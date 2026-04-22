# frozen_string_literal: true

require "ruby_llm"
require_relative "cost_tracker"
require_relative "system_prompt_builder"
require_relative "../errors"
require_relative "../models/stream_events"
require_relative "../api/retry_handler"

module Openharness
  module Rb
    module Engine
      class QueryEngine
        include Api::RetryHandler

        attr_reader :cost_tracker, :chat

        # @param model [String] RubyLLM model identifier (e.g. "gpt-4o", "claude-sonnet-4-20250514")
        # @param tools [Array<Class<RubyLLM::Tool>>] tool classes to register with the chat
        # @param system_prompt [String, nil] explicit system prompt (overrides builder)
        # @param system_prompt_builder [SystemPromptBuilder, nil] builds system prompt from context
        # @param provider_config [Hash, nil] API keys for RubyLLM configuration
        def initialize(model:, tools: [], system_prompt: nil, system_prompt_builder: nil, provider_config: nil)
          configure_ruby_llm(provider_config) if provider_config

          @model = model
          @tools = tools
          @cost_tracker = CostTracker.new

          prompt = system_prompt || system_prompt_builder&.build
          @chat = RubyLLM.chat(model: @model)
          @chat.with_instructions(prompt) if prompt
          @chat.with_tools(*@tools) unless @tools.empty?
        end

        # Ask a question. RubyLLM handles the full tool-calling loop internally.
        # Yields StreamEvent instances for real-time UI updates.
        # Returns the final RubyLLM::Message.
        def ask(message, &event_handler)
          with_retry do
            @chat.on_tool_call do |tool_call|
              event_handler&.call(Models::ToolExecutionStarted.new(
                tool_name: tool_call.name.to_s,
                tool_use_id: tool_call.id.to_s
              ))
            end

            @chat.on_tool_result do |result|
              event_handler&.call(Models::ToolExecutionCompleted.new(
                tool_use_id: "latest",
                result: Models::ToolResult.new(text: result.to_s)
              ))
            end

            response = @chat.ask(message) do |chunk|
              if chunk.content
                event_handler&.call(Models::AssistantTextDelta.new(text: chunk.content))
              end
            end

            # Track usage if available
            if response.respond_to?(:input_tokens)
              @cost_tracker.record(
                input_tokens: response.input_tokens || 0,
                output_tokens: response.output_tokens || 0,
                cost: 0.0
              )
            end

            event_handler&.call(Models::AssistantTurnComplete.new(stop_reason: "end_turn"))
            response
          end
        end

        # Reset conversation history (starts a fresh chat with same config)
        def clear!
          prompt = @chat.respond_to?(:instructions) ? @chat.instructions : nil
          @chat = RubyLLM.chat(model: @model)
          @chat.with_instructions(prompt) if prompt
          @chat.with_tools(*@tools) unless @tools.empty?
        end

        # Add a tool to the chat at runtime
        def add_tool(tool)
          @tools << tool
          @chat.with_tool(tool)
        end

        private

        def configure_ruby_llm(config)
          RubyLLM.configure do |c|
            c.openai_api_key = config[:openai_api_key] if config[:openai_api_key]
            c.anthropic_api_key = config[:anthropic_api_key] if config[:anthropic_api_key]
            c.gemini_api_key = config[:gemini_api_key] if config[:gemini_api_key]
          end
        end
      end
    end
  end
end
