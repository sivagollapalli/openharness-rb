# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    module Engine
      # Simple stub for ApiAdapter used in tests
      class StubApiAdapter
        attr_reader :calls

        def initialize(responses: [])
          @responses = responses
          @call_index = 0
          @calls = []
        end

        def stream_messages(messages, tools: [], &block)
          @calls << { messages: messages, tools: tools }
          response = @responses[@call_index] || @responses.last
          @call_index += 1

          # Yield stream events if provided
          if response[:stream_events]
            response[:stream_events].each { |e| block&.call(e) }
          end

          response[:result]
        end
      end

      # Simple stub for ToolRegistry used in tests
      class StubToolRegistry
        attr_reader :execute_calls

        def initialize(results: {})
          @results = results
          @execute_calls = []
        end

        def schemas
          []
        end

        def execute(name, input, context)
          @execute_calls << { name: name, input: input, context: context }
          @results[name] || Models::ToolResult.new(text: "ok")
        end
      end

      # Simple stub for PermissionChecker
      class StubPermissionChecker
        def evaluate(**_args)
          Permissions::PermissionDecision.new(status: "allowed", reason: nil)
        end
      end

      class TestQueryEngineAppendsUserMessage < Minitest::Test
        # **Validates: Requirements 4.1**

        def test_run_query_appends_user_message_and_calls_api
          text_response = {
            content_blocks: [
              Models::ContentBlock.new(type: "text", content: { text: "Hello!" })
            ]
          }

          api = StubApiAdapter.new(responses: [{ result: text_response }])
          tools = StubToolRegistry.new
          perms = StubPermissionChecker.new
          context = Models::QueryContext.new(max_turns: 10)

          engine = QueryEngine.new(
            api_adapter: api,
            tool_registry: tools,
            permission_checker: perms,
            context: context
          )

          engine.run_query("What is Ruby?")

          # Verify user message was appended
          assert_equal 2, engine.messages.length # user + assistant
          assert_equal "user", engine.messages[0].role
          assert_equal "text", engine.messages[0].content_blocks[0].type
          assert_equal({ text: "What is Ruby?" }, engine.messages[0].content_blocks[0].content)

          # Verify API was called
          assert_equal 1, api.calls.length
        end
      end

      class TestQueryEngineExecutesTools < Minitest::Test
        # **Validates: Requirements 4.2**

        def test_run_query_executes_tools_when_response_contains_tool_use
          tool_response = {
            content_blocks: [
              Models::ContentBlock.new(
                type: "tool_use",
                content: { id: "tu_1", name: "read_file", input: { path: "test.rb" } }
              )
            ]
          }

          final_response = {
            content_blocks: [
              Models::ContentBlock.new(type: "text", content: { text: "File contents are..." })
            ]
          }

          api = StubApiAdapter.new(responses: [
            { result: tool_response },
            { result: final_response }
          ])

          tool_result = Models::ToolResult.new(text: "file content here")
          tools = StubToolRegistry.new(results: { "read_file" => tool_result })
          perms = StubPermissionChecker.new
          context = Models::QueryContext.new(max_turns: 10)

          engine = QueryEngine.new(
            api_adapter: api,
            tool_registry: tools,
            permission_checker: perms,
            context: context
          )

          events = []
          engine.run_query("Read test.rb") { |e| events << e }

          # Tool was executed
          assert_equal 1, tools.execute_calls.length
          assert_equal "read_file", tools.execute_calls[0][:name]
          assert_equal({ path: "test.rb" }, tools.execute_calls[0][:input])

          # ToolExecutionStarted and ToolExecutionCompleted events emitted
          started_events = events.select { |e| e.is_a?(Models::ToolExecutionStarted) }
          completed_events = events.select { |e| e.is_a?(Models::ToolExecutionCompleted) }
          assert_equal 1, started_events.length
          assert_equal "read_file", started_events[0].tool_name
          assert_equal 1, completed_events.length
          assert_equal "tu_1", completed_events[0].tool_use_id

          # API was called twice (once with tool_use, once with final)
          assert_equal 2, api.calls.length

          # Tool result was appended to messages
          tool_result_msg = engine.messages.find do |m|
            m.role == "user" && m.content_blocks.any? { |b| b.type == "tool_result" }
          end
          refute_nil tool_result_msg
        end
      end

      class TestQueryEngineEmitsAssistantTurnComplete < Minitest::Test
        # **Validates: Requirements 4.3**

        def test_run_query_emits_assistant_turn_complete_when_no_tool_use
          text_response = {
            content_blocks: [
              Models::ContentBlock.new(type: "text", content: { text: "Just text" })
            ]
          }

          api = StubApiAdapter.new(responses: [{ result: text_response }])
          tools = StubToolRegistry.new
          perms = StubPermissionChecker.new
          context = Models::QueryContext.new(max_turns: 10)

          engine = QueryEngine.new(
            api_adapter: api,
            tool_registry: tools,
            permission_checker: perms,
            context: context
          )

          events = []
          engine.run_query("Hello") { |e| events << e }

          turn_complete = events.select { |e| e.is_a?(Models::AssistantTurnComplete) }
          assert_equal 1, turn_complete.length
          assert_equal "end_turn", turn_complete[0].stop_reason
        end
      end

      class TestQueryEngineMaxTurnsExceeded < Minitest::Test
        # **Validates: Requirements 4.5**

        def test_run_query_raises_max_turns_exceeded
          # Always return tool_use to force the loop to keep going
          tool_response = {
            content_blocks: [
              Models::ContentBlock.new(
                type: "tool_use",
                content: { id: "tu_1", name: "read_file", input: { path: "x.rb" } }
              )
            ]
          }

          api = StubApiAdapter.new(responses: [{ result: tool_response }])
          tools = StubToolRegistry.new
          perms = StubPermissionChecker.new
          context = Models::QueryContext.new(max_turns: 2)

          engine = QueryEngine.new(
            api_adapter: api,
            tool_registry: tools,
            permission_checker: perms,
            context: context
          )

          assert_raises(MaxTurnsExceeded) do
            engine.run_query("Do something")
          end

          # Should have attempted max_turns + 1 iterations before raising
          assert_operator engine.turn_count, :<=, 3
        end
      end
    end
  end
end
