# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class StopTaskTool < RubyLLM::Tool
          description "Stop a running background task by name"

          def name = "stop_task"

          param :task_name, desc: "Name of the task to stop"

          def initialize(task_manager)
            @task_manager = task_manager
          end

          def execute(task_name:)
            @task_manager.stop(task_name)
            "Background task '#{task_name}' stopped."
          rescue Openharness::Rb::TaskNotFoundError
            { error: "No task found with name '#{task_name}'." }
          end
        end
      end
    end
  end
end
