# frozen_string_literal: true

require "ruby_llm"
require_relative "../models/stream_events"
require_relative "retry_handler"

module Openharness
  module Rb
    module Api
      class LlmAdapter
        include RetryHandler

        def initialize(model: nil, provider_config: nil)
          configure_ruby_llm(provider_config) if provider_config
          @model = model
        end

        # Send a message with tools using RubyLLM's native tool calling.
        # tools should be an array of RubyLLM::Tool classes or instances.
        # Yields streaming chunks to the block.
        # Returns the final RubyLLM::Message.
        def ask(message, tools: [], &block)
          with_retry do
            chat = RubyLLM.chat(model: @model)
            chat.with_tools(*tools) unless tools.empty?

            chat.on_tool_call do |tool_call|
              block&.call(Models::ToolExecutionStarted.new(
                tool_name: tool_call.name.to_s,
                tool_use_id: tool_call.id.to_s
              ))
            end

            chat.on_tool_result do |result|
              block&.call(Models::ToolExecutionCompleted.new(
                tool_use_id: "latest",
                result: Models::ToolResult.new(text: result.to_s)
              ))
            end

            response = chat.ask(message) do |chunk|
              if chunk.content
                block&.call(Models::AssistantTextDelta.new(text: chunk.content))
              end
            end

            block&.call(Models::AssistantTurnComplete.new(stop_reason: "end_turn"))
            response
          end
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
