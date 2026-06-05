# frozen_string_literal: true

module Openharness
  module Rb
    module Context
      # DefaultStrategy is the built-in context management implementation that
      # uses LLM calls via RubyLLM to generate conversation summaries.
      #
      # It implements two levels of reduction:
      # - `summarize`: Preserves system message, generates a concise summary of
      #   older messages, and keeps the last 4 messages unchanged.
      # - `compact`: Preserves system message, generates an ultra-compact summary
      #   (2-3 sentences), and keeps the last 2 messages unchanged.
      #
      # Both methods are safe — they never mutate the input messages array.
      #
      # @example
      #   strategy = DefaultStrategy.new
      #   result = strategy.summarize(messages, model: "claude-sonnet-4-20250514")
      class DefaultStrategy
        include Strategy

        # Summarize older messages into a condensed form while preserving
        # the system message and most recent 4 messages.
        #
        # @param messages [Array<Hash>] full conversation messages
        # @param opts [Hash] keyword options
        # @option opts [String] :model the model identifier for LLM summarization
        # @return [Array<Hash>] replacement messages array
        def summarize(messages, **opts)
          return messages if messages.length <= 4

          system_msg = messages.first if messages.first[:role] == "system"
          start_idx = system_msg ? 1 : 0
          recent = messages.last(4)
          older = messages[start_idx...(messages.length - 4)]

          summary_text = generate_summary(older, opts[:model])

          result = []
          result << system_msg if system_msg
          result << { role: "system", content: "[Conversation Summary]\n#{summary_text}" }
          result.concat(recent)
          result
        end

        # Compact the conversation aggressively while preserving the system
        # message and most recent 2 messages.
        #
        # @param messages [Array<Hash>] full conversation messages
        # @param opts [Hash] keyword options
        # @option opts [String] :model the model identifier for LLM compaction
        # @return [Array<Hash>] replacement messages array
        def compact(messages, **opts)
          return messages if messages.length <= 2

          system_msg = messages.first if messages.first[:role] == "system"
          recent = messages.last(2)
          start_idx = system_msg ? 1 : 0
          older = messages[start_idx...(messages.length - 2)]

          summary_text = generate_compact_summary(older, opts[:model])

          result = []
          result << system_msg if system_msg
          result << { role: "system", content: "[Compacted Context]\n#{summary_text}" }
          result.concat(recent)
          result
        end

        private

        # Generate a concise summary of messages using the LLM.
        # Preserves key decisions, tool results, and context needed to continue.
        #
        # @param messages [Array<Hash>] messages to summarize
        # @param model [String] model identifier
        # @return [String] summary text
        def generate_summary(messages, model)
          chat = RubyLLM.chat(model: model)
          chat.with_instructions(
            "Summarize this conversation concisely. Preserve key decisions, " \
            "tool results, and context the assistant needs to continue helping."
          )
          formatted = messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
          response = chat.ask("Summarize:\n#{formatted}")
          response.content
        end

        # Generate an ultra-compact summary (2-3 sentences max) using the LLM.
        # Captures only the user's goal, key decisions, and current state.
        #
        # @param messages [Array<Hash>] messages to compact
        # @param model [String] model identifier
        # @return [String] ultra-compact summary text
        def generate_compact_summary(messages, model)
          chat = RubyLLM.chat(model: model)
          chat.with_instructions(
            "Create an ultra-compact summary (2-3 sentences max). Include ONLY: " \
            "the user's goal, key decisions made, and current state. Drop all details."
          )
          formatted = messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
          response = chat.ask("Ultra-compact summary:\n#{formatted}")
          response.content
        end
      end
    end
  end
end
