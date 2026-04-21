# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Openharness
  module Rb
    module Session
      # **Validates: Requirements 38.3**
      # Property 7: Session storage round-trip — save then load produces equivalent state
      class TestSessionStorageRoundTrip < Minitest::Test
        VALID_ROLES = %w[user assistant system].freeze
        BLOCK_TYPES = %w[text image tool_use tool_result].freeze

        def setup
          @tmpdir = Dir.mktmpdir("session_test")
          @storage = SessionStorage.new(directory: @tmpdir)
        end

        def teardown
          FileUtils.rm_rf(@tmpdir)
        end

        def random_content_hash
          keys = %w[text url id name]
          selected = keys.sample(rand(1..3))
          selected.each_with_object({}) { |k, h| h[k.to_sym] = "val_#{rand(1000)}" }
        end

        def random_content_block
          Models::ContentBlock.new(
            type: BLOCK_TYPES.sample,
            content: random_content_hash
          )
        end

        def random_message
          role = VALID_ROLES.sample
          blocks = Array.new(rand(1..3)) { random_content_block }
          Models::ConversationMessage.new(role: role, content_blocks: blocks)
        end

        def random_cost_tracker
          tracker = Engine::CostTracker.new
          rand(1..5).times do
            tracker.record(
              input_tokens: rand(1..1000),
              output_tokens: rand(1..500),
              cost: rand * 10.0
            )
          end
          tracker
        end

        def test_round_trip_property
          100.times do |i|
            session_id = "test-session-#{i}"
            messages = Array.new(rand(1..5)) { random_message }
            cost_tracker = random_cost_tracker
            metadata = { "run" => i, "tag" => "test_#{rand(100)}" }

            @storage.save(session_id, messages: messages, cost_tracker: cost_tracker, metadata: metadata)
            loaded = @storage.load(session_id)

            # Verify messages round-trip
            assert_equal messages.size, loaded[:messages].size,
                         "Iteration #{i}: message count mismatch"

            messages.zip(loaded[:messages]).each_with_index do |(orig, rest), j|
              assert_equal orig.role, rest.role,
                           "Iteration #{i}, msg #{j}: role mismatch"
              assert_equal orig.content_blocks.size, rest.content_blocks.size,
                           "Iteration #{i}, msg #{j}: block count mismatch"

              orig.content_blocks.zip(rest.content_blocks).each_with_index do |(ob, rb), k|
                assert_equal ob.type, rb.type,
                             "Iteration #{i}, msg #{j}, block #{k}: type mismatch"
                assert_equal ob.content, rb.content,
                             "Iteration #{i}, msg #{j}, block #{k}: content mismatch"
              end
            end

            # Verify cost round-trip
            expected_cost = cost_tracker.summary
            assert_equal expected_cost[:input_tokens], loaded[:cost][:input_tokens],
                         "Iteration #{i}: input_tokens mismatch"
            assert_equal expected_cost[:output_tokens], loaded[:cost][:output_tokens],
                         "Iteration #{i}: output_tokens mismatch"
            assert_in_delta expected_cost[:total_cost], loaded[:cost][:total_cost], 0.001,
                           "Iteration #{i}: total_cost mismatch"
          end
        end
      end

      # Test SessionStorage raises SessionNotFoundError for missing session
      class TestSessionStorageNotFound < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir("session_test")
          @storage = SessionStorage.new(directory: @tmpdir)
        end

        def teardown
          FileUtils.rm_rf(@tmpdir)
        end

        def test_load_missing_session_raises
          assert_raises(SessionNotFoundError) do
            @storage.load("nonexistent-session-id")
          end
        end

        def test_load_missing_session_error_message
          err = assert_raises(SessionNotFoundError) do
            @storage.load("missing-123")
          end
          assert_match(/missing-123/, err.message)
        end
      end

      # Test BackgroundTaskManager start/stop/list lifecycle
      class TestBackgroundTaskManagerLifecycle < Minitest::Test
        def setup
          @manager = BackgroundTaskManager.new
        end

        def teardown
          @manager.list.each { |t| @manager.stop(t[:name]) }
        end

        def test_start_and_list
          @manager.start(name: "sleeper", command: "sleep 10", cwd: Dir.pwd)
          tasks = @manager.list
          assert_equal 1, tasks.size
          assert_equal "sleeper", tasks.first[:name]
          assert_equal :running, tasks.first[:status]
        end

        def test_start_duplicate_raises
          @manager.start(name: "dup", command: "sleep 10", cwd: Dir.pwd)
          assert_raises(DuplicateTaskError) do
            @manager.start(name: "dup", command: "sleep 10", cwd: Dir.pwd)
          end
        end

        def test_stop_removes_task
          @manager.start(name: "stopper", command: "sleep 10", cwd: Dir.pwd)
          assert_equal 1, @manager.list.size

          @manager.stop("stopper")
          assert_equal 0, @manager.list.size
        end

        def test_output_captures_stdout
          @manager.start(name: "echo_task", command: "echo hello_world", cwd: Dir.pwd)
          # Give the process a moment to produce output
          sleep 0.5
          out = @manager.output("echo_task")
          assert_includes out, "hello_world"
        end

        def test_list_empty_initially
          assert_equal [], @manager.list
        end

        def test_multiple_tasks
          @manager.start(name: "task1", command: "sleep 10", cwd: Dir.pwd)
          @manager.start(name: "task2", command: "sleep 10", cwd: Dir.pwd)
          assert_equal 2, @manager.list.size
          names = @manager.list.map { |t| t[:name] }
          assert_includes names, "task1"
          assert_includes names, "task2"
        end
      end

      # Test BackgroundTaskManager raises TaskNotFoundError
      class TestBackgroundTaskManagerNotFound < Minitest::Test
        def setup
          @manager = BackgroundTaskManager.new
        end

        def test_stop_unknown_raises
          assert_raises(TaskNotFoundError) do
            @manager.stop("nonexistent")
          end
        end

        def test_output_unknown_raises
          assert_raises(TaskNotFoundError) do
            @manager.output("nonexistent")
          end
        end
      end
    end
  end
end
