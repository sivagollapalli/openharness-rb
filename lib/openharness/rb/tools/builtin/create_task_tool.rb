# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class CreateTaskTool < RubyLLM::Tool
          description "Start a named background task that runs a shell command"

          def name = "create_task"

          param :task_name, desc: "Unique name for the background task"
          param :command, desc: "Shell command to run"

          def initialize(task_manager)
            @task_manager = task_manager
          end

          def execute(task_name:, command:)
            cwd = ENV["OPENHARNESS_CWD"] || Dir.pwd
            @task_manager.start(name: task_name, command: command, cwd: cwd)
            "Background task '#{task_name}' started."
          rescue Openharness::Rb::DuplicateTaskError
            { error: "A task named '#{task_name}' already exists." }
          end
        end
      end
    end
  end
end
