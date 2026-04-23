# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class ListTasksTool < RubyLLM::Tool
          description "List all active background tasks with their names and statuses"

          def name = "list_tasks"

          def initialize(task_manager)
            @task_manager = task_manager
          end

          def execute
            tasks = @task_manager.list
            if tasks.empty?
              "No active background tasks."
            else
              tasks.map { |t| "#{t[:name]} (#{t[:status]})" }.join("\n")
            end
          end
        end
      end
    end
  end
end
