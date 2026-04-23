# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class GrepTool < RubyLLM::Tool
          description "Search files matching a glob pattern for lines matching a regex pattern"

          def name = "grep"

          param :pattern, desc: "Regex pattern to search for"
          param :glob, desc: "File glob pattern (e.g. '**/*.rb')"

          def execute(pattern:, glob:)
            regex = Regexp.new(pattern)
            matches = []

            Dir.glob(File.join(working_dir, glob)).each do |file_path|
              next unless File.file?(file_path)

              File.readlines(file_path).each_with_index do |line, index|
                if regex.match?(line)
                  relative = file_path.sub("#{working_dir}/", "")
                  matches << "#{relative}:#{index + 1}:#{line.rstrip}"
                end
              end
            rescue Errno::EACCES, Errno::EISDIR
              next
            end

            matches.empty? ? "No matches found" : matches.join("\n")
          rescue RegexpError => e
            { error: "Invalid regex: #{e.message}" }
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
