# frozen_string_literal: true

require_relative "../errors"

module Openharness
  module Rb
    module Mcp
      class McpConnectionStatus
        CONNECTED = :connected
        DISCONNECTED = :disconnected
        ERROR = :error
      end

      # Manages MCP server connections using the ruby_llm-mcp gem.
      # Accepts config as either:
      #   - McpServerConfig struct (flat: name, transport, command, args, url, etc.)
      #   - Plain hash matching ruby_llm-mcp format (name, transport, config: { command:, args: })
      class McpClientManager
        attr_reader :statuses, :clients

        def initialize
          @clients = {}
          @statuses = {}
        end

        # Connect to an MCP server.
        # config can be a McpServerConfig, or a plain Hash.
        def connect(config)
          require "ruby_llm/mcp"

          name, transport_type, client_config = normalize_config(config)

          client = RubyLLM::MCP.client(
            name: name,
            transport_type: transport_type,
            config: client_config
          )

          @clients[name] = client
          @statuses[name] = McpConnectionStatus::CONNECTED
          client
        rescue StandardError => e
          name ||= config.respond_to?(:name) ? config.name : config[:name]
          @statuses[name] = McpConnectionStatus::ERROR
          warn "MCP server '#{name}' failed to connect: #{e.message}"
          nil
        end

        def connect_all(configs)
          configs.each { |c| connect(c) }
        end

        # All RubyLLM-compatible tools from all connected servers.
        def tools
          @clients.values.flat_map do |client|
            client.tools
          rescue StandardError => e
            warn "Failed to get tools from MCP client: #{e.message}"
            []
          end
        end

        def resources
          @clients.values.flat_map do |client|
            client.resources
          rescue StandardError => e
            warn "Failed to get resources from MCP client: #{e.message}"
            []
          end
        end

        def client(name)
          @clients.fetch(name) do
            raise McpServerNotConnectedError, "MCP server '#{name}' is not connected"
          end
        end

        def disconnect_all
          @clients.each do |name, client|
            client.stop if client.respond_to?(:stop)
            @statuses[name] = McpConnectionStatus::DISCONNECTED
          rescue StandardError => e
            warn "Error disconnecting MCP server '#{name}': #{e.message}"
          end
          @clients.clear
        end

        def connected?
          @statuses.values.any? { |s| s == McpConnectionStatus::CONNECTED }
        end

        private

        # Normalize config into [name, transport_type, client_config] for RubyLLM::MCP.client
        def normalize_config(config)
          if config.is_a?(Hash)
            normalize_hash_config(config)
          else
            normalize_struct_config(config)
          end
        end

        # Handle plain hash config — supports both formats:
        #   { name: "x", transport: "stdio", command: "npx", args: [...] }
        #   { name: "x", transport: "stdio", config: { command: "npx", args: [...] } }
        def normalize_hash_config(hash)
          h = hash.transform_keys(&:to_sym)
          name = h[:name]
          transport = resolve_transport(h[:transport]&.to_s || "stdio")

          # If user passed a nested config: key, use it directly
          if h[:config]
            client_config = h[:config].transform_keys(&:to_sym)
          elsif transport == :stdio
            client_config = {
              command: h[:command],
              args: h[:args] || [],
              env: h[:env] || {}
            }.compact
          else
            client_config = {
              url: h[:url],
              headers: h[:headers] || {}
            }.compact
          end

          [name, transport, client_config]
        end

        # Handle McpServerConfig struct
        def normalize_struct_config(config)
          name = config.name
          transport = resolve_transport(config.transport)

          client_config = if transport == :stdio
                            {
                              command: config.command,
                              args: config.args,
                              env: config.env
                            }.compact
                          else
                            cfg = { url: config.url }
                            cfg[:headers] = config.headers unless config.headers.empty?
                            cfg
                          end

          [name, transport, client_config]
        end

        def resolve_transport(transport_str)
          case transport_str.to_s
          when "stdio" then :stdio
          when "http", "streamable" then :streamable
          when "sse" then :sse
          else :stdio
          end
        end
      end
    end
  end
end
