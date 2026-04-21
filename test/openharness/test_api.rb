# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    module Api
      class TestProviderRegistryDetection < Minitest::Test
        # **Validates: Requirements 8.2, 8.3**
        # Property 14: For all API keys with a known prefix, detect_provider returns
        # the correct provider. For all keys with unknown prefixes, detect_provider
        # raises UnknownProviderError.

        KNOWN_PREFIXES = {
          "anthropic" => "sk-ant-",
          "openai" => "sk-",
          "gemini" => "AI",
        }.freeze

        def setup
          @registry = ProviderRegistry.new
        end

        def random_suffix(length = 20)
          chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
          Array.new(length) { chars.sample }.join
        end

        def test_known_prefixes_return_correct_provider
          100.times do |i|
            KNOWN_PREFIXES.each do |expected_name, prefix|
              key = "#{prefix}#{random_suffix}"
              result = @registry.detect_provider(api_key: key)

              assert_instance_of ProviderSpec, result,
                                 "Iteration #{i}: expected ProviderSpec for prefix '#{prefix}'"
              assert_equal expected_name, result.name,
                           "Iteration #{i}: expected provider '#{expected_name}' for key '#{key}'"
            end
          end
        end

        def test_anthropic_prefix_takes_priority_over_openai
          # sk-ant- starts with sk- but should match anthropic (longer prefix)
          50.times do
            key = "sk-ant-#{random_suffix}"
            result = @registry.detect_provider(api_key: key)
            assert_equal "anthropic", result.name,
                         "sk-ant- prefix should match anthropic, not openai"
          end
        end

        def test_unknown_prefixes_raise_error
          # Generate prefixes that don't match any known provider
          unknown_prefixes = %w[gsk- xai- hf- BEARER- tok- abc123]
          100.times do |i|
            prefix = unknown_prefixes.sample
            key = "#{prefix}#{random_suffix}"
            assert_raises(UnknownProviderError,
                          "Iteration #{i}: expected UnknownProviderError for key '#{key}'") do
              @registry.detect_provider(api_key: key)
            end
          end
        end
      end

      class TestRetryDelayBounds < Minitest::Test
        # **Validates: Requirements 9**
        # Property 9: The computed delay for attempt N is always
        # >= base_delay * 2^N and <= base_delay * 2^N + 1.0 (jitter bound)

        # Helper class that includes RetryHandler so we can test it
        class RetryTester
          include RetryHandler

          attr_reader :captured_delays

          def initialize
            @captured_delays = []
          end

          # Override sleep to capture delay values instead of actually sleeping
          def sleep(seconds)
            @captured_delays << seconds
          end
        end

        def test_delay_bounds_property
          50.times do |i|
            tester = RetryTester.new
            base_delay = [0.1, 0.5, 1.0, 2.0].sample
            max_retries = rand(1..4)

            # Force failures to trigger retries, then succeed
            call_count = 0
            begin
              tester.with_retry(max_retries: max_retries, base_delay: base_delay) do
                call_count += 1
                raise StandardError, "test error" if call_count <= max_retries
                :success
              end
            rescue StandardError
              # If all retries exhausted, that's fine too
            end

            tester.captured_delays.each_with_index do |delay, idx|
              attempt = idx + 1 # attempts is 1-indexed after first increment
              min_delay = base_delay * (2**attempt)
              max_delay = min_delay + 1.0

              assert delay >= min_delay,
                     "Iteration #{i}, attempt #{attempt}: delay #{delay} < min #{min_delay}"
              assert delay <= max_delay,
                     "Iteration #{i}, attempt #{attempt}: delay #{delay} > max #{max_delay}"
            end
          end
        end
      end

      class TestRetryHandlerNonRetryable < Minitest::Test
        # **Validates: Requirements 44**
        # Test that RetryHandler does not retry on 401/400 (AuthenticationFailure
        # and non-retryable error classes)

        class RetryTester
          include RetryHandler

          attr_reader :sleep_count

          def initialize
            @sleep_count = 0
          end

          def sleep(seconds)
            @sleep_count += 1
          end
        end

        def test_authentication_failure_raises_immediately
          tester = RetryTester.new
          call_count = 0

          assert_raises(AuthenticationFailure) do
            tester.with_retry(max_retries: 3) do
              call_count += 1
              raise AuthenticationFailure, "Invalid API key"
            end
          end

          assert_equal 1, call_count, "Should only call block once (no retries)"
          assert_equal 0, tester.sleep_count, "Should not sleep on non-retryable error"
        end

        def test_unauthorized_error_raises_immediately
          # Simulate RubyLLM::UnauthorizedError (401)
          stub_error_class = Class.new(StandardError)
          # Set the class name to match NON_RETRYABLE_ERRORS
          stub_error_class.define_singleton_method(:name) { "RubyLLM::UnauthorizedError" }

          tester = RetryTester.new
          call_count = 0

          error_instance = stub_error_class.new("Unauthorized")
          # Ensure the instance reports the correct class name
          error_instance.define_singleton_method(:class) { stub_error_class }

          assert_raises(stub_error_class) do
            tester.with_retry(max_retries: 3) do
              call_count += 1
              raise error_instance
            end
          end

          assert_equal 1, call_count, "Should only call block once for 401 error"
          assert_equal 0, tester.sleep_count, "Should not sleep on 401 error"
        end

        def test_bad_request_error_raises_immediately
          # Simulate RubyLLM::BadRequestError (400)
          stub_error_class = Class.new(StandardError)
          stub_error_class.define_singleton_method(:name) { "RubyLLM::BadRequestError" }

          tester = RetryTester.new
          call_count = 0

          error_instance = stub_error_class.new("Bad request")
          error_instance.define_singleton_method(:class) { stub_error_class }

          assert_raises(stub_error_class) do
            tester.with_retry(max_retries: 3) do
              call_count += 1
              raise error_instance
            end
          end

          assert_equal 1, call_count, "Should only call block once for 400 error"
          assert_equal 0, tester.sleep_count, "Should not sleep on 400 error"
        end
      end

      class TestLlmAdapterConfiguration < Minitest::Test
        # **Validates: Requirements 7.1**
        # Test that creating LlmAdapter with provider_config calls RubyLLM.configure

        def test_configure_passes_openai_key
          configured = {}

          # Stub RubyLLM.configure to capture what keys are set
          config_obj = Struct.new(:openai_api_key, :anthropic_api_key, :gemini_api_key).new
          RubyLLM.stub(:configure, proc { |&block| block.call(config_obj) }) do
            LlmAdapter.new(provider_config: { openai_api_key: "sk-test-key-123" })
          end

          assert_equal "sk-test-key-123", config_obj.openai_api_key
          assert_nil config_obj.anthropic_api_key
          assert_nil config_obj.gemini_api_key
        end

        def test_configure_passes_anthropic_key
          config_obj = Struct.new(:openai_api_key, :anthropic_api_key, :gemini_api_key).new
          RubyLLM.stub(:configure, proc { |&block| block.call(config_obj) }) do
            LlmAdapter.new(provider_config: { anthropic_api_key: "sk-ant-test-456" })
          end

          assert_nil config_obj.openai_api_key
          assert_equal "sk-ant-test-456", config_obj.anthropic_api_key
          assert_nil config_obj.gemini_api_key
        end

        def test_configure_passes_gemini_key
          config_obj = Struct.new(:openai_api_key, :anthropic_api_key, :gemini_api_key).new
          RubyLLM.stub(:configure, proc { |&block| block.call(config_obj) }) do
            LlmAdapter.new(provider_config: { gemini_api_key: "AItest789" })
          end

          assert_nil config_obj.openai_api_key
          assert_nil config_obj.anthropic_api_key
          assert_equal "AItest789", config_obj.gemini_api_key
        end

        def test_configure_passes_multiple_keys
          config_obj = Struct.new(:openai_api_key, :anthropic_api_key, :gemini_api_key).new
          RubyLLM.stub(:configure, proc { |&block| block.call(config_obj) }) do
            LlmAdapter.new(provider_config: {
              openai_api_key: "sk-openai",
              anthropic_api_key: "sk-ant-anthropic",
              gemini_api_key: "AIgemini",
            })
          end

          assert_equal "sk-openai", config_obj.openai_api_key
          assert_equal "sk-ant-anthropic", config_obj.anthropic_api_key
          assert_equal "AIgemini", config_obj.gemini_api_key
        end

        def test_no_config_does_not_call_configure
          configure_called = false
          RubyLLM.stub(:configure, proc { configure_called = true }) do
            LlmAdapter.new(model: "gpt-4o")
          end

          refute configure_called, "RubyLLM.configure should not be called without provider_config"
        end
      end
    end
  end
end
