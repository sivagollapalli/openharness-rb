# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class BashTool < BaseTool
          DEFAULT_TIMEOUT = 120

          def name
            "bash"
          end

          def description
            "Execute a shell command in a subprocess with configurable timeout"
          end

          def input_schema
            {
              type: "object",
              properties: {
                command: { type: "string", description: "Shell command to execute" },
                timeout: { type: "integer", description: "Timeout in seconds (default: 120)" }
              },
              required: ["command"]
            }
          end

          private

          def execute(input, context)
            command = input[:command] || input["command"]
            timeout = input[:timeout] || input["timeout"] || DEFAULT_TIMEOUT

            stdout, stderr, _status = Timeout.timeout(timeout) do
              Open3.capture3(command, chdir: context.cwd)
            end

            output = [stdout, stderr].reject(&:empty?).join("\n").strip
            Models::ToolResult.new(text: output.empty? ? "(no output)" : output)
          rescue Timeout::Error
            Models::ToolResult.new(text: "Command timed out after #{timeout}s", is_error: true)
          end
        end
      end
    end
  end
end
