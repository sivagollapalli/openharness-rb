# frozen_string_literal: true

require "ruby_llm"
require "json"
require_relative "permission_guard"

module Openharness
  module Rb
    module Tools
      module Builtin
        class NotebookEditTool < RubyLLM::Tool
          include PermissionGuard

          description "Read or edit a cell in a Jupyter notebook (.ipynb) file"

          def name = "notebook_edit"

          param :path, desc: "Notebook file path relative to working directory"
          param :cell_index, type: :integer, desc: "Index of the cell to read or edit (0-based)"
          param :new_content, desc: "New content for the cell (omit to read)", required: false

          def execute(path:, cell_index:, new_content: nil)
            # Only check permission when writing (new_content provided)
            if new_content
              case check_permission!
              when :denied then return permission_denied_message("Mutating tool blocked")
              when :denied_by_user then return user_denied_message
              end
            end

            file_path = File.expand_path(path, working_dir)
            notebook = JSON.parse(File.read(file_path))
            cells = notebook["cells"] || []

            return { error: "Cell index #{cell_index} out of range (0..#{cells.length - 1})" } if cell_index < 0 || cell_index >= cells.length

            if new_content
              cells[cell_index]["source"] = new_content.lines
              File.write(file_path, JSON.pretty_generate(notebook))
              "Cell #{cell_index} updated in #{path}"
            else
              Array(cells[cell_index]["source"]).join
            end
          rescue Errno::ENOENT
            { error: "Notebook not found: #{path}" }
          rescue JSON::ParserError => e
            { error: "Invalid notebook JSON: #{e.message}" }
          end

          private

          def working_dir
            ENV["OPENHARNESS_CWD"] || Dir.pwd
          end
        end
      end
    end
  end
end
