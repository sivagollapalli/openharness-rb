# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class EditFileTool < BaseTool
          def name
            "edit_file"
          end

          def description
            "Apply a text replacement (old_str -> new_str) to a file"
          end

          def input_schema
            {
              type: "object",
              properties: {
                path: { type: "string", description: "File path relative to cwd" },
                old_str: { type: "string", description: "Text to find and replace" },
                new_str: { type: "string", description: "Replacement text" }
              },
              required: %w[path old_str new_str]
            }
          end

          private

          def execute(input, context)
            path = input[:path] || input["path"]
            old_str = input[:old_str] || input["old_str"]
            new_str = input[:new_str] || input["new_str"]
            file_path = File.expand_path(path, context.cwd)

            content = File.read(file_path)
            occurrences = content.scan(old_str).length

            if occurrences.zero?
              return Models::ToolResult.new(
                text: "old_str not found in #{path}",
                is_error: true
              )
            end

            if occurrences > 1
              return Models::ToolResult.new(
                text: "old_str matches #{occurrences} locations in #{path}; must match exactly one",
                is_error: true
              )
            end

            new_content = content.sub(old_str, new_str)
            File.write(file_path, new_content)

            Models::ToolResult.new(text: "Successfully edited #{path}")
          rescue Errno::ENOENT
            Models::ToolResult.new(text: "File not found: #{path}", is_error: true)
          end
        end
      end
    end
  end
end
