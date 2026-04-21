# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class ReadFileTool < BaseTool
          def name
            "read_file"
          end

          def description
            "Read the contents of a file at a given path relative to the working directory"
          end

          def input_schema
            {
              type: "object",
              properties: {
                path: { type: "string", description: "File path relative to cwd" }
              },
              required: ["path"]
            }
          end

          private

          def execute(input, context)
            file_path = File.expand_path(input[:path] || input["path"], context.cwd)
            Models::ToolResult.new(text: File.read(file_path))
          rescue Errno::ENOENT
            Models::ToolResult.new(text: "File not found: #{input[:path] || input["path"]}", is_error: true)
          end
        end
      end
    end
  end
end
