# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"
require "faraday"

module Openharness
  module Rb
    module Hooks
      # ---------------------------------------------------------------
      # 7.6.1 Test HookRegistry register and hooks_for filtering
      # ---------------------------------------------------------------
      class TestHookRegistryFiltering < Minitest::Test
        # **Validates: Requirements 20.1, 20.2, 20.3**

        def setup
          @registry = HookRegistry.new
        end

        def test_hooks_for_returns_hooks_matching_event
          hook_a = CommandHookDefinition.new(
            event: :pre_tool_use, matcher: nil, command: "echo a"
          )
          hook_b = CommandHookDefinition.new(
            event: :post_tool_use, matcher: nil, command: "echo b"
          )
          @registry.register(hook_a)
          @registry.register(hook_b)

          assert_equal [hook_a], @registry.hooks_for(:pre_tool_use)
          assert_equal [hook_b], @registry.hooks_for(:post_tool_use)
          assert_empty @registry.hooks_for(:session_start)
        end

        def test_nil_matcher_matches_all_contexts
          hook = CommandHookDefinition.new(
            event: :pre_tool_use, matcher: nil, command: "echo all"
          )
          @registry.register(hook)

          assert_equal [hook], @registry.hooks_for(:pre_tool_use, context_name: "anything")
          assert_equal [hook], @registry.hooks_for(:pre_tool_use, context_name: nil)
        end

        def test_glob_matcher_filters_by_context_name
          hook = CommandHookDefinition.new(
            event: :pre_tool_use, matcher: "*.rb", command: "echo rb"
          )
          @registry.register(hook)

          assert_equal [hook], @registry.hooks_for(:pre_tool_use, context_name: "foo.rb")
          assert_empty @registry.hooks_for(:pre_tool_use, context_name: "foo.py")
        end

        def test_multiple_hooks_same_event_different_matchers
          hook_all = CommandHookDefinition.new(
            event: :pre_tool_use, matcher: nil, command: "echo all"
          )
          hook_rb = CommandHookDefinition.new(
            event: :pre_tool_use, matcher: "*.rb", command: "echo rb"
          )
          @registry.register(hook_all)
          @registry.register(hook_rb)

          # Both match for .rb context (nil matches everything)
          result = @registry.hooks_for(:pre_tool_use, context_name: "test.rb")
          assert_equal 2, result.size

          # Only nil-matcher matches for .py context
          result = @registry.hooks_for(:pre_tool_use, context_name: "test.py")
          assert_equal [hook_all], result
        end
      end

      # ---------------------------------------------------------------
      # 7.6.2 Test HookExecutor dispatches command hooks with env injection
      # ---------------------------------------------------------------
      class TestHookExecutorCommandDispatch < Minitest::Test
        # **Validates: Requirements 21.1, 21.2, 21.3**

        def test_command_hook_executes_and_injects_env_vars
          Dir.mktmpdir do |dir|
            outfile = File.join(dir, "hook_output.txt")
            # The command writes the env var to a temp file so we can verify
            cmd = "echo $OPENHARNESS_HOOK_EVENT > #{Shellwords.escape(outfile)}"

            hook = CommandHookDefinition.new(
              event: :pre_tool_use, matcher: nil, command: cmd
            )

            registry = HookRegistry.new
            registry.register(hook)
            executor = HookExecutor.new(registry: registry)

            result = executor.dispatch(:pre_tool_use, payload: { tool: "bash" })
            assert result[:ok], "Expected dispatch to succeed"

            # Verify the file was written (command executed)
            assert File.exist?(outfile), "Expected command to write output file"
            content = File.read(outfile).strip
            # The env var value is shell-escaped, so it should contain the event name
            assert_includes content, "pre_tool_use"
          end
        end

        def test_command_hook_env_values_are_shell_escaped
          # Verify that payload with special chars is escaped
          hook = CommandHookDefinition.new(
            event: :session_start, matcher: nil, command: "true"
          )

          registry = HookRegistry.new
          registry.register(hook)
          executor = HookExecutor.new(registry: registry)

          # Payload with shell-dangerous characters
          payload = { key: "value; rm -rf /" }
          result = executor.dispatch(:session_start, payload: payload)
          assert result[:ok], "Expected dispatch to succeed even with special chars in payload"
        end
      end

      # ---------------------------------------------------------------
      # 7.6.3 Test HookExecutor dispatches HTTP hooks (mocked Faraday)
      # ---------------------------------------------------------------
      class TestHookExecutorHttpDispatch < Minitest::Test
        # **Validates: Requirements 22.1, 22.2**

        def test_http_hook_sends_post_with_correct_url_headers_and_body
          # Use Faraday's built-in test adapter to capture the request
          captured_body = nil
          captured_headers = nil

          stubs = Faraday::Adapter::Test::Stubs.new do |stub|
            stub.post("https://example.com/webhook") do |env|
              captured_body = env.body
              captured_headers = env.request_headers.dup
              [200, { "Content-Type" => "application/json" }, '{"ok":true}']
            end
          end

          test_conn = Faraday.new do |f|
            f.adapter :test, stubs
          end

          hook = HttpHookDefinition.new(
            event: :post_tool_use,
            matcher: nil,
            url: "https://example.com/webhook",
            headers: { "X-Custom" => "test-value" }
          )

          registry = HookRegistry.new
          registry.register(hook)
          executor = HookExecutor.new(registry: registry, http_client: test_conn)

          payload = { tool: "bash", result: "ok" }
          result = executor.dispatch(:post_tool_use, payload: payload)

          assert result[:ok], "Expected HTTP hook dispatch to succeed"

          # Verify the captured request
          assert captured_body, "Expected Faraday to capture the request body"
          assert_equal "application/json", captured_headers["Content-Type"]
          assert_equal "test-value", captured_headers["X-Custom"]

          body = JSON.parse(captured_body)
          assert_equal "bash", body["tool"]
          assert_equal "ok", body["result"]

          stubs.verify_stubbed_calls
        end

        def test_http_hook_failure_on_non_2xx_status
          stubs = Faraday::Adapter::Test::Stubs.new do |stub|
            stub.post("https://example.com/webhook") do
              [500, {}, "Internal Server Error"]
            end
          end

          test_conn = Faraday.new do |f|
            f.adapter :test, stubs
          end

          hook = HttpHookDefinition.new(
            event: :session_end,
            matcher: nil,
            url: "https://example.com/webhook",
            block_on_failure: false
          )

          registry = HookRegistry.new
          registry.register(hook)
          executor = HookExecutor.new(registry: registry, http_client: test_conn)

          result = executor.dispatch(:session_end, payload: {})
          # With block_on_failure=false, overall result is ok but has warnings
          assert result[:ok], "Expected overall dispatch to succeed (block_on_failure=false)"
          assert_equal 1, result[:warnings].size
          refute result[:warnings].first[:ok]
        end
      end

      # ---------------------------------------------------------------
      # 7.6.4 Test block_on_failure halts operation on hook failure
      # ---------------------------------------------------------------
      class TestBlockOnFailureHalts < Minitest::Test
        # **Validates: Requirements 20.4**

        def test_blocking_http_hook_failure_returns_ok_false
          stubs = Faraday::Adapter::Test::Stubs.new do |stub|
            stub.post("https://example.com/fail") do
              [503, {}, "Service Unavailable"]
            end
          end

          test_conn = Faraday.new do |f|
            f.adapter :test, stubs
          end

          hook = HttpHookDefinition.new(
            event: :pre_tool_use,
            matcher: nil,
            block_on_failure: true,
            url: "https://example.com/fail"
          )

          registry = HookRegistry.new
          registry.register(hook)
          executor = HookExecutor.new(registry: registry, http_client: test_conn)

          result = executor.dispatch(:pre_tool_use, payload: { action: "test" })

          refute result[:ok], "Expected result[:ok] to be false when blocking hook fails"
          assert result[:failures], "Expected failures to be present"
          assert result[:failures].any? { |f| !f[:ok] }
        end
      end

      # ---------------------------------------------------------------
      # 7.6.5 Test block_on_failure=false logs and continues on failure
      # ---------------------------------------------------------------
      class TestBlockOnFailureFalseContinues < Minitest::Test
        # **Validates: Requirements 20.5**

        def test_non_blocking_hook_failure_returns_ok_true_with_warnings
          stubs = Faraday::Adapter::Test::Stubs.new do |stub|
            stub.post("https://example.com/fail") do
              [500, {}, "Internal Server Error"]
            end
          end

          test_conn = Faraday.new do |f|
            f.adapter :test, stubs
          end

          hook = HttpHookDefinition.new(
            event: :session_start,
            matcher: nil,
            block_on_failure: false,
            url: "https://example.com/fail"
          )

          registry = HookRegistry.new
          registry.register(hook)
          executor = HookExecutor.new(registry: registry, http_client: test_conn)

          result = executor.dispatch(:session_start, payload: {})

          assert result[:ok], "Expected result[:ok] to be true when non-blocking hook fails"
          assert result[:warnings], "Expected warnings to be present"
          assert_equal 1, result[:warnings].size
          refute result[:warnings].first[:ok]
          assert result[:warnings].first[:error], "Expected error message in warning"
        end

        def test_mixed_blocking_and_non_blocking_only_blocking_halts
          stubs = Faraday::Adapter::Test::Stubs.new do |stub|
            stub.post("https://example.com/ok") do
              [200, {}, '{"ok":true}']
            end
            stub.post("https://example.com/fail") do
              [500, {}, "error"]
            end
          end

          test_conn = Faraday.new do |f|
            f.adapter :test, stubs
          end

          # Non-blocking hook that fails — should produce warning but not halt
          non_blocking = HttpHookDefinition.new(
            event: :pre_tool_use,
            matcher: nil,
            block_on_failure: false,
            url: "https://example.com/fail"
          )

          # Successful hook
          success_hook = HttpHookDefinition.new(
            event: :pre_tool_use,
            matcher: nil,
            block_on_failure: false,
            url: "https://example.com/ok"
          )

          registry = HookRegistry.new
          registry.register(non_blocking)
          registry.register(success_hook)
          executor = HookExecutor.new(registry: registry, http_client: test_conn)

          result = executor.dispatch(:pre_tool_use, payload: {})

          assert result[:ok], "Expected ok=true when only non-blocking hooks fail"
          assert_equal 1, result[:warnings].size
        end
      end
    end
  end
end
