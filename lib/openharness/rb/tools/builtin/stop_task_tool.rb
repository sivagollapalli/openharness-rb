# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class StopTaskTool < BaseTool
          def initialize(task_manager:)
            @task_manager = task_manager
            super()
          end

          def name
            "stop_task"
          end

          def description
            "Stop a running background task by name"
          end

          def input_schema
            {
              type: "object",
              properties: {
                task_name: { type: "string", description: "Name of the task to stop" }
              },
              required: ["task_name"]
            }
          end

          private

          def execute(input, _context)
            task_name = input[:task_name] || input["task_name"]
            @task_manager.stop(task_name)
            Models::ToolResult.new(text: "Background task '#{task_name}' stopped.")
          rescue TaskNotFoundError
            Models::ToolResult.new(
              text: "No task found with name '#{task_name}'.",
              is_error: true
            )
          end
        end
      end
    end
  end
end
