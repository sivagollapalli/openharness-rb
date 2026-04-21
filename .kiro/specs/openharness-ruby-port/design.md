# Technical Design: openharness-rb

## Overview

This document describes the technical design for porting OpenHarness to Ruby as the `openharness-rb` gem. The design follows idiomatic Ruby patterns, leveraging RubyLLM for multi-provider LLM integration and the Async gem for fiber-based concurrency. The architecture is organized into layered modules under the `Openharness::Rb` namespace.

## Architecture

### Module Structure

```
Openharness::Rb
├── Models/          # Data structures (ConversationMessage, StreamEvent, etc.)
├── Engine/          # QueryEngine, CostTracker, SystemPromptBuilder
├── Api/             # RubyLLM adapter, ProviderRegistry, retry logic
├── Tools/           # BaseTool, ToolRegistry, built-in tools
├── Permissions/     # PermissionChecker, PathRule, modes
├── Hooks/           # HookExecutor, HookRegistry, hook types
├── Mcp/             # McpClientManager, McpToolAdapter
├── Skills/          # SkillDefinition, SkillRegistry
├── Plugins/         # PluginManifest, LoadedPlugin, loader
├── Memory/          # MemorySystem, tokenizer, scoring
├── Agents/          # TeamRegistry, AgentDefinition, messaging
├── Session/         # SessionStorage, BackgroundTaskManager
├── Config/          # Settings, configuration loading
└── Cli/             # Thor-based CLI, slash commands
```

### Key Dependencies

| Gem | Purpose | Requirement |
|-----|---------|-------------|
| `ruby_llm` | Multi-provider LLM API client | Req 7 |
| `async` | Fiber-based concurrency | Req 4, 15 |
| `dry-types` / `dry-struct` | Input validation & typed structs | Req 43 |
| `dry-validation` | Schema validation contracts | Req 43 |
| `faraday` | HTTP client (for hooks, MCP HTTP, web tools) | Req 22, 25, 46 |
| `thor` | CLI framework | Req 41 |
| `listen` | File watching for hook hot-reload | Req 24 |
| `shellwords` | Shell escaping | Req 21 |

## Component Designs

### 1. Data Models (Req 1, 3, 6, 12)

All core data models use `dry-struct` for immutable, typed value objects.

```ruby
module Openharness
  module Rb
    module Models
      class ContentBlock < Dry::Struct
        attribute :type, Types::String.enum("text", "image", "tool_use", "tool_result")
        attribute :content, Types::Hash
      end

      class ConversationMessage < Dry::Struct
        attribute :role, Types::String.enum("user", "assistant", "system")
        attribute :content_blocks, Types::Array.of(ContentBlock)

        def to_h; ...; end
        def self.from_h(hash); ...; end
      end

      class ToolResult < Dry::Struct
        attribute :text, Types::String
        attribute :is_error, Types::Bool.default(false)
      end

      class QueryContext < Dry::Struct
        attribute :cwd, Types::String.default { Dir.pwd }
        attribute :max_turns, Types::Integer.default(10)
        attribute :permission_prompt, Types::Any.optional
        attribute :ask_user_prompt, Types::Any.optional
      end

      class ToolExecutionContext < Dry::Struct
        attribute :cwd, Types::String
        attribute :session_id, Types::String
        attribute :event_emitter, Types::Any
      end
    end
  end
end
```

### 2. Stream Events (Req 3)

Stream events use a base class with typed subclasses:

```ruby
module Openharness
  module Rb
    module Models
      class StreamEvent < Dry::Struct; end

      class AssistantTextDelta < StreamEvent
        attribute :text, Types::String
      end

      class ToolExecutionStarted < StreamEvent
        attribute :tool_name, Types::String
        attribute :tool_use_id, Types::String
      end

      class ToolExecutionCompleted < StreamEvent
        attribute :tool_use_id, Types::String
        attribute :result, ToolResult
      end

      class AssistantTurnComplete < StreamEvent
        attribute :stop_reason, Types::String
      end

      class ErrorOccurred < StreamEvent
        attribute :error, Types::Any
      end
    end
  end
end
```

### 3. Cost Tracker (Req 2)

Simple mutable accumulator with thread-safe access:

```ruby
module Openharness
  module Rb
    module Engine
      class CostTracker
        attr_reader :input_tokens, :output_tokens, :total_cost

        def initialize
          @input_tokens = 0
          @output_tokens = 0
          @total_cost = 0.0
          @mutex = Mutex.new
        end

        def record(input_tokens:, output_tokens:, cost:)
          @mutex.synchronize do
            @input_tokens += input_tokens
            @output_tokens += output_tokens
            @total_cost += cost
          end
        end

        def summary
          { input_tokens: @input_tokens, output_tokens: @output_tokens, total_cost: @total_cost }
        end
      end
    end
  end
end
```

### 4. API Layer — RubyLLM Adapter (Req 7, 8, 9, 44)

Instead of building custom API clients, we wrap RubyLLM's `Chat` interface. RubyLLM already handles multi-provider support (OpenAI, Anthropic, Gemini, etc.), streaming, tool calls, and error handling.

```ruby
module Openharness
  module Rb
    module Api
      class LlmAdapter
        def initialize(model: nil, provider_config: nil)
          configure_ruby_llm(provider_config) if provider_config
          @model = model
        end

        # Streams messages, yielding StreamEvent instances
        def stream_messages(messages, tools: [], &block)
          chat = RubyLLM.chat(model: @model)
          tools.each { |t| chat.with_tool(t) }

          chat.ask(format_messages(messages)) do |chunk|
            event = chunk_to_stream_event(chunk)
            block.call(event) if event
          end
        end

        private

        def configure_ruby_llm(config)
          RubyLLM.configure do |c|
            c.openai_api_key = config[:openai_api_key] if config[:openai_api_key]
            c.anthropic_api_key = config[:anthropic_api_key] if config[:anthropic_api_key]
          end
        end

        def chunk_to_stream_event(chunk)
          if chunk.tool_calls&.any?
            # Map to ToolExecutionStarted
          elsif chunk.content
            Models::AssistantTextDelta.new(text: chunk.content)
          end
        end
      end
    end
  end
end
```

The ProviderRegistry wraps RubyLLM's model registry with auto-detection:

```ruby
module Openharness
  module Rb
    module Api
      class ProviderSpec < Dry::Struct
        attribute :name, Types::String
        attribute :base_url, Types::String.optional
        attribute :auth_type, Types::String.enum("api_key", "oauth")
        attribute :model_pattern, Types::String.optional
        attribute :default_model, Types::String
      end

      class ProviderRegistry
        PROVIDERS = {
          "openai" => { prefix: "sk-", default_model: "gpt-4o" },
          "anthropic" => { prefix: "sk-ant-", default_model: "claude-sonnet-4-20250514" },
          # ... more providers
        }.freeze

        def detect_provider(api_key:, base_url: nil)
          # Match by key prefix or base_url pattern
          # Raise UnknownProviderError if no match
        end
      end
    end
  end
end
```

Error hierarchy wraps RubyLLM errors:

```ruby
module Openharness
  module Rb
    class OpenHarnessApiError < StandardError; end
    class AuthenticationFailure < OpenHarnessApiError; end
    class RateLimitFailure < OpenHarnessApiError
      attr_reader :retry_after
    end
    class RequestFailure < OpenHarnessApiError
      attr_reader :status_code, :response_body
    end
  end
end
```

### 5. Retry Logic (Req 44)

Standalone retry module used by the LLM adapter and HTTP hooks:

```ruby
module Openharness
  module Rb
    module Api
      module RetryHandler
        RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze
        NON_RETRYABLE_STATUSES = [400, 401].freeze

        def with_retry(max_retries: 3, base_delay: 1.0)
          attempts = 0
          begin
            yield
          rescue RubyLLM::RateLimitError, RubyLLM::ServerError,
                 RubyLLM::ServiceUnavailableError => e
            attempts += 1
            raise wrap_error(e) if attempts > max_retries

            delay = base_delay * (2**attempts) + rand(0.0..1.0)
            retry_after = extract_retry_after(e)
            delay = [delay, retry_after].max if retry_after
            sleep(delay)
            retry
          rescue RubyLLM::UnauthorizedError => e
            raise AuthenticationFailure, e.message
          end
        end
      end
    end
  end
end
```

### 6. Query Engine (Req 4, 5)

The core loop drives the thought-action-observation cycle using Async for concurrent tool execution:

```ruby
module Openharness
  module Rb
    module Engine
      class QueryEngine
        def initialize(api_adapter:, tool_registry:, permission_checker:, context:)
          @api = api_adapter
          @tools = tool_registry
          @permissions = permission_checker
          @context = context
          @messages = []
          @cost_tracker = CostTracker.new
          @turn_count = 0
        end

        def run_query(user_message, &event_handler)
          @messages << Models::ConversationMessage.new(
            role: "user",
            content_blocks: [{ type: "text", content: { text: user_message } }]
          )

          loop do
            @turn_count += 1
            raise MaxTurnsExceeded if @turn_count > @context.max_turns

            compact_if_needed!

            response = @api.stream_messages(@messages, tools: @tools.schemas) do |event|
              event_handler&.call(event)
            end

            tool_uses = extract_tool_uses(response)
            break if tool_uses.empty?

            # Concurrent tool execution via Async
            results = execute_tools_concurrently(tool_uses, &event_handler)
            append_tool_results(results)
          end

          event_handler&.call(Models::AssistantTurnComplete.new(stop_reason: "end_turn"))
        end

        private

        def execute_tools_concurrently(tool_uses, &event_handler)
          Async do |task|
            tool_uses.map do |tu|
              task.async do
                event_handler&.call(Models::ToolExecutionStarted.new(
                  tool_name: tu[:name], tool_use_id: tu[:id]
                ))
                result = @tools.execute(tu[:name], tu[:input], @context)
                event_handler&.call(Models::ToolExecutionCompleted.new(
                  tool_use_id: tu[:id], result: result
                ))
                result
              end
            end.map(&:wait)
          end
        end

        def compact_if_needed!
          # Token counting and summarization when threshold exceeded
        end
      end
    end
  end
end
```

### 7. Tools System (Req 10, 11, 12, 13, 14, 43)

BaseTool uses a module-based abstract interface with dry-validation for input:

```ruby
module Openharness
  module Rb
    module Tools
      class BaseTool
        def name; raise NotImplementedError; end
        def description; raise NotImplementedError; end
        def input_schema; raise NotImplementedError; end

        def call(input, context)
          validated = validate_input(input)
          return validated if validated.is_a?(Models::ToolResult) && validated.is_error

          execute(validated, context)
        rescue StandardError => e
          Models::ToolResult.new(text: e.message, is_error: true)
        end

        private

        def execute(input, context)
          raise NotImplementedError
        end

        def validate_input(input)
          # Validate against input_schema using dry-validation
        end
      end

      class ToolRegistry
        def initialize
          @tools = {}
        end

        def register(tool)
          raise DuplicateToolError, tool.name if @tools.key?(tool.name)
          @tools[tool.name] = tool
        end

        def get_tool(name)
          @tools.fetch(name) { raise ToolNotFoundError, name }
        end

        def unregister(name)
          @tools.delete(name)
        end

        def schemas
          @tools.values.map { |t| { name: t.name, description: t.description, input_schema: t.input_schema } }
        end

        def execute(name, input, context)
          get_tool(name).call(input, context)
        end
      end
    end
  end
end
```

Built-in tools follow the BaseTool contract:

```ruby
module Openharness
  module Rb
    module Tools
      module Builtin
        class ReadFileTool < BaseTool
          def name; "read_file"; end
          def description; "Read the contents of a file"; end
          def input_schema
            { type: "object", properties: { path: { type: "string" } }, required: ["path"] }
          end

          private

          def execute(input, context)
            full_path = File.expand_path(input[:path], context.cwd)
            Models::ToolResult.new(text: File.read(full_path))
          rescue Errno::ENOENT
            Models::ToolResult.new(text: "File not found: #{input[:path]}", is_error: true)
          end
        end

        class BashTool < BaseTool
          DEFAULT_TIMEOUT = 120

          def name; "bash"; end
          def description; "Execute a shell command"; end
          def input_schema
            { type: "object",
              properties: { command: { type: "string" }, timeout: { type: "integer" } },
              required: ["command"] }
          end

          private

          def execute(input, context)
            timeout = input[:timeout] || DEFAULT_TIMEOUT
            stdout, stderr, status = Open3.capture3(
              input[:command], chdir: context.cwd, timeout: timeout
            )
            Models::ToolResult.new(text: "#{stdout}\n#{stderr}".strip)
          rescue Timeout::Error
            Models::ToolResult.new(text: "Command timed out after #{timeout}s", is_error: true)
          end
        end
      end
    end
  end
end
```


### 8. Permission System (Req 16, 17, 18, 19)

```ruby
module Openharness
  module Rb
    module Permissions
      class PermissionMode
        DEFAULT = :default
        PLAN = :plan
        FULL_AUTO = :full_auto
      end

      class PermissionDecision < Dry::Struct
        attribute :status, Types::String.enum("allowed", "requires_confirmation", "denied")
        attribute :reason, Types::String.optional
      end

      class PathRule < Dry::Struct
        attribute :pattern, Types::String
        attribute :action, Types::String.enum("allow", "deny")
      end

      class PermissionChecker
        SENSITIVE_PATH_PATTERNS = [
          "~/.ssh/*", "~/.aws/credentials", "~/.aws/config",
          "~/.config/gcloud/*", "~/.kube/config",
          "**/.env", "**/.env.*"
        ].freeze

        MUTATING_TOOLS = %w[write_to_file edit_file bash notebook_edit].freeze

        def initialize(mode:, denied_tools: [], allowed_tools: [], path_rules: [], denied_commands: [])
          @mode = mode
          @denied_tools = denied_tools.to_set
          @allowed_tools = allowed_tools.to_set
          @path_rules = path_rules
          @denied_commands = denied_commands
        end

        def evaluate(tool_name:, file_path: nil, command: nil)
          # 1. Sensitive paths (always deny)
          return denied("Sensitive path") if file_path && sensitive_path?(file_path)

          # 2. Denied tools
          return denied("Tool denied by configuration") if @denied_tools.include?(tool_name)

          # 3. Allowed tools
          return allowed if @allowed_tools.include?(tool_name)

          # 4. Path rules
          if file_path
            decision = evaluate_path_rules(file_path)
            return decision if decision
          end

          # 5. Command patterns
          return denied("Command denied") if command && denied_command?(command)

          # 6. Mode resolution
          resolve_by_mode(tool_name)
        end

        private

        def sensitive_path?(path)
          expanded = File.expand_path(path)
          SENSITIVE_PATH_PATTERNS.any? { |pat| File.fnmatch?(File.expand_path(pat), expanded) }
        end

        def evaluate_path_rules(path)
          matching = @path_rules.select { |r| File.fnmatch?(r.pattern, path) }
          return nil if matching.empty?
          # Most specific (longest pattern) wins
          rule = matching.max_by { |r| r.pattern.length }
          rule.action == "allow" ? allowed : denied("Path denied by rule")
        end

        def denied_command?(command)
          @denied_commands.any? do |pattern|
            pattern.is_a?(Regexp) ? command.match?(pattern) : command.include?(pattern)
          end
        end

        def resolve_by_mode(tool_name)
          case @mode
          when PermissionMode::FULL_AUTO then allowed
          when PermissionMode::PLAN
            MUTATING_TOOLS.include?(tool_name) ? denied("Plan mode") : allowed
          else
            MUTATING_TOOLS.include?(tool_name) ? requires_confirmation : allowed
          end
        end

        def allowed = PermissionDecision.new(status: "allowed")
        def denied(reason) = PermissionDecision.new(status: "denied", reason: reason)
        def requires_confirmation = PermissionDecision.new(status: "requires_confirmation")
      end
    end
  end
end
```

### 9. Hooks System (Req 20, 21, 22, 23, 24)

```ruby
module Openharness
  module Rb
    module Hooks
      class HookEvent
        SESSION_START = :session_start
        SESSION_END = :session_end
        PRE_TOOL_USE = :pre_tool_use
        POST_TOOL_USE = :post_tool_use
      end

      class HookDefinition < Dry::Struct
        attribute :event, Types::Symbol
        attribute :matcher, Types::String.optional  # glob pattern
        attribute :block_on_failure, Types::Bool.default(false)
      end

      class CommandHookDefinition < HookDefinition
        attribute :command, Types::String
      end

      class HttpHookDefinition < HookDefinition
        attribute :url, Types::String
        attribute :headers, Types::Hash.default({}.freeze)
      end

      class PromptHookDefinition < HookDefinition
        attribute :prompt_template, Types::String
      end

      class HookRegistry
        def initialize(config_paths: [])
          @hooks = Hash.new { |h, k| h[k] = [] }
          @config_paths = config_paths
          @listener = nil
        end

        def register(hook_def)
          @hooks[hook_def.event] << hook_def
        end

        def hooks_for(event, context_name: nil)
          @hooks[event].select do |h|
            h.matcher.nil? || File.fnmatch?(h.matcher, context_name || "")
          end
        end

        def start_watching!
          @listener = Listen.to(*@config_paths.map { |p| File.dirname(p) }) do |modified, _, _|
            reload_configs(modified)
          end
          @listener.start
        end

        def stop_watching!
          @listener&.stop
        end

        private

        def reload_configs(modified_files)
          # Parse and re-register hooks from modified config files
          # Log warnings for invalid syntax, retain previous config
        end
      end

      class HookExecutor
        def initialize(registry:, http_client: nil, llm_adapter: nil)
          @registry = registry
          @http = http_client || Faraday.new
          @llm = llm_adapter
        end

        def dispatch(event, payload:, context_name: nil)
          hooks = @registry.hooks_for(event, context_name: context_name)
          results = hooks.map { |h| execute_hook(h, payload) }

          failures = results.select { |r| !r[:ok] }
          blocking_failures = hooks.zip(results)
            .select { |h, r| h.block_on_failure && !r[:ok] }

          if blocking_failures.any?
            { ok: false, failures: blocking_failures.map { |_, r| r } }
          else
            { ok: true, warnings: failures }
          end
        end

        private

        def execute_hook(hook, payload)
          case hook
          when CommandHookDefinition then execute_command(hook, payload)
          when HttpHookDefinition then execute_http(hook, payload)
          when PromptHookDefinition then execute_prompt(hook, payload)
          end
        end

        def execute_command(hook, payload)
          env = {
            "OPENHARNESS_HOOK_EVENT" => Shellwords.escape(hook.event.to_s),
            "OPENHARNESS_HOOK_PAYLOAD" => Shellwords.escape(JSON.generate(payload))
          }
          system(env, hook.command)
          { ok: true }
        rescue StandardError => e
          { ok: false, error: e.message }
        end

        def execute_http(hook, payload)
          resp = @http.post(hook.url) do |req|
            req.headers.merge!(hook.headers)
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.generate(payload)
          end
          resp.success? ? { ok: true } : { ok: false, error: "HTTP #{resp.status}" }
        end

        def execute_prompt(hook, payload)
          # Send to LLM, expect { ok: bool, reason: string }
          response = @llm.stream_messages([
            { role: "user", content: hook.prompt_template.gsub("{{payload}}", JSON.generate(payload)) }
          ])
          result = JSON.parse(response.content)
          result["ok"] ? { ok: true } : { ok: false, error: result["reason"] }
        end
      end
    end
  end
end
```

### 10. MCP Integration (Req 25, 26, 27, 28)

```ruby
module Openharness
  module Rb
    module Mcp
      class McpServerConfig < Dry::Struct
        attribute :name, Types::String
        attribute :transport, Types::String.enum("stdio", "http")
        attribute :command, Types::String.optional   # stdio
        attribute :args, Types::Array.of(Types::String).default([].freeze)
        attribute :env, Types::Hash.default({}.freeze)
        attribute :url, Types::String.optional       # http
        attribute :headers, Types::Hash.default({}.freeze)
      end

      class McpConnectionStatus
        CONNECTED = :connected
        DISCONNECTED = :disconnected
        ERROR = :error
      end

      class McpClientManager
        def initialize
          @connections = {}
          @statuses = {}
        end

        def connect(config)
          case config.transport
          when "stdio" then connect_stdio(config)
          when "http" then connect_http(config)
          end
          @statuses[config.name] = McpConnectionStatus::CONNECTED
        rescue StandardError => e
          @statuses[config.name] = McpConnectionStatus::ERROR
          raise McpServerNotConnectedError, "#{config.name}: #{e.message}"
        end

        def disconnect_all
          @connections.each_value(&:close)
          @connections.clear
          @statuses.transform_values! { McpConnectionStatus::DISCONNECTED }
        end

        def call_tool(server_name, tool_name, arguments)
          conn = @connections.fetch(server_name) { raise McpServerNotConnectedError, server_name }
          conn.call_tool(tool_name, arguments)
        end

        def list_resources
          @connections.flat_map { |name, conn| conn.list_resources.map { |r| [name, r] } }
        end

        def read_resource(server_name, uri)
          conn = @connections.fetch(server_name) { raise McpServerNotConnectedError, server_name }
          conn.read_resource(uri)
        end

        private

        def connect_stdio(config)
          # Spawn process, establish JSON-RPC over stdin/stdout
        end

        def connect_http(config)
          # Establish HTTP streamable connection
        end
      end

      class McpToolAdapter < Tools::BaseTool
        def initialize(server_name:, tool_info:, client_manager:)
          @server_name = server_name
          @tool_info = tool_info
          @client_manager = client_manager
        end

        def name; @tool_info[:name]; end
        def description; @tool_info[:description]; end
        def input_schema; @tool_info[:input_schema]; end

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
```

### 11. Skills & Plugins (Req 29, 30, 31)

```ruby
module Openharness
  module Rb
    module Skills
      class SkillDefinition < Dry::Struct
        attribute :name, Types::String
        attribute :description, Types::String
        attribute :content, Types::String
      end

      class SkillRegistry
        BUNDLED_PATH = File.expand_path("../skills/bundled", __dir__)
        USER_PATH = File.expand_path("~/.openharness/skills")

        def initialize
          @skills = {}
        end

        def load_all(plugin_skills: [])
          load_from_directory(BUNDLED_PATH)
          load_from_directory(USER_PATH) if Dir.exist?(USER_PATH)
          plugin_skills.each { |s| register(s) }
        end

        def get(name)
          @skills.fetch(name) { raise SkillNotFoundError, name }
        end

        def available_names
          @skills.keys
        end

        private

        def register(skill_def)
          @skills[skill_def.name] = skill_def
        end

        def load_from_directory(dir)
          Dir.glob(File.join(dir, "*.md")).each do |path|
            skill = parse_skill_file(path)
            register(skill)
          end
        end

        def parse_skill_file(path)
          content = File.read(path)
          if content.start_with?("---")
            frontmatter, body = content.split("---", 3)[1..2]
            meta = YAML.safe_load(frontmatter)
            SkillDefinition.new(name: meta["name"], description: meta["description"], content: body.strip)
          else
            lines = content.lines
            name = lines.first&.sub(/^#\s*/, "")&.strip || File.basename(path, ".md")
            desc = lines[1..]&.find { |l| l.strip.length > 0 }&.strip || ""
            SkillDefinition.new(name: name, description: desc, content: content)
          end
        end
      end
    end

    module Plugins
      class PluginManifest < Dry::Struct
        attribute :name, Types::String
        attribute :version, Types::String
        attribute :skills, Types::Array.of(Types::String).default([].freeze)
        attribute :commands, Types::Array.default([].freeze)
        attribute :agents, Types::Array.default([].freeze)
        attribute :hooks, Types::Array.default([].freeze)
        attribute :mcp_servers, Types::Array.default([].freeze)
      end

      class LoadedPlugin
        attr_reader :manifest, :path, :skill_definitions, :hook_definitions, :mcp_configs

        def initialize(manifest:, path:)
          @manifest = manifest
          @path = path
          @skill_definitions = []
          @hook_definitions = []
          @mcp_configs = []
        end
      end

      class PluginLoader
        SEARCH_PATHS = [
          File.expand_path("~/.openharness/plugins"),
          ".openharness/plugins"
        ].freeze

        def load_all
          SEARCH_PATHS.flat_map { |dir| load_from_directory(dir) }.compact
        end

        private

        def load_from_directory(dir)
          return [] unless Dir.exist?(dir)
          Dir.children(dir).filter_map do |name|
            plugin_dir = File.join(dir, name)
            manifest_path = File.join(plugin_dir, "plugin.json")
            next unless File.exist?(manifest_path)

            manifest = PluginManifest.new(**JSON.parse(File.read(manifest_path), symbolize_names: true))
            LoadedPlugin.new(manifest: manifest, path: plugin_dir)
          rescue JSON::ParserError, Dry::Struct::Error => e
            warn "Skipping invalid plugin at #{plugin_dir}: #{e.message}"
            nil
          end
        end
      end
    end
  end
end
```


### 12. Memory System (Req 32, 33, 34)

```ruby
module Openharness
  module Rb
    module Memory
      class MemoryHeader < Dry::Struct
        attribute :name, Types::String
        attribute :description, Types::String.optional
        attribute :type, Types::String.optional
        attribute :path, Types::String
        attribute :modified_at, Types::Time
      end

      class Tokenizer
        # Multi-language tokenizer for memory search scoring
        HAN_RANGE = /\p{Han}/

        def tokenize(text)
          tokens = []
          text.scan(/[\p{Han}]|[a-zA-Z0-9]+/) do |match|
            tokens << match.downcase
          end
          tokens
        end
      end

      class MemorySystem
        INDEX_FILE = "MEMORY.md"

        def initialize(project_dir:)
          @memory_dir = get_project_memory_dir(project_dir)
          @tokenizer = Tokenizer.new
        end

        def scan_memory_files
          return [] unless Dir.exist?(@memory_dir)

          Dir.glob(File.join(@memory_dir, "*.md"))
            .reject { |f| File.basename(f) == INDEX_FILE }
            .map { |f| parse_memory_file(f) }
            .sort_by { |h| -h.modified_at.to_f }
        end

        def find_relevant_memories(query, limit: 5)
          query_tokens = @tokenizer.tokenize(query)
          headers = scan_memory_files

          scored = headers.map do |header|
            meta_score = score_tokens(query_tokens, @tokenizer.tokenize("#{header.name} #{header.description}")) * 2.0
            body = File.read(header.path)
            body_score = score_tokens(query_tokens, @tokenizer.tokenize(body))
            { header: header, score: meta_score + body_score }
          end

          scored.sort_by { |s| -s[:score] }.first(limit)
        end

        def load_memory_prompt
          index_path = File.join(@memory_dir, INDEX_FILE)
          index = File.exist?(index_path) ? File.read(index_path) : ""
          memories = scan_memory_files.first(10).map { |h| "- #{h.name}: #{h.description}" }
          "## Memory\n\n#{index}\n\n### Available Memories\n#{memories.join("\n")}"
        end

        private

        def get_project_memory_dir(project_dir)
          File.join(project_dir, ".openharness", "memory")
        end

        def parse_memory_file(path)
          content = File.read(path)
          if content.start_with?("---")
            frontmatter = content.split("---", 3)[1]
            meta = YAML.safe_load(frontmatter)
            MemoryHeader.new(
              name: meta["name"] || File.basename(path, ".md"),
              description: meta["description"],
              type: meta["type"],
              path: path,
              modified_at: File.mtime(path)
            )
          else
            MemoryHeader.new(
              name: File.basename(path, ".md"),
              description: nil, type: nil,
              path: path, modified_at: File.mtime(path)
            )
          end
        end

        def score_tokens(query_tokens, target_tokens)
          return 0.0 if query_tokens.empty? || target_tokens.empty?
          target_set = target_tokens.to_set
          matches = query_tokens.count { |t| target_set.include?(t) }
          matches.to_f / query_tokens.length
        end
      end
    end
  end
end
```

### 13. Multi-Agent Coordination (Req 35, 36, 37)

```ruby
module Openharness
  module Rb
    module Agents
      class AgentDefinition < Dry::Struct
        attribute :name, Types::String
        attribute :role, Types::String
        attribute :capabilities, Types::Array.of(Types::String).default([].freeze)
        attribute :tool_access, Types::Array.of(Types::String).default([].freeze)
      end

      class TeamRegistry
        def initialize(parent_permission_checker: nil)
          @agents = {}
          @mailboxes = Hash.new { |h, k| h[k] = [] }
          @parent_permissions = parent_permission_checker
        end

        def register(agent_def)
          raise DuplicateAgentError, agent_def.name if @agents.key?(agent_def.name)
          @agents[agent_def.name] = agent_def
        end

        def get(name)
          @agents.fetch(name) { raise AgentNotFoundError, name }
        end

        def list_agents
          @agents.values
        end

        def send_message(from:, to:, content:)
          raise AgentNotFoundError, to unless @agents.key?(to)
          @mailboxes[to] << { from: from, content: content, timestamp: Time.now }
        end

        def receive_messages(agent_name)
          messages = @mailboxes[agent_name].dup
          @mailboxes[agent_name].clear
          messages
        end

        def propagate_permissions(permission_checker)
          @parent_permissions = permission_checker
          # Child agents inherit this configuration
        end
      end
    end
  end
end
```

### 14. Session Storage (Req 38)

```ruby
module Openharness
  module Rb
    module Session
      class SessionStorage
        DEFAULT_DIR = File.expand_path("~/.openharness/sessions")

        def initialize(directory: DEFAULT_DIR)
          @directory = directory
          FileUtils.mkdir_p(@directory)
        end

        def save(session_id, messages:, cost_tracker:, metadata: {})
          data = {
            session_id: session_id,
            messages: messages.map(&:to_h),
            cost: cost_tracker.summary,
            metadata: metadata,
            saved_at: Time.now.iso8601
          }
          File.write(session_path(session_id), JSON.pretty_generate(data))
        end

        def load(session_id)
          path = session_path(session_id)
          raise SessionNotFoundError, session_id unless File.exist?(path)
          data = JSON.parse(File.read(path), symbolize_names: true)
          {
            messages: data[:messages].map { |m| Models::ConversationMessage.from_h(m) },
            cost: data[:cost],
            metadata: data[:metadata]
          }
        end

        private

        def session_path(id)
          File.join(@directory, "#{id}.json")
        end
      end
    end
  end
end
```

### 15. Background Task Manager (Req 15)

Uses the Async gem for fiber-based concurrency:

```ruby
module Openharness
  module Rb
    module Session
      class BackgroundTaskManager
        def initialize
          @tasks = {}
          @outputs = {}
        end

        def start(name:, command:, cwd: Dir.pwd)
          raise DuplicateTaskError, name if @tasks.key?(name)

          @outputs[name] = +""
          @tasks[name] = Async do |task|
            process = Async::Process.spawn(command, chdir: cwd)
            # Capture output asynchronously
            while (line = process.stdout.gets)
              @outputs[name] << line
            end
            process.wait
          end
        end

        def stop(name)
          task = @tasks.fetch(name) { raise TaskNotFoundError, name }
          task.stop
          @tasks.delete(name)
        end

        def list
          @tasks.map { |name, task| { name: name, status: task.status } }
        end

        def output(name)
          raise TaskNotFoundError, name unless @tasks.key?(name)
          @outputs[name]
        end
      end
    end
  end
end
```

### 16. Settings & Configuration (Req 39)

```ruby
module Openharness
  module Rb
    module Config
      class Settings < Dry::Struct
        attribute :permission_mode, Types::Symbol.default(:default)
        attribute :denied_tools, Types::Array.of(Types::String).default([].freeze)
        attribute :allowed_tools, Types::Array.of(Types::String).default([].freeze)
        attribute :path_rules, Types::Array.default([].freeze)
        attribute :denied_commands, Types::Array.default([].freeze)
        attribute :api_key, Types::String.optional
        attribute :base_url, Types::String.optional
        attribute :model, Types::String.optional
        attribute :max_turns, Types::Integer.default(10)
        attribute :context_window_threshold, Types::Integer.default(100_000)

        def self.load_file(path)
          ext = File.extname(path)
          data = case ext
                 when ".yml", ".yaml" then YAML.safe_load(File.read(path), symbolize_names: true)
                 when ".json" then JSON.parse(File.read(path), symbolize_names: true)
                 else raise ConfigurationError, "Unsupported config format: #{ext}"
                 end
          new(**data)
        rescue Dry::Struct::Error => e
          raise ConfigurationError, "Invalid configuration: #{e.message}"
        end

        def to_h
          super
        end
      end
    end
  end
end
```

### 17. System Prompt Builder (Req 40)

```ruby
module Openharness
  module Rb
    module Engine
      class SystemPromptBuilder
        PROJECT_CONTEXT_FILES = ["CLAUDE.md", ".openharness/context.md"].freeze

        def initialize(tool_registry:, skill_registry: nil, memory_system: nil, project_root: Dir.pwd)
          @tools = tool_registry
          @skills = skill_registry
          @memory = memory_system
          @project_root = project_root
        end

        def build
          sections = []
          sections << build_tool_section
          sections << build_skill_section if @skills
          sections << build_memory_section if @memory
          sections << build_project_context
          sections.compact.join("\n\n")
        end

        private

        def build_tool_section
          schemas = @tools.schemas
          "## Available Tools\n\n#{JSON.pretty_generate(schemas)}"
        end

        def build_skill_section
          names = @skills.available_names
          return nil if names.empty?
          "## Available Skills\n\n#{names.map { |n| "- #{n}" }.join("\n")}"
        end

        def build_memory_section
          @memory.load_memory_prompt
        end

        def build_project_context
          PROJECT_CONTEXT_FILES.each do |file|
            path = File.join(@project_root, file)
            return "## Project Context\n\n#{File.read(path)}" if File.exist?(path)
          end
          nil
        end
      end
    end
  end
end
```

### 18. CLI (Req 41, 42)

```ruby
module Openharness
  module Rb
    module Cli
      class Main < Thor
        desc "start", "Start an interactive agent session"
        option :provider, type: :string
        option :model, type: :string
        option :api_key, type: :string
        option :cwd, type: :string, default: Dir.pwd
        def start
          settings = load_settings(options)
          session = InteractiveSession.new(settings: settings)
          session.run
        end

        desc "setup", "Configure OpenHarness"
        def setup
          SetupWizard.new.run
        end

        map "s" => :start
      end

      class InteractiveSession
        SLASH_COMMANDS = {
          "/help" => :cmd_help,
          "/memory" => :cmd_memory,
          "/skill" => :cmd_skill,
          "/clear" => :cmd_clear,
          "/cost" => :cmd_cost,
          "/exit" => :cmd_exit,
        }.freeze

        def run
          loop do
            input = prompt_user
            break if input.nil?

            if input.start_with?("/")
              handle_slash_command(input)
            else
              process_query(input)
            end
          end
        end

        private

        def handle_slash_command(input)
          cmd, *args = input.split(" ")
          method = SLASH_COMMANDS[cmd]
          method ? send(method, *args) : puts("Unknown command: #{cmd}")
        end

        def cmd_help(*)
          SLASH_COMMANDS.each_key { |c| puts "  #{c}" }
        end

        def cmd_exit(*)
          throw :exit
        end
      end
    end
  end
end
```

## File Structure

```
lib/
  openharness/
    rb.rb                          # Main entry, requires all modules
    rb/
      version.rb                   # Gem version
      types.rb                     # Dry::Types definitions
      errors.rb                    # All error classes
      models/
        conversation_message.rb
        content_block.rb
        tool_result.rb
        stream_events.rb
        query_context.rb
        tool_execution_context.rb
      engine/
        query_engine.rb
        cost_tracker.rb
        system_prompt_builder.rb
      api/
        llm_adapter.rb
        provider_registry.rb
        provider_spec.rb
        retry_handler.rb
      tools/
        base_tool.rb
        tool_registry.rb
        builtin/
          read_file_tool.rb
          write_to_file_tool.rb
          edit_file_tool.rb
          grep_tool.rb
          glob_tool.rb
          bash_tool.rb
          skill_tool.rb
          agent_tool.rb
          web_search_tool.rb
          web_fetch_tool.rb
          lsp_tool.rb
          notebook_edit_tool.rb
          create_task_tool.rb
          list_tasks_tool.rb
          stop_task_tool.rb
          get_task_output_tool.rb
      permissions/
        permission_checker.rb
        permission_decision.rb
        permission_mode.rb
        path_rule.rb
      hooks/
        hook_event.rb
        hook_definition.rb
        hook_registry.rb
        hook_executor.rb
        types/
          command_hook.rb
          http_hook.rb
          prompt_hook.rb
      mcp/
        mcp_client_manager.rb
        mcp_tool_adapter.rb
        mcp_server_config.rb
        read_mcp_resource_tool.rb
      skills/
        skill_definition.rb
        skill_registry.rb
      plugins/
        plugin_manifest.rb
        loaded_plugin.rb
        plugin_loader.rb
      memory/
        memory_system.rb
        memory_header.rb
        tokenizer.rb
      agents/
        agent_definition.rb
        team_registry.rb
      session/
        session_storage.rb
        background_task_manager.rb
      config/
        settings.rb
      cli/
        main.rb
        interactive_session.rb
        setup_wizard.rb
```

## Correctness Properties

### Property 1: ConversationMessage Round-Trip Serialization
- Requirement: 1.5
- Property: For all valid ConversationMessage instances, `ConversationMessage.from_h(msg.to_h)` produces an object equal to the original
- Type: Round-trip
- Test: Generate random ConversationMessages with varying roles and content block types, serialize to Hash, deserialize back, assert equality

### Property 2: CostTracker Accumulation Invariant
- Requirement: 2.1, 2.2
- Property: After recording N usage entries, the CostTracker totals equal the sum of all individual entries
- Type: Invariant
- Test: Generate random sequences of (input_tokens, output_tokens, cost) tuples, record all, verify totals match sums

### Property 3: ConversationMessage Role Validation
- Requirement: 1.1, 1.3
- Property: ConversationMessage creation succeeds only for roles in {"user", "assistant", "system"} and raises for all other strings
- Type: Error condition
- Test: Generate random strings; if in valid set, creation succeeds; otherwise, raises validation error

### Property 4: PermissionChecker Precedence Invariant
- Requirement: 16.6
- Property: Sensitive path denial always takes precedence over all other rules, regardless of mode, allowed_tools, or path_rules
- Type: Invariant
- Test: Generate random PermissionChecker configurations (varying modes, allowed_tools, path_rules) and always evaluate with a sensitive path — result is always "denied"

### Property 5: PermissionChecker Mode Behavior
- Requirement: 16.2, 16.3, 16.4
- Property: In FULL_AUTO mode, non-sensitive, non-denied tool invocations are always allowed. In PLAN mode, mutating tools are always denied. In DEFAULT mode, mutating tools always require confirmation.
- Type: Invariant
- Test: Generate random tool names (not in denied/allowed lists, no sensitive paths) and verify mode-specific behavior

### Property 6: Sensitive Path Protection Immutability
- Requirement: 17.3
- Property: The SENSITIVE_PATH_PATTERNS list is frozen and cannot be modified at runtime
- Type: Invariant
- Test: Attempt to modify the patterns list and verify it raises a FrozenError

### Property 7: Session Storage Round-Trip
- Requirement: 38.3
- Property: For all valid conversation states, serializing to JSON then deserializing produces an equivalent state
- Type: Round-trip
- Test: Generate random conversation states (messages, cost data, metadata), save then load, assert equality

### Property 8: Settings Round-Trip
- Requirement: 39.4
- Property: For all valid Settings instances, `Settings.new(**settings.to_h)` produces an equivalent Settings instance
- Type: Round-trip
- Test: Generate random valid Settings with varying modes, tool lists, and thresholds, serialize to Hash, reconstruct, assert equality

### Property 9: Retry Delay Exponential Growth
- Requirement: 44.1
- Property: The computed delay for attempt N is always >= base_delay * 2^N and <= base_delay * 2^N + 1.0 (jitter bound)
- Type: Metamorphic
- Test: Generate random attempt numbers (0-10) and base_delays, compute delay, verify bounds

### Property 10: Memory Tokenizer Lowercase Invariant
- Requirement: 33.3
- Property: All tokens produced by the tokenizer are lowercase
- Type: Invariant
- Test: Generate random strings (ASCII + CJK), tokenize, verify every token equals its lowercase form

### Property 11: Memory Tokenizer CJK Segmentation
- Requirement: 33.2
- Property: For strings containing only Han ideographs, each token is exactly one character
- Type: Invariant
- Test: Generate random Han character strings, tokenize, verify each token has length 1

### Property 12: ToolRegistry Idempotent Unregister
- Requirement: 11.5
- Property: Unregistering a tool then attempting to get it raises ToolNotFoundError; unregistering a non-existent tool is a no-op
- Type: Idempotence
- Test: Register tools, unregister, verify get raises; unregister again, verify no error

### Property 13: Input Validation Error Conditions
- Requirement: 43.3
- Property: For all inputs that violate the schema (wrong types, missing required fields), validation returns a ToolResult with is_error=true
- Type: Error condition
- Test: Generate random invalid inputs (missing required keys, wrong types) against a known schema, verify is_error=true

### Property 14: ProviderRegistry Detection
- Requirement: 8.2, 8.3
- Property: For all API keys with a known prefix, detect_provider returns the correct provider. For all keys with unknown prefixes, detect_provider raises UnknownProviderError.
- Type: Error condition / Invariant
- Test: Generate keys with known prefixes (sk-, sk-ant-) and random unknown prefixes, verify correct detection or error

