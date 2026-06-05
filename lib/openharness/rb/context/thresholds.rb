# frozen_string_literal: true

module Openharness
  module Rb
    module Context
      # Value object holding configurable threshold ratios for context management.
      # Determines when summarization and compaction are triggered based on
      # the fraction of the context window consumed.
      #
      # @example Default thresholds
      #   Thresholds.new # summarize at 25%, compact at 50%
      #
      # @example Custom thresholds
      #   Thresholds.new(summarize_ratio: 0.30, compact_ratio: 0.60)
      class Thresholds
        attr_reader :summarize_ratio, :compact_ratio

        # @param summarize_ratio [Float] usage ratio at which summarization triggers (0.0..1.0, default 0.25)
        # @param compact_ratio [Float] usage ratio at which compaction triggers (0.0..1.0, default 0.50)
        # @raise [ArgumentError] if summarize_ratio >= compact_ratio
        # @raise [ArgumentError] if either ratio is outside 0.0..1.0
        def initialize(summarize_ratio: 0.25, compact_ratio: 0.50)
          unless (0.0..1.0).cover?(summarize_ratio) && (0.0..1.0).cover?(compact_ratio)
            raise ArgumentError, "ratios must be between 0 and 1"
          end

          unless summarize_ratio < compact_ratio
            raise ArgumentError, "summarize_ratio must be < compact_ratio"
          end

          @summarize_ratio = summarize_ratio
          @compact_ratio = compact_ratio
        end
      end
    end
  end
end
