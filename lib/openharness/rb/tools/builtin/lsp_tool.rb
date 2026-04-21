# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class LspTool < BaseTool
          def name
            "lsp"
          end

          def description
            "Interact with a Language Server Protocol server for diagnostics, definitions, and references"
          end

          def input_schema
            {
              type: "object",
              properties: {
                action: {
                  type: "string",
                  description: "LSP action to perform: diagnostics, definition, or references",
                  enum: %w[diagnostics definition references]
                },
                file: { type: "string", description: "File path relative to cwd" },
                line: { type: "integer", description: "Line number (0-based)" },
                character: { type: "integer", description: "Character offset (0-based)" }
              },
              required: %w[action file]
            }
          end

          private

          def execute(input, _context)
            action = input[:action] || input["action"]
            Models::ToolResult.new(
              text: "No LSP server configured. Cannot perform '#{action}' action.",
              is_error: true
            )
          end
        end
      end
    end
  end
end
