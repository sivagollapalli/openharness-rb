# frozen_string_literal: true

require "ruby_llm"
require "fileutils"

module Openharness
  module Rb
    module Tools
      module Builtin
        class WriteToFileTool < RubyLLM::Tool
          description "Write content to a file, creating parent directories as needed"

          param :path, desc: "File path relative to working directory"
          param :content, desc: "Content to write to the file"

          def execute(path:, content:)
            file_path = File.expand_path(path, working_dir)
            FileUtils.mkdir_p(File.dirname(file_path))
            File.write(file_path, content)
            "Successfully wrote #{content.length} bytes to #{path}"
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
