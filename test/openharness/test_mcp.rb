# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    module Mcp
      # ---------------------------------------------------------------
      # 8.5.1 Test McpToolAdapter wraps MCP tool as BaseTool with
      #        correct name/description/schema
      # ---------------------------------------------------------------
      class TestMcpToolAdapterWrapping < Minitest::Test
        # **Validates: Requirements 26.1, 26.3**

        def setup
          @tool_info = {
            name: "get_weather",
            description: "Fetch current weather for a location",
            input_schema: {
              type: "object",
              properties: {
                location: { type: "string", description: "City name" }
              },
              required: ["location"]
            }
          }
          @manager = McpClientManager.new
          @adapter = McpToolAdapter.new(
            server_name: "weather-server",
            tool_info: @tool_info,
            client_manager: @manager
          )
        end

        def test_name_matches_tool_info
          assert_equal "get_weather", @adapter.name
        end

        def test_description_matches_tool_info
          assert_equal "Fetch current weather for a location", @adapter.description
        end

        def test_input_schema_matches_tool_info
          assert_equal @tool_info[:input_schema], @adapter.input_schema
        end

        def test_adapter_is_a_base_tool
          assert_kind_of Tools::BaseTool, @adapter
        end
      end

      # ---------------------------------------------------------------
      # 8.5.2 Test McpToolAdapter returns error ToolResult when server
      #        disconnected
      # ---------------------------------------------------------------
      class TestMcpToolAdapterDisconnected < Minitest::Test
        # **Validates: Requirements 26.4**

        def setup
          @tool_info = {
            name: "run_query",
            description: "Run a database query",
            input_schema: { type: "object", properties: {} }
          }
          @manager = McpClientManager.new
          @adapter = McpToolAdapter.new(
            server_name: "db-server",
            tool_info: @tool_info,
            client_manager: @manager
          )
        end

        def test_call_returns_error_tool_result_when_not_connected
          context = Models::ToolExecutionContext.new(
            cwd: Dir.pwd,
            session_id: "test-session",
            event_emitter: ->(_event) {}
          )
          result = @adapter.call({ query: "SELECT 1" }, context)

          assert_instance_of Models::ToolResult, result
          assert result.is_error, "Expected is_error to be true"
          assert_includes result.text, "db-server"
        end
      end

      # ---------------------------------------------------------------
      # 8.5.3 Test McpClientManager tracks connection status
      # ---------------------------------------------------------------
      class TestMcpClientManagerStatus < Minitest::Test
        # **Validates: Requirements 25.3, 25.4, 25.5**

        def setup
          @manager = McpClientManager.new
        end

        def test_initial_statuses_empty
          assert_empty @manager.statuses
        end

        def test_connect_stdio_sets_connected_status
          config = McpServerConfig.new(
            name: "test-stdio",
            transport: "stdio",
            command: "echo hello"
          )
          @manager.connect(config)

          assert_equal McpConnectionStatus::CONNECTED, @manager.statuses["test-stdio"]
        end

        def test_connect_http_sets_connected_status
          config = McpServerConfig.new(
            name: "test-http",
            transport: "http",
            url: "http://localhost:3000"
          )
          @manager.connect(config)

          assert_equal McpConnectionStatus::CONNECTED, @manager.statuses["test-http"]
        end

        def test_disconnect_all_sets_disconnected_status
          stdio_config = McpServerConfig.new(
            name: "server-a",
            transport: "stdio",
            command: "echo a"
          )
          http_config = McpServerConfig.new(
            name: "server-b",
            transport: "http",
            url: "http://localhost:4000"
          )
          @manager.connect(stdio_config)
          @manager.connect(http_config)

          @manager.disconnect_all

          assert_equal McpConnectionStatus::DISCONNECTED, @manager.statuses["server-a"]
          assert_equal McpConnectionStatus::DISCONNECTED, @manager.statuses["server-b"]
        end

        def test_call_tool_raises_when_not_connected
          assert_raises(McpServerNotConnectedError) do
            @manager.call_tool("nonexistent", "some_tool", {})
          end
        end

        def test_read_resource_raises_when_not_connected
          assert_raises(McpServerNotConnectedError) do
            @manager.read_resource("nonexistent", "file:///test.txt")
          end
        end
      end

      # ---------------------------------------------------------------
      # 8.5.4 Test McpServerConfig validates stdio and http
      #        configurations
      # ---------------------------------------------------------------
      class TestMcpServerConfigValidation < Minitest::Test
        # **Validates: Requirements 28.1, 28.2**

        def test_stdio_config_with_command_and_args
          config = McpServerConfig.new(
            name: "my-server",
            transport: "stdio",
            command: "/usr/bin/mcp-server",
            args: ["--port", "3000"],
            env: { "API_KEY" => "secret" }
          )

          assert_equal "my-server", config.name
          assert_equal "stdio", config.transport
          assert_equal "/usr/bin/mcp-server", config.command
          assert_equal ["--port", "3000"], config.args
          assert_equal({ "API_KEY" => "secret" }, config.env)
          assert_nil config.url
        end

        def test_http_config_with_url_and_headers
          config = McpServerConfig.new(
            name: "remote-server",
            transport: "http",
            url: "https://mcp.example.com/api",
            headers: { "Authorization" => "Bearer token123" }
          )

          assert_equal "remote-server", config.name
          assert_equal "http", config.transport
          assert_equal "https://mcp.example.com/api", config.url
          assert_equal({ "Authorization" => "Bearer token123" }, config.headers)
          assert_nil config.command
        end

        def test_defaults_for_optional_fields
          config = McpServerConfig.new(
            name: "minimal",
            transport: "stdio"
          )

          assert_nil config.command
          assert_equal [], config.args
          assert_equal({}, config.env)
          assert_nil config.url
          assert_equal({}, config.headers)
        end

        def test_invalid_transport_raises_error
          assert_raises(Dry::Struct::Error) do
            McpServerConfig.new(
              name: "bad",
              transport: "websocket"
            )
          end
        end
      end

      # ---------------------------------------------------------------
      # ReadMcpResourceTool basic tests
      # ---------------------------------------------------------------
      class TestReadMcpResourceTool < Minitest::Test
        # **Validates: Requirements 27.1, 27.2**

        def setup
          @manager = McpClientManager.new
          @tool = ReadMcpResourceTool.new(
            server_name: "resource-server",
            client_manager: @manager
          )
        end

        def test_name_and_description
          assert_equal "read_mcp_resource", @tool.name
          assert_equal "Read a resource from an MCP server by URI", @tool.description
        end

        def test_input_schema_requires_uri
          schema = @tool.input_schema
          assert_equal "object", schema[:type]
          assert schema[:properties].key?(:uri)
          assert_includes schema[:required], "uri"
        end

        def test_returns_error_when_server_not_connected
          context = Models::ToolExecutionContext.new(
            cwd: Dir.pwd,
            session_id: "test-session",
            event_emitter: ->(_event) {}
          )
          result = @tool.call({ uri: "file:///test.txt" }, context)

          assert_instance_of Models::ToolResult, result
          assert result.is_error
          assert_includes result.text, "resource-server"
        end

        def test_is_a_base_tool
          assert_kind_of Tools::BaseTool, @tool
        end
      end
    end
  end
end
