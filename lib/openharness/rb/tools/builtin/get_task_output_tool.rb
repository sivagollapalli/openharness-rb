# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class GetTaskOutputTool < BaseTool
          def initialize(task_manager:)
            @task_manager = task_manager
            super()
          end

          def name
            "get_task_output"
          end

          def description
            "Get the output of a running background task"
          end

          def input_schema
            {
              type: "object",
              properties: {
                task_name: { type: "string", description: "Name of the task to get output from" }
              },
              required: ["task_name"]
            }
          end

          private

          def execute(input, _context)
            task_name = input[:task_name] || input["task_name"]
            output = @task_manager.output(task_name)
            Models::ToolResult.new(text: output.empty? ? "(no output yet)" : output)
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
