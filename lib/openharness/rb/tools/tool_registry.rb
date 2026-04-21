# frozen_string_literal: true

require_relative "../errors"

module Openharness
  module Rb
    module Tools
      class ToolRegistry
        def initialize
          @tools = {}
        end

        def register(tool)
          raise DuplicateToolError, tool.name if @tools.key?(tool.name)

          @tools[tool.name] = tool
        end

        def get_tool(name)
          @tools.fetch(name) { raise ToolNotFoundError, name }
        end

        def unregister(name)
          @tools.delete(name)
        end

        def schemas
          @tools.values.map do |t|
            { name: t.name, description: t.description, input_schema: t.input_schema }
          end
        end

        def execute(name, input, context)
          get_tool(name).call(input, context)
        end
      end
    end
  end
end
