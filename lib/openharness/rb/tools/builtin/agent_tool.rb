# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class AgentTool < RubyLLM::Tool
          description "Spawn a sub-agent to handle a delegated task"

          param :task_description, desc: "Description of the task to delegate"
          param :agent_name, desc: "Optional name of the agent to use", required: false

          def execute(task_description:, agent_name: nil)
            msg = "Sub-agent spawning is not yet fully implemented."
            msg += " Requested agent: #{agent_name}." if agent_name
            msg += " Task: #{task_description}"
            msg
          end
        end
      end
    end
  end
end
