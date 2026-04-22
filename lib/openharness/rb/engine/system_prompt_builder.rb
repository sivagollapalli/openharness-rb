# frozen_string_literal: true

module Openharness
  module Rb
    module Engine
      class SystemPromptBuilder
        PROJECT_CONTEXT_FILES = ["CLAUDE.md", ".openharness/context.md"].freeze

        def initialize(skill_registry: nil, memory_system: nil, project_root: Dir.pwd)
          @skills = skill_registry
          @memory = memory_system
          @project_root = project_root
        end

        def build
          sections = []
          sections << build_skill_section if @skills
          sections << build_memory_section if @memory
          sections << build_project_context
          sections.compact.join("\n\n")
        end

        private

        def build_skill_section
          names = @skills.available_names
          return nil if names.empty?

          "## Available Skills\n\nUse the skill tool to load any of these:\n#{names.map { |n| "- #{n}" }.join("\n")}"
        end

        def build_memory_section
          @memory.load_memory_prompt
        end

        def build_project_context
          PROJECT_CONTEXT_FILES.each do |file|
            path = File.join(@project_root, file)
            return "## Project Context\n\n#{File.read(path)}" if File.exist?(path)
          end
          nil
        end
      end
    end
  end
end
