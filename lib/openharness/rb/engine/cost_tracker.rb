# frozen_string_literal: true

module Openharness
  module Rb
    module Engine
      class CostTracker
        attr_reader :input_tokens, :output_tokens, :total_cost

        def initialize
          @input_tokens = 0
          @output_tokens = 0
          @total_cost = 0.0
          @mutex = Mutex.new
        end

        def record(input_tokens:, output_tokens:, cost:)
          @mutex.synchronize do
            @input_tokens += input_tokens
            @output_tokens += output_tokens
            @total_cost += cost
          end
        end

        def summary
          { input_tokens: @input_tokens, output_tokens: @output_tokens, total_cost: @total_cost }
        end
      end
    end
  end
end
