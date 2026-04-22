# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class LspTool < RubyLLM::Tool
          description "Interact with a Language Server Protocol server for diagnostics, definitions, and references"

          param :action, desc: "LSP action: diagnostics, definition, or references"
          param :file, desc: "File path relative to working directory"
          param :line, type: :integer, desc: "Line number (0-based)", required: false
          param :character, type: :integer, desc: "Character offset (0-based)", required: false

          def execute(action:, file:, line: nil, character: nil)
            { error: "No LSP server configured. Cannot perform '#{action}' action." }
          end
        end
      end
    end
  end
end
