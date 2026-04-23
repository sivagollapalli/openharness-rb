# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class SkillTool < RubyLLM::Tool
          description "Load a skill by name. Skills provide domain knowledge for specific tasks. " \
                      "Call this tool when you need specialized knowledge to complete a task. " \
                      "The skill content will be returned for you to use."

          def name = "skill"

          param :skill_name, desc: "Name of the skill to load (see available skills in system prompt)"

          def initialize(skill_registry)
            @skill_registry = skill_registry
          end

          def execute(skill_name:)
            skill = @skill_registry.get(skill_name)

            # Fire SkillLoaded event if an event callback is set
            callback = Thread.current[:openharness_event_handler]
            if callback
              callback.call(Models::SkillLoaded.new(
                skill_name: skill.name,
                description: skill.description,
                content_length: skill.content.length
              ))
            end

            "## Skill: #{skill.name}\n\n#{skill.content}"
          rescue Openharness::Rb::SkillNotFoundError
            catalog = @skill_registry.catalog_entries
            if catalog.empty?
              { error: "No skills available." }
            else
              list = catalog.map { |e| "- #{e[:name]}: #{e[:description]}" }.join("\n")
              { error: "Skill '#{skill_name}' not found.\n\nAvailable skills:\n#{list}" }
            end
          end
        end
      end
    end
  end
end
