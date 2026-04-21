# frozen_string_literal: true

require "fileutils"
require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class WriteToFileTool < BaseTool
          def name
            "write_to_file"
          end

          def description
            "Write content to a file at a given path relative to the working directory, creating parent directories as needed"
          end

          def input_schema
            {
              type: "object",
              properties: {
                path: { type: "string", description: "File path relative to cwd" },
                content: { type: "string", description: "Content to write to the file" }
              },
              required: %w[path content]
            }
          end

          private

          def execute(input, context)
            path = input[:path] || input["path"]
            content = input[:content] || input["content"]
            file_path = File.expand_path(path, context.cwd)

            FileUtils.mkdir_p(File.dirname(file_path))
            File.write(file_path, content)

            Models::ToolResult.new(text: "Successfully wrote to #{path}")
          end
        end
      end
    end
  end
end
