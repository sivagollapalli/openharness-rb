# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class SkillTool < RubyLLM::Tool
          description "Retrieve a skill by name and return its content"

          param :skill_name, desc: "Name of the skill to retrieve"

          def initialize(skill_registry)
            @skill_registry = skill_registry
          end

          def execute(skill_name:)
            skill = @skill_registry.get(skill_name)
            skill.content
          rescue Openharness::Rb::SkillNotFoundError
            available = @skill_registry.available_names.join(", ")
            { error: "Skill not found: #{skill_name}. Available skills: #{available}" }
          end
        end
      end
    end
  end
end
