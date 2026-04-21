# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    # Stub API adapter that simulates: tool_use response → final text response
    class MockLlmAdapter
      attr_reader :calls

      def initialize
        @calls = []
        @call_index = 0
      end

      def stream_messages(messages, tools: [], &block)
        @calls << { messages: messages.dup, tools: tools }
        @call_index += 1

        if @call_index == 1
          # First call: return a tool_use block
          tool_use_response = {
            content_blocks: [
              Models::ContentBlock.new(
                type: "tool_use",
                content: { id: "call_1", name: "echo_tool", input: { text: "hello world" } }
              )
            ]
          }
          tool_use_response
        else
          # Subsequent calls: return final text
          {
            content_blocks: [
              Models::ContentBlock.new(
                type: "text",
                content: { text: "The echo tool returned: hello world" }
              )
            ]
          }
        end
      end
    end

    # A simple tool for integration testing
    class EchoTool < Tools::BaseTool
      def name = "echo_tool"
      def description = "Echoes input text"
      def input_schema = { type: "object", properties: { text: { type: "string" } }, required: ["text"] }

      def execute(input, _context)
        Models::ToolResult.new(text: "Echo: #{input[:text] || input['text']}")
      end
    end

    class TestIntegrationFullQueryCycle < Minitest::Test
      def test_full_query_cycle_with_mocked_llm
        # Setup components
        mock_api = MockLlmAdapter.new
        tool_registry = Tools::ToolRegistry.new
        tool_registry.register(EchoTool.new)

        permission_checker = Permissions::PermissionChecker.new(
          mode: Permissions::PermissionMode::FULL_AUTO
        )

        context = Models::QueryContext.new(max_turns: 10)

        engine = Engine::QueryEngine.new(
          api_adapter: mock_api,
          tool_registry: tool_registry,
          permission_checker: permission_checker,
          context: context
        )

        # Collect events
        events = []
        engine.run_query("Please echo hello world") { |e| events << e }

        # Verify: API was called twice (tool_use → final answer)
        assert_equal 2, mock_api.calls.length

        # Verify: tool was executed
        tool_started = events.select { |e| e.is_a?(Models::ToolExecutionStarted) }
        assert_equal 1, tool_started.length
        assert_equal "echo_tool", tool_started.first.tool_name

        tool_completed = events.select { |e| e.is_a?(Models::ToolExecutionCompleted) }
        assert_equal 1, tool_completed.length
        assert_equal "Echo: hello world", tool_completed.first.result.text

        # Verify: turn complete event emitted
        turn_complete = events.select { |e| e.is_a?(Models::AssistantTurnComplete) }
        assert_equal 1, turn_complete.length
        assert_equal "end_turn", turn_complete.first.stop_reason

        # Verify: conversation history has correct structure
        # user message → assistant (tool_use) → user (tool_result) → assistant (final)
        assert_equal 4, engine.messages.length
        assert_equal "user", engine.messages[0].role
        assert_equal "assistant", engine.messages[1].role
        assert_equal "user", engine.messages[2].role
        assert_equal "tool_result", engine.messages[2].content_blocks[0].type
        assert_equal "assistant", engine.messages[3].role
        assert_equal "text", engine.messages[3].content_blocks[0].type
      end
    end
  end
end
