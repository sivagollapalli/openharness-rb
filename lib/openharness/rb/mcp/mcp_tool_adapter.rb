# frozen_string_literal: true

require_relative "../tools/base_tool"
require_relative "../errors"

module Openharness
  module Rb
    module Mcp
      class McpToolAdapter < Tools::BaseTool
        def initialize(server_name:, tool_info:, client_manager:)
          @server_name = server_name
          @tool_info = tool_info
          @client_manager = client_manager
        end

        def name
          @tool_info[:name]
        end

        def description
          @tool_info[:description]
        end

        def input_schema
          @tool_info[:input_schema]
        end

        private

        def execute(input, _context)
          result = @client_manager.call_tool(@server_name, name, input)
          Models::ToolResult.new(text: result.to_s)
        rescue McpServerNotConnectedError => e
          Models::ToolResult.new(text: e.message, is_error: true)
        end
      end
    end
  end
end
