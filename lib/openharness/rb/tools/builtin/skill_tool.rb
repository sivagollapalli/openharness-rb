# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class SkillTool < BaseTool
          def initialize(skill_registry:)
            @skill_registry = skill_registry
            super()
          end

          def name
            "skill"
          end

          def description
            "Retrieve a skill by name and return its content"
          end

          def input_schema
            {
              type: "object",
              properties: {
                skill_name: { type: "string", description: "Name of the skill to retrieve" }
              },
              required: ["skill_name"]
            }
          end

          private

          def execute(input, _context)
            skill_name = input[:skill_name] || input["skill_name"]
            skill = @skill_registry.get(skill_name)
            Models::ToolResult.new(text: skill.content)
          rescue SkillNotFoundError
            available = @skill_registry.available_names.join(", ")
            Models::ToolResult.new(
              text: "Skill not found: #{skill_name}. Available skills: #{available}",
              is_error: true
            )
          end
        end
      end
    end
  end
end
