# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class GlobTool < BaseTool
          def name
            "glob"
          end

          def description
            "Return a list of file paths matching a given glob pattern relative to the working directory"
          end

          def input_schema
            {
              type: "object",
              properties: {
                pattern: { type: "string", description: "Glob pattern (e.g. '**/*.rb')" }
              },
              required: ["pattern"]
            }
          end

          private

          def execute(input, context)
            pattern = input[:pattern] || input["pattern"]
            full_pattern = File.join(context.cwd, pattern)

            paths = Dir.glob(full_pattern).select { |f| File.file?(f) }
            relative_paths = paths.map { |p| p.sub("#{context.cwd}/", "") }

            Models::ToolResult.new(text: relative_paths.join("\n"))
          end
        end
      end
    end
  end
end
