# frozen_string_literal: true

require "ruby_llm"
require "open3"
require "timeout"

module Openharness
  module Rb
    module Tools
      module Builtin
        class BashTool < RubyLLM::Tool
          description "Execute a shell command in a subprocess with configurable timeout"

          param :command, desc: "Shell command to execute"
          param :timeout, type: :integer, desc: "Timeout in seconds (default: 120)", required: false

          def execute(command:, timeout: 120)
            stdout, stderr, _status = Timeout.timeout(timeout) do
              Open3.capture3(command, chdir: working_dir)
            end

            output = [stdout, stderr].reject(&:empty?).join("\n").strip
            output.empty? ? "(no output)" : output
          rescue Timeout::Error
            { error: "Command timed out after #{timeout}s" }
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
