# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class EditFileTool < RubyLLM::Tool
          description "Apply a text replacement (old_str -> new_str) to a file. old_str must match exactly once."

          param :path, desc: "File path relative to working directory"
          param :old_str, desc: "Text to find and replace (must match exactly once)"
          param :new_str, desc: "Replacement text"

          def execute(path:, old_str:, new_str:)
            file_path = File.expand_path(path, working_dir)
            content = File.read(file_path)
            occurrences = content.scan(old_str).length

            return { error: "old_str not found in #{path}" } if occurrences.zero?
            return { error: "old_str matches #{occurrences} locations in #{path}; must match exactly one" } if occurrences > 1

            File.write(file_path, content.sub(old_str, new_str))
            "Successfully edited #{path}"
          rescue Errno::ENOENT
            { error: "File not found: #{path}" }
          end

          private

          def working_dir
            ENV["OPENHARNESS_CWD"] || Dir.pwd
          end
        end
      end
    end
  end
end
