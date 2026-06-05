# frozen_string_literal: true

module Openharness
  module Rb
    module Context
      # Strategy is the pluggable interface for context management behavior.
      #
      # Implement this module to provide custom summarization and compaction
      # logic. The ContextManager delegates to a Strategy when token usage
      # crosses configured thresholds.
      #
      # Both methods receive the full conversation messages array and keyword
      # options containing the model identifier, context window size, and
      # current cumulative token count.
      #
      # Implementations MUST:
      # - Return a new Array of message Hashes (do not mutate the input)
      # - Each Hash must contain :role (String) and :content (String) keys
      #
      # @example Custom strategy
      #   class MyStrategy
      #     include Openharness::Rb::Context::Strategy
      #
      #     def summarize(messages, **opts)
      #       # Keep system message and last 10 messages
      #       system_msg = messages.first if messages.first[:role] == "system"
      #       result = system_msg ? [system_msg] : []
      #       result.concat(messages.last(10))
      #       result
      #     end
      #
      #     def compact(messages, **opts)
      #       # Keep only system message and last user message
      #       system_msg = messages.first if messages.first[:role] == "system"
      #       last_user = messages.reverse.find { |m| m[:role] == "user" }
      #       result = system_msg ? [system_msg] : []
      #       result << last_user if last_user
      #       result
      #     end
      #   end
      module Strategy
        # Summarize older messages into a condensed form.
        #
        # Called by the ContextManager when usage crosses the summarize
        # threshold. Typically preserves the system message and recent
        # messages while condensing older conversation history.
        #
        # @param messages [Array<Hash>] full conversation messages, each with
        #   :role (String) and :content (String) keys
        # @param opts [Hash] keyword options
        # @option opts [String] :model the model identifier
        # @option opts [Integer] :context_window maximum token capacity
        # @option opts [Integer] :current_tokens cumulative input tokens used
        # @return [Array<Hash>] replacement messages array (must not mutate input)
        # @raise [NotImplementedError] if the including class does not override
        def summarize(messages, **opts)
          raise NotImplementedError, "#{self.class}#summarize must be implemented"
        end

        # Compact the conversation more aggressively.
        #
        # Called by the ContextManager when usage crosses the compact
        # threshold. Produces a minimal message set, typically retaining
        # only the system message, an ultra-compact summary, and the most
        # recent messages.
        #
        # @param messages [Array<Hash>] full conversation messages, each with
        #   :role (String) and :content (String) keys
        # @param opts [Hash] keyword options
        # @option opts [String] :model the model identifier
        # @option opts [Integer] :context_window maximum token capacity
        # @option opts [Integer] :current_tokens cumulative input tokens used
        # @return [Array<Hash>] replacement messages array (must not mutate input)
        # @raise [NotImplementedError] if the including class does not override
        def compact(messages, **opts)
          raise NotImplementedError, "#{self.class}#compact must be implemented"
        end
      end
    end
  end
end
