# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class ReadFileTool < RubyLLM::Tool
          description "Read the contents of a file at a given path relative to the working directory"

          param :path, desc: "File path relative to working directory"

          def execute(path:)
            file_path = File.expand_path(path, working_dir)
            File.read(file_path)
          rescue Errno::ENOENT
            { error: "File not found: #{path}" }
          rescue Errno::EACCES
            { error: "Permission denied: #{path}" }
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
