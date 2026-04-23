# frozen_string_literal: true

require "yaml"

module Openharness
  module Rb
    module Skills
      # SkillRegistry manages a catalog of skills.
      #
      # On startup it reads .openharness/skills.yml to build a lightweight
      # catalog (name + description only, no content loaded). The LLM sees
      # this catalog in the system prompt and can call the skill tool to
      # load any skill's full content on demand.
      #
      # Content is lazy-loaded from .openharness/skills/<file>.md the first
      # time a skill is requested, then cached in memory for the session.
      class SkillRegistry
        CATALOG_FILE = "skills.yml"
        SKILLS_DIR = "skills"

        attr_reader :catalog

        def initialize
          @catalog = {}     # name => { description:, file:, loaded: false }
          @skills = {}      # name => SkillDefinition (loaded on demand)
          @skills_dir = nil
        end

        # Load the skill catalog from .openharness/skills.yml
        def load_all(project_root: Dir.pwd, plugin_skills: [])
          @skills_dir = File.join(project_root, ".openharness", SKILLS_DIR)
          catalog_path = File.join(project_root, ".openharness", CATALOG_FILE)

          load_catalog(catalog_path) if File.exist?(catalog_path)

          # Also discover any .md files not listed in the catalog
          discover_unlisted_skills

          plugin_skills.each { |s| register_loaded(s) }
        end

        # Get a skill by name. Lazy-loads content from disk if not yet loaded.
        def get(name)
          # Already loaded — return from cache
          return @skills[name] if @skills.key?(name)

          # In catalog but not loaded — load now
          if @catalog.key?(name)
            load_skill_content(name)
            return @skills[name]
          end

          raise SkillNotFoundError, "Skill '#{name}' not found. Available: #{available_names.join(', ')}"
        end

        # All known skill names (from catalog + any already loaded)
        def available_names
          (@catalog.keys + @skills.keys).uniq
        end

        # Catalog entries with descriptions (for system prompt)
        def catalog_entries
          @catalog.map { |name, info| { name: name, description: info[:description] } }
        end

        # Register a skill that's already fully loaded (e.g. from plugins or runtime)
        def register_loaded(skill_def)
          @skills[skill_def.name] = skill_def
          @catalog[skill_def.name] ||= {
            description: skill_def.description,
            file: nil,
            loaded: true
          }
        end

        private

        def load_catalog(path)
          data = YAML.safe_load(File.read(path), symbolize_names: true) || {}
          entries = data[:skills] || {}

          entries.each do |name, info|
            name_str = name.to_s
            @catalog[name_str] = {
              description: info[:description] || "",
              file: info[:file],
              loaded: false
            }
          end
        end

        # Find .md files in the skills dir that aren't in the catalog
        def discover_unlisted_skills
          return unless @skills_dir && Dir.exist?(@skills_dir)

          Dir.glob(File.join(@skills_dir, "*.md")).each do |path|
            basename = File.basename(path, ".md")
            next if @catalog.key?(basename)

            # Parse just the frontmatter for description, don't load full content
            desc = extract_description(path)
            @catalog[basename] = {
              description: desc,
              file: File.basename(path),
              loaded: false
            }
          end
        end

        def extract_description(path)
          content = File.read(path)
          if content.start_with?("---")
            frontmatter = content.split("---", 3)[1]
            meta = YAML.safe_load(frontmatter)
            meta&.dig("description") || ""
          else
            lines = content.lines
            lines[1..]&.find { |l| l.strip.length > 0 }&.strip || ""
          end
        rescue StandardError
          ""
        end

        # Load the full content of a skill from its .md file
        def load_skill_content(name)
          info = @catalog[name]
          file = info[:file]

          unless file && @skills_dir
            raise SkillNotFoundError, "No file path for skill '#{name}'"
          end

          path = File.join(@skills_dir, file)
          unless File.exist?(path)
            raise SkillNotFoundError, "Skill file not found: #{path}"
          end

          $stdout.puts "\e[36m📖 Loading skill '#{name}' from #{file}...\e[0m"

          skill = parse_skill_file(name, path)
          @skills[name] = skill
          info[:loaded] = true

          $stdout.puts "\e[36m   ✓ Loaded (#{skill.content.length} chars, #{skill.content.lines.count} lines)\e[0m"
          skill
        end

        def parse_skill_file(expected_name, path)
          content = File.read(path)
          if content.start_with?("---")
            parts = content.split("---", 3)
            frontmatter = parts[1]
            body = parts[2]
            meta = YAML.safe_load(frontmatter)
            SkillDefinition.new(
              name: meta["name"] || expected_name,
              description: meta["description"] || "",
              content: body.strip
            )
          else
            lines = content.lines
            name = lines.first&.sub(/^#\s*/, "")&.strip || expected_name
            desc = lines[1..]&.find { |l| l.strip.length > 0 }&.strip || ""
            SkillDefinition.new(name: name, description: desc, content: content)
          end
        end
      end
    end
  end
end
