# frozen_string_literal: true

require "json"
require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class NotebookEditTool < BaseTool
          def name
            "notebook_edit"
          end

          def description
            "Read or edit a cell in a Jupyter notebook (.ipynb) file"
          end

          def input_schema
            {
              type: "object",
              properties: {
                path: { type: "string", description: "Notebook file path relative to cwd" },
                cell_index: { type: "integer", description: "Index of the cell to read or edit (0-based)" },
                new_content: { type: "string", description: "New content for the cell (omit to read)" }
              },
              required: %w[path cell_index]
            }
          end

          private

          def execute(input, context)
            path = input[:path] || input["path"]
            cell_index = input[:cell_index] || input["cell_index"]
            new_content = input[:new_content] || input["new_content"]
            file_path = File.expand_path(path, context.cwd)

            notebook = JSON.parse(File.read(file_path))
            cells = notebook["cells"] || []

            if cell_index < 0 || cell_index >= cells.length
              return Models::ToolResult.new(
                text: "Cell index #{cell_index} out of range (0..#{cells.length - 1})",
                is_error: true
              )
            end

            if new_content
              cells[cell_index]["source"] = new_content.lines
              File.write(file_path, JSON.pretty_generate(notebook))
              Models::ToolResult.new(text: "Cell #{cell_index} updated in #{path}")
            else
              source = Array(cells[cell_index]["source"]).join
              Models::ToolResult.new(text: source)
            end
          rescue Errno::ENOENT
            Models::ToolResult.new(text: "Notebook not found: #{path}", is_error: true)
          rescue JSON::ParserError => e
            Models::ToolResult.new(text: "Invalid notebook JSON: #{e.message}", is_error: true)
          end
        end
      end
    end
  end
end
