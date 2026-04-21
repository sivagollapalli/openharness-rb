# frozen_string_literal: true

require_relative "../models/tool_result"

module Openharness
  module Rb
    module Tools
      class BaseTool
        def name
          raise NotImplementedError
        end

        def description
          raise NotImplementedError
        end

        def input_schema
          raise NotImplementedError
        end

        def call(input, context)
          validated = validate_input(input)
          return validated if validated.is_a?(Models::ToolResult) && validated.is_error

          execute(validated, context)
        rescue StandardError => e
          Models::ToolResult.new(text: e.message, is_error: true)
        end

        private

        def execute(_input, _context)
          raise NotImplementedError
        end

        def validate_input(input)
          # Validate against input_schema — for now, just return input
          # Full dry-validation integration can be added later
          input
        end
      end
    end
  end
end
