# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class CreateTaskTool < BaseTool
          def initialize(task_manager:)
            @task_manager = task_manager
            super()
          end

          def name
            "create_task"
          end

          def description
            "Start a named background task that runs a command"
          end

          def input_schema
            {
              type: "object",
              properties: {
                task_name: { type: "string", description: "Unique name for the background task" },
                command: { type: "string", description: "Shell command to run" }
              },
              required: %w[task_name command]
            }
          end

          private

          def execute(input, context)
            task_name = input[:task_name] || input["task_name"]
            command = input[:command] || input["command"]

            @task_manager.start(name: task_name, command: command, cwd: context.cwd)
            Models::ToolResult.new(text: "Background task '#{task_name}' started.")
          rescue DuplicateTaskError
            Models::ToolResult.new(
              text: "A task named '#{task_name}' already exists.",
              is_error: true
            )
          end
        end
      end
    end
  end
end
