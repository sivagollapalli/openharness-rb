# frozen_string_literal: true

require_relative "../tools/base_tool"
require_relative "../errors"

module Openharness
  module Rb
    module Mcp
      class ReadMcpResourceTool < Tools::BaseTool
        def initialize(server_name:, client_manager:)
          @server_name = server_name
          @client_manager = client_manager
        end

        def name
          "read_mcp_resource"
        end

        def description
          "Read a resource from an MCP server by URI"
        end

        def input_schema
          {
            type: "object",
            properties: {
              uri: { type: "string", description: "The URI of the resource to read" }
            },
            required: ["uri"]
          }
        end

        private

        def execute(input, _context)
          uri = input[:uri] || input["uri"]
          content = @client_manager.read_resource(@server_name, uri)
          Models::ToolResult.new(text: content.to_s)
        rescue McpServerNotConnectedError => e
          Models::ToolResult.new(text: e.message, is_error: true)
        end
      end
    end
  end
end
