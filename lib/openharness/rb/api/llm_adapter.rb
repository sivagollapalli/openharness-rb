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

        def stream_messages(messages, tools: [], &block)
          with_retry do
            chat = RubyLLM.chat(model: @model)
            tools.each { |t| chat.with_tool(t) }

            chat.ask(format_messages(messages)) do |chunk|
              event = chunk_to_stream_event(chunk)
              block.call(event) if event && block
            end
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

        def format_messages(messages)
          messages.map do |msg|
            if msg.is_a?(Hash)
              msg
            else
              msg.to_h
            end
          end
        end

        def chunk_to_stream_event(chunk)
          if chunk.tool_calls&.any?
            tool_call = chunk.tool_calls.first
            Models::ToolExecutionStarted.new(
              tool_name: tool_call[:name] || tool_call["name"] || "",
              tool_use_id: tool_call[:id] || tool_call["id"] || ""
            )
          elsif chunk.content
            Models::AssistantTextDelta.new(text: chunk.content)
          end
        end
      end
    end
  end
end
