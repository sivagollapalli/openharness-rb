# frozen_string_literal: true

require_relative "cost_tracker"
require_relative "../errors"
require_relative "../models/conversation_message"
require_relative "../models/content_block"
require_relative "../models/stream_events"

module Openharness
  module Rb
    module Engine
      class QueryEngine
        attr_reader :messages, :turn_count, :cost_tracker

        def initialize(api_adapter:, tool_registry:, permission_checker:, context:)
          @api = api_adapter
          @tools = tool_registry
          @permissions = permission_checker
          @context = context
          @messages = []
          @cost_tracker = CostTracker.new
          @turn_count = 0
        end

        def run_query(user_message, &event_handler)
          @messages << Models::ConversationMessage.new(
            role: "user",
            content_blocks: [
              Models::ContentBlock.new(type: "text", content: { text: user_message })
            ]
          )

          loop do
            @turn_count += 1
            raise MaxTurnsExceeded, "Exceeded max turns (#{@context.max_turns})" if @turn_count > @context.max_turns

            compact_if_needed!

            response = @api.stream_messages(@messages, tools: @tools.schemas) do |event|
              event_handler&.call(event)
            end

            tool_uses = extract_tool_uses(response)

            if tool_uses.empty?
              append_assistant_response(response)
              event_handler&.call(Models::AssistantTurnComplete.new(stop_reason: "end_turn"))
              break
            end

            append_assistant_response(response)
            results = execute_tools_concurrently(tool_uses, &event_handler)
            append_tool_results(tool_uses, results)
          end
        end

        private

        def execute_tools_concurrently(tool_uses, &event_handler)
          # Sequential execution for now; Async integration can come later
          tool_uses.map do |tu|
            event_handler&.call(Models::ToolExecutionStarted.new(
              tool_name: tu[:name], tool_use_id: tu[:id]
            ))
            result = @tools.execute(tu[:name], tu[:input], build_tool_context)
            event_handler&.call(Models::ToolExecutionCompleted.new(
              tool_use_id: tu[:id], result: result
            ))
            result
          end
        end

        def compact_if_needed!
          # Placeholder for auto-compaction when token count exceeds threshold
        end

        def extract_tool_uses(response)
          return [] unless response.is_a?(Hash) || response.respond_to?(:content_blocks)

          blocks = if response.respond_to?(:content_blocks)
                     response.content_blocks
                   elsif response.is_a?(Hash)
                     response[:content_blocks] || response["content_blocks"] || []
                   else
                     []
                   end

          blocks.select { |b| block_type(b) == "tool_use" }
                .map { |b| extract_tool_use_info(b) }
        end

        def block_type(block)
          if block.respond_to?(:type)
            block.type
          elsif block.is_a?(Hash)
            block[:type] || block["type"]
          end
        end

        def extract_tool_use_info(block)
          content = if block.respond_to?(:content)
                      block.content
                    elsif block.is_a?(Hash)
                      block[:content] || block["content"] || {}
                    else
                      {}
                    end

          {
            id: content[:id] || content["id"] || "",
            name: content[:name] || content["name"] || "",
            input: content[:input] || content["input"] || {}
          }
        end

        def append_assistant_response(response)
          blocks = if response.respond_to?(:content_blocks)
                     response.content_blocks
                   elsif response.is_a?(Hash)
                     (response[:content_blocks] || response["content_blocks"] || []).map do |b|
                       Models::ContentBlock.new(type: b[:type] || b["type"], content: b[:content] || b["content"] || {})
                     end
                   else
                     [Models::ContentBlock.new(type: "text", content: { text: response.to_s })]
                   end

          @messages << Models::ConversationMessage.new(role: "assistant", content_blocks: blocks)
        end

        def append_tool_results(tool_uses, results)
          blocks = tool_uses.zip(results).map do |tu, result|
            Models::ContentBlock.new(
              type: "tool_result",
              content: {
                tool_use_id: tu[:id],
                text: result.text,
                is_error: result.is_error
              }
            )
          end

          @messages << Models::ConversationMessage.new(role: "user", content_blocks: blocks)
        end

        def build_tool_context
          Models::ToolExecutionContext.new(
            cwd: @context.cwd,
            session_id: "default",
            event_emitter: nil
          )
        end
      end
    end
  end
end
