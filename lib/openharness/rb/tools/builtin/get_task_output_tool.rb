# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class GetTaskOutputTool < RubyLLM::Tool
          description "Get the output of a running background task"

          def name = "get_task_output"

          param :task_name, desc: "Name of the task to get output from"

          def initialize(task_manager)
            @task_manager = task_manager
          end

          def execute(task_name:)
            output = @task_manager.output(task_name)
            output.empty? ? "(no output yet)" : output
          rescue Openharness::Rb::TaskNotFoundError
            { error: "No task found with name '#{task_name}'." }
          end
        end
      end
    end
  end
end
