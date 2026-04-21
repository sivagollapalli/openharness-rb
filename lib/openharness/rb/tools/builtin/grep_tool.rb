# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class GrepTool < BaseTool
          def name
            "grep"
          end

          def description
            "Search files matching a glob pattern for lines matching a regex pattern"
          end

          def input_schema
            {
              type: "object",
              properties: {
                pattern: { type: "string", description: "Regex pattern to search for" },
                glob: { type: "string", description: "File glob pattern (e.g. '**/*.rb')" }
              },
              required: %w[pattern glob]
            }
          end

          private

          def execute(input, context)
            pattern = input[:pattern] || input["pattern"]
            glob = input[:glob] || input["glob"]
            regex = Regexp.new(pattern)

            matches = []
            Dir.glob(File.join(context.cwd, glob)).each do |file_path|
              next unless File.file?(file_path)

              File.readlines(file_path).each_with_index do |line, index|
                if regex.match?(line)
                  relative = file_path.sub("#{context.cwd}/", "")
                  matches << "#{relative}:#{index + 1}:#{line.rstrip}"
                end
              end
            rescue Errno::EACCES, Errno::EISDIR
              next
            end

            Models::ToolResult.new(text: matches.empty? ? "No matches found" : matches.join("\n"))
          end
        end
      end
    end
  end
end
