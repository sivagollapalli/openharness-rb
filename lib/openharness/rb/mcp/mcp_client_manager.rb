# frozen_string_literal: true

require_relative "../errors"
require_relative "mcp_server_config"

module Openharness
  module Rb
    module Mcp
      class McpConnectionStatus
        CONNECTED = :connected
        DISCONNECTED = :disconnected
        ERROR = :error
      end

      class McpClientManager
        attr_reader :statuses

        def initialize
          @connections = {}
          @statuses = {}
        end

        def connect(config)
          case config.transport
          when "stdio" then connect_stdio(config)
          when "http"  then connect_http(config)
          end
          @statuses[config.name] = McpConnectionStatus::CONNECTED
        rescue StandardError => e
          @statuses[config.name] = McpConnectionStatus::ERROR
          raise McpServerNotConnectedError, "#{config.name}: #{e.message}"
        end

        def disconnect_all
          @connections.each_value do |conn|
            conn.close if conn.respond_to?(:close)
          end
          @connections.clear
          @statuses.transform_values! { McpConnectionStatus::DISCONNECTED }
        end

        def call_tool(server_name, tool_name, arguments)
          conn = @connections.fetch(server_name) do
            raise McpServerNotConnectedError, server_name
          end
          conn.call_tool(tool_name, arguments)
        end

        def list_resources
          @connections.flat_map do |name, conn|
            conn.list_resources.map { |r| [name, r] }
          end
        end

        def read_resource(server_name, uri)
          conn = @connections.fetch(server_name) do
            raise McpServerNotConnectedError, server_name
          end
          conn.read_resource(uri)
        end

        private

        def connect_stdio(config)
          # Spawn process, establish JSON-RPC over stdin/stdout
          # Placeholder for actual stdio transport implementation
        end

        def connect_http(config)
          # Establish HTTP streamable connection
          # Placeholder for actual HTTP transport implementation
        end
      end
    end
  end
end
