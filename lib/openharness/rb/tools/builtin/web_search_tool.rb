# frozen_string_literal: true

require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class WebSearchTool < BaseTool
          def name
            "web_search"
          end

          def description
            "Search the web for information using a query string"
          end

          def input_schema
            {
              type: "object",
              properties: {
                query: { type: "string", description: "Search query" }
              },
              required: ["query"]
            }
          end

          private

          def execute(input, _context)
            query = input[:query] || input["query"]
            Models::ToolResult.new(
              text: "Web search is not yet configured. Query: #{query}",
              is_error: true
            )
          end
        end
      end
    end
  end
end
