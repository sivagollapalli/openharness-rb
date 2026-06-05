# frozen_string_literal: true

module Openharness
  module Rb
    module Context
      # ContextManager monitors token usage against the model's context window
      # and triggers summarization or compaction strategies when thresholds are
      # crossed.
      #
      # State transitions are monotonic: :normal → :summarized → :compacted.
      # Only `reset!` can move the state backwards.
      #
      # @example Basic usage
      #   manager = ContextManager.new(
      #     context_window: 100_000,
      #     thresholds: Thresholds.new(summarize_ratio: 0.25, compact_ratio: 0.50),
      #     strategy: DefaultStrategy.new
      #   )
      #   action = manager.check_and_manage!(chat, response)
      #   # => :none, :summarized, or :compacted
      class ContextManager
        attr_reader :context_window, :thresholds, :strategy, :state, :cumulative_input_tokens

        # @param context_window [Integer] max tokens for the model
        # @param thresholds [Thresholds] summarize/compact ratios
        # @param strategy [Strategy] pluggable summarization/compaction logic
        def initialize(context_window:, thresholds: Thresholds.new, strategy: nil)
          @context_window = context_window
          @thresholds = thresholds
          @strategy = strategy
          @state = :normal
          @cumulative_input_tokens = 0
        end

        # Resolve the context window size for a given model from RubyLLM's registry.
        # Falls back to 100,000 tokens if the model is not found or an error occurs.
        #
        # @param model [String] model identifier (e.g., "gpt-4o", "claude-sonnet-4-20250514")
        # @return [Integer] context window token limit
        def self.resolve_context_window(model)
          model_info = RubyLLM.models.find(model)
          model_info&.context_window || 100_000
        rescue StandardError
          100_000
        end

        # Called after each LLM response to check thresholds and manage context.
        #
        # @param chat [RubyLLM::Chat] the active chat object
        # @param response [Object] latest response with token counts
        # @return [Symbol] :none, :summarized, or :compacted
        def check_and_manage!(chat, response)
          update_token_count(response)
          ratio = usage_ratio

          if ratio >= @thresholds.compact_ratio
            apply_compaction!(chat)
          elsif ratio >= @thresholds.summarize_ratio && @state == :normal
            apply_summarization!(chat)
          else
            :none
          end
        rescue StandardError => e
          $stderr.puts "[ContextManager] Error during check_and_manage!: #{e.message}"
          :none
        end

        # Current usage as a fraction of context window.
        #
        # @return [Float] 0.0 when context_window is zero, otherwise
        #   cumulative_input_tokens / context_window
        def usage_ratio
          return 0.0 if @context_window.zero?

          @cumulative_input_tokens.to_f / @context_window
        end

        # Reset state to initial values.
        # Called when the conversation is cleared.
        def reset!
          @cumulative_input_tokens = 0
          @state = :normal
        end

        private

        # Update the cumulative input token count from the latest response.
        # This is not additive — it reflects the latest response's input_tokens
        # which represents the full context sent to the model.
        def update_token_count(response)
          return unless response&.respond_to?(:input_tokens) && response.input_tokens

          @cumulative_input_tokens = response.input_tokens
        end

        # Apply summarization strategy to the chat.
        # Wraps the strategy call in error handling.
        #
        # @return [Symbol] :summarized on success, :none on error
        def apply_summarization!(chat)
          messages = extract_messages(chat)
          opts = { model: chat.model, context_window: @context_window, current_tokens: @cumulative_input_tokens }
          replacement = @strategy.summarize(messages, **opts)
          replace_history!(chat, replacement)
          @state = :summarized
          :summarized
        rescue StandardError => e
          $stderr.puts "[ContextManager] Summarization failed: #{e.message}"
          :none
        end

        # Apply compaction strategy to the chat.
        # Wraps the strategy call in error handling.
        #
        # @return [Symbol] :compacted on success, :none on error
        def apply_compaction!(chat)
          messages = extract_messages(chat)
          opts = { model: chat.model, context_window: @context_window, current_tokens: @cumulative_input_tokens }
          replacement = @strategy.compact(messages, **opts)
          replace_history!(chat, replacement)
          @state = :compacted
          :compacted
        rescue StandardError => e
          $stderr.puts "[ContextManager] Compaction failed: #{e.message}"
          :none
        end

        # Extract messages from the chat as an array of hashes.
        #
        # @param chat [RubyLLM::Chat] the chat object
        # @return [Array<Hash>] messages as [{role:, content:}]
        def extract_messages(chat)
          chat.messages.map do |msg|
            { role: msg.role.to_s, content: msg.content }
          end
        end

        # Replace the chat's message history with a new set of messages.
        #
        # @param chat [RubyLLM::Chat] the chat object
        # @param new_messages [Array<Hash>] replacement messages
        def replace_history!(chat, new_messages)
          chat.messages.clear
          new_messages.each do |msg|
            chat.messages << RubyLLM::Message.new(role: msg[:role].to_sym, content: msg[:content])
          end
        end
      end
    end
  end
end
