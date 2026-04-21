# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class ListTasksTool < BaseTool
          def initialize(task_manager:)
            @task_manager = task_manager
            super()
          end

          def name
            "list_tasks"
          end

          def description
            "List all active background tasks"
          end

          def input_schema
            {
              type: "object",
              properties: {},
              required: []
            }
          end

          private

          def execute(_input, _context)
            tasks = @task_manager.list
            if tasks.empty?
              Models::ToolResult.new(text: "No active background tasks.")
            else
              lines = tasks.map { |t| "#{t[:name]} (#{t[:status]})" }
              Models::ToolResult.new(text: lines.join("\n"))
            end
          end
        end
      end
    end
  end
end
