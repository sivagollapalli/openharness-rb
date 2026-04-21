# frozen_string_literal: true

require "yaml"

module Openharness
  module Rb
    module Skills
      class SkillRegistry
        BUNDLED_PATH = File.expand_path("../skills/bundled", __dir__)
        USER_PATH = File.expand_path("~/.openharness/skills")

        def initialize
          @skills = {}
        end

        def load_all(plugin_skills: [])
          load_from_directory(BUNDLED_PATH)
          load_from_directory(USER_PATH) if Dir.exist?(USER_PATH)
          plugin_skills.each { |s| register(s) }
        end

        def get(name)
          @skills.fetch(name) { raise SkillNotFoundError, name }
        end

        def available_names
          @skills.keys
        end

        private

        def register(skill_def)
          @skills[skill_def.name] = skill_def
        end

        def load_from_directory(dir)
          return unless Dir.exist?(dir)

          Dir.glob(File.join(dir, "*.md")).each do |path|
            skill = parse_skill_file(path)
            register(skill)
          end
        end

        def parse_skill_file(path)
          content = File.read(path)
          if content.start_with?("---")
            parts = content.split("---", 3)
            frontmatter = parts[1]
            body = parts[2]
            meta = YAML.safe_load(frontmatter)
            SkillDefinition.new(
              name: meta["name"],
              description: meta["description"],
              content: body.strip
            )
          else
            lines = content.lines
            name = lines.first&.sub(/^#\s*/, "")&.strip || File.basename(path, ".md")
            desc = lines[1..]&.find { |l| l.strip.length > 0 }&.strip || ""
            SkillDefinition.new(name: name, description: desc, content: content)
          end
        end
      end
    end
  end
end
