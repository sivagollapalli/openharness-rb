# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class GlobTool < RubyLLM::Tool
          description "List file paths matching a glob pattern relative to the working directory"

          def name = "glob"

          param :pattern, desc: "Glob pattern (e.g. '**/*.rb', 'src/**/*.js')"

          def execute(pattern:)
            full_pattern = File.join(working_dir, pattern)
            paths = Dir.glob(full_pattern).select { |f| File.file?(f) }
            relative = paths.map { |p| p.sub("#{working_dir}/", "") }
            relative.empty? ? "No files matched pattern: #{pattern}" : relative.join("\n")
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
