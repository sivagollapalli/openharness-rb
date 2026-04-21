# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class AgentTool < BaseTool
          def name
            "agent"
          end

          def description
            "Spawn a sub-agent to handle a delegated task"
          end

          def input_schema
            {
              type: "object",
              properties: {
                task_description: { type: "string", description: "Description of the task to delegate" },
                agent_name: { type: "string", description: "Optional name of the agent to use" }
              },
              required: ["task_description"]
            }
          end

          private

          def execute(input, _context)
            task_description = input[:task_description] || input["task_description"]
            agent_name = input[:agent_name] || input["agent_name"]

            msg = "Sub-agent spawning is not yet fully implemented."
            msg += " Requested agent: #{agent_name}." if agent_name
            msg += " Task: #{task_description}"

            Models::ToolResult.new(text: msg)
          end
        end
      end
    end
  end
end
