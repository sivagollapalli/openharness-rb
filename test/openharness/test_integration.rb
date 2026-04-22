# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    # A simple RubyLLM::Tool for integration testing
    class IntegrationEchoTool < RubyLLM::Tool
      description "Echoes input text back"

      param :text, desc: "Text to echo"

      def execute(text:)
        "Echo: #{text}"
      end
    end

    class TestIntegrationQueryEngine < Minitest::Test
      def test_query_engine_initializes_with_tools_and_system_prompt
        engine = Engine::QueryEngine.new(
          model: "gpt-4o",
          tools: [IntegrationEchoTool],
          system_prompt: "You are a helpful assistant.",
          provider_config: { openai_api_key: "sk-test" }
        )

        # Verify chat was created with tools
        assert_equal 1, engine.chat.tools.length
        assert_equal "integration_echo_tool", engine.chat.tools.first.name

        # Verify cost tracker starts at zero
        assert_equal 0, engine.cost_tracker.input_tokens
        assert_equal 0, engine.cost_tracker.output_tokens
      end

      def test_query_engine_clear_resets_conversation
        engine = Engine::QueryEngine.new(
          model: "gpt-4o",
          tools: [IntegrationEchoTool],
          system_prompt: "You are helpful.",
          provider_config: { openai_api_key: "sk-test" }
        )

        engine.clear!

        # After clear, tools should still be registered
        assert_equal 1, engine.chat.tools.length
      end

      def test_query_engine_add_tool_at_runtime
        engine = Engine::QueryEngine.new(
          model: "gpt-4o",
          provider_config: { openai_api_key: "sk-test" }
        )

        assert_equal 0, engine.chat.tools.length

        engine.add_tool(IntegrationEchoTool)
        assert_equal 1, engine.chat.tools.length
      end

      def test_harness_wires_query_engine_with_default_tools
        harness = Harness.new(api_key: "sk-test", model: "gpt-4o")

        # Should have all 11 default tools
        assert_equal 11, harness.query_engine.chat.tools.length

        # Cost tracker accessible through harness
        assert_equal 0, harness.cost_tracker.input_tokens
      end

      def test_harness_add_tool
        harness = Harness.new(api_key: "sk-test", model: "gpt-4o")
        initial_count = harness.query_engine.chat.tools.length

        harness.add_tool(IntegrationEchoTool)
        assert_equal initial_count + 1, harness.query_engine.chat.tools.length
      end

      def test_harness_clear
        harness = Harness.new(api_key: "sk-test", model: "gpt-4o")
        tool_count = harness.query_engine.chat.tools.length

        harness.clear!

        # Tools should be preserved after clear
        assert_equal tool_count, harness.query_engine.chat.tools.length
      end
    end
  end
end
