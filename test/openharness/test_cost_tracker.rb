# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    module Engine
      class TestCostTrackerAccumulation < Minitest::Test
        # **Validates: Requirements 2.1, 2.2**
        # Property 2: After recording N usage entries, the CostTracker totals
        # equal the sum of all individual entries.

        def test_accumulation_property
          100.times do |i|
            tracker = CostTracker.new
            entry_count = rand(1..20)
            entries = Array.new(entry_count) do
              {
                input_tokens: rand(0..10_000),
                output_tokens: rand(0..10_000),
                cost: rand * 100.0
              }
            end

            entries.each do |e|
              tracker.record(input_tokens: e[:input_tokens], output_tokens: e[:output_tokens], cost: e[:cost])
            end

            expected_input = entries.sum { |e| e[:input_tokens] }
            expected_output = entries.sum { |e| e[:output_tokens] }
            expected_cost = entries.sum { |e| e[:cost] }

            assert_equal expected_input, tracker.input_tokens,
                         "Iteration #{i}: input_tokens mismatch"
            assert_equal expected_output, tracker.output_tokens,
                         "Iteration #{i}: output_tokens mismatch"
            assert_in_delta expected_cost, tracker.total_cost, 1e-9,
                           "Iteration #{i}: total_cost mismatch"
          end
        end
      end

      class TestCostTrackerInitialization < Minitest::Test
        # **Validates: Requirements 2.3**

        def test_initializes_to_zero
          tracker = CostTracker.new
          assert_equal 0, tracker.input_tokens
          assert_equal 0, tracker.output_tokens
          assert_in_delta 0.0, tracker.total_cost, 1e-9
        end
      end

      class TestCostTrackerSummary < Minitest::Test
        # **Validates: Requirements 2.4**

        def test_summary_returns_correct_hash_structure
          tracker = CostTracker.new
          tracker.record(input_tokens: 100, output_tokens: 200, cost: 0.05)
          tracker.record(input_tokens: 50, output_tokens: 75, cost: 0.02)

          result = tracker.summary

          assert_instance_of Hash, result
          assert_equal %i[input_tokens output_tokens total_cost].sort, result.keys.sort
          assert_equal 150, result[:input_tokens]
          assert_equal 275, result[:output_tokens]
          assert_in_delta 0.07, result[:total_cost], 1e-9
        end
      end
    end
  end
end
