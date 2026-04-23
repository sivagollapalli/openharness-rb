# OpenHarness Ruby (openharness-rb)

A Ruby port of [OpenHarness](https://github.com/HKUDS/OpenHarness) — lightweight agent infrastructure that turns an LLM into a functional software engineering agent. Supports tool-use, skills, memory, permissions, hooks, MCP integration, and multi-agent coordination.

## Installation

Add to your Gemfile:

```ruby
gem "openharness-rb"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install openharness-rb
```

Requires Ruby >= 3.2.0.

## Quick Start

### CLI

Run the setup wizard to configure your provider and API key:

```bash
openharness setup
# or
oh setup
```

Start an interactive session:

```bash
openharness start --provider openai --model gpt-4o --api-key sk-your-key
# or simply
oh
```

CLI options:

| Flag | Description |
|------|-------------|
| `--provider` | LLM provider name (openai, anthropic, gemini) |
| `--model` | Model identifier (e.g. gpt-4o, claude-sonnet-4-20250514) |
| `--api-key` | API key for the provider |
| `--cwd` | Working directory (defaults to current dir) |

### Slash Commands

Inside an interactive session:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/memory` | Display memory index |
| `/skill <name>` | Load a skill into the conversation |
| `/clear` | Clear conversation history |
| `/cost` | Show token usage and cost |
| `/exit` | Exit the session |

## Programmatic Usage

### Basic Harness

The `Harness` class wires everything together for you:

```ruby
require "openharness/rb"

harness = Openharness::Rb::Harness.new(
  api_key: "sk-your-key",
  model: "gpt-4o",
  permission_mode: :full_auto,
  max_turns: 20
)

# Register custom tools
harness.tool_registry.register(MyCustomTool.new)

# Run a query and handle streaming events
harness.query("List the files in this directory") do |event|
  case event
  when Openharness::Rb::Models::AssistantTextDelta
    print event.text
  when Openharness::Rb::Models::ToolExecutionStarted
    puts "\n[Executing #{event.tool_name}...]"
  when Openharness::Rb::Models::AssistantTurnComplete
    puts "\n[Done]"
  end
end
```

### Loading Settings from a File

```ruby
# config.yml
# permission_mode: default
# api_key: sk-your-key
# model: gpt-4o
# max_turns: 15
# denied_tools:
#   - bash
# denied_commands:
#   - "rm -rf /"

settings = Openharness::Rb::Config::Settings.load_file("config.yml")
harness = Openharness::Rb::Harness.new(settings: settings)
```

Settings also support JSON files. All fields have sensible defaults.

### Assembling Components Manually

For full control, wire the `QueryEngine` yourself:

```ruby
require "openharness/rb"

# QueryEngine uses RubyLLM directly — pass model, tools, and API keys
engine = Openharness::Rb::Engine::QueryEngine.new(
  model: "gpt-4o",
  tools: [
    Openharness::Rb::Tools::Builtin::ReadFileTool,
    Openharness::Rb::Tools::Builtin::BashTool,
    Openharness::Rb::Tools::Builtin::GrepTool,
    Openharness::Rb::Tools::Builtin::GlobTool,
  ],
  provider_config: { openai_api_key: "sk-your-key" }
)

# Ask a question — RubyLLM handles the tool-calling loop automatically
engine.ask("What Ruby files are in this project?") do |event|
  case event
  when Openharness::Rb::Models::AssistantTextDelta
    print event.text
  when Openharness::Rb::Models::ToolExecutionStarted
    puts "\n[Executing #{event.tool_name}...]"
  when Openharness::Rb::Models::AssistantTurnComplete
    puts "\n[Done]"
  end
end

# Reset conversation
engine.clear!

# Add tools at runtime
engine.add_tool(MyCustomTool)
```

## Custom Tools

Create tools by subclassing `BaseTool`:

```ruby
class WeatherTool < Openharness::Rb::Tools::BaseTool
  def name = "get_weather"
  def description = "Get current weather for a city"

  def input_schema
    {
      type: "object",
      properties: { city: { type: "string" } },
      required: ["city"]
    }
  end

  private

  def execute(input, context)
    city = input[:city] || input["city"]
    # Your weather API logic here
    Openharness::Rb::Models::ToolResult.new(text: "72°F and sunny in #{city}")
  end
end

harness.tool_registry.register(WeatherTool.new)
```

## Built-in Tools

| Tool | Description |
|------|-------------|
| `read_file` | Read file contents |
| `write_to_file` | Write content to a file (creates parent dirs) |
| `edit_file` | Apply text replacement in a file |
| `grep` | Search files with regex patterns |
| `glob` | List files matching a glob pattern |
| `bash` | Execute shell commands (with timeout) |
| `skill` | Load a skill into the conversation |
| `agent` | Spawn a sub-agent for delegated tasks |
| `web_search` | Search the web (placeholder) |
| `web_fetch` | Fetch a web page via HTTP |
| `lsp` | Language Server Protocol integration (placeholder) |
| `notebook_edit` | Read/edit Jupyter notebook cells |
| `create_task` | Start a background task |
| `list_tasks` | List active background tasks |
| `stop_task` | Stop a background task |
| `get_task_output` | Get output from a background task |

## Permissions

Three permission modes control tool execution safety:

```ruby
# DEFAULT — mutating tools require confirmation, read-only tools allowed
Openharness::Rb::Permissions::PermissionMode::DEFAULT

# PLAN — mutating tools blocked, read-only tools allowed
Openharness::Rb::Permissions::PermissionMode::PLAN

# FULL_AUTO — all tools allowed without confirmation
Openharness::Rb::Permissions::PermissionMode::FULL_AUTO
```

Sensitive paths (SSH keys, AWS credentials, .env files) are always protected regardless of mode. You can also configure:

```ruby
perms = Openharness::Rb::Permissions::PermissionChecker.new(
  mode: Openharness::Rb::Permissions::PermissionMode::DEFAULT,
  denied_tools: ["bash"],                    # block specific tools
  allowed_tools: ["read_file"],              # skip confirmation for specific tools
  denied_commands: ["rm -rf /", /sudo\s/],   # block dangerous commands
  path_rules: [
    Openharness::Rb::Permissions::PathRule.new(pattern: "/secrets/*", action: "deny"),
    Openharness::Rb::Permissions::PathRule.new(pattern: "/src/*", action: "allow"),
  ]
)
```

## Hooks

Hooks let you run custom logic on lifecycle events:

```ruby
registry = Openharness::Rb::Hooks::HookRegistry.new

# Run a shell command before every tool execution
registry.register(Openharness::Rb::Hooks::CommandHookDefinition.new(
  event: :pre_tool_use,
  matcher: nil,           # nil matches all tools
  block_on_failure: false,
  command: "echo 'Tool about to run'"
))

# POST to a webhook after tool execution
registry.register(Openharness::Rb::Hooks::HttpHookDefinition.new(
  event: :post_tool_use,
  matcher: "bash",
  block_on_failure: false,
  url: "https://hooks.example.com/notify",
  headers: { "Authorization" => "Bearer token" }
))

executor = Openharness::Rb::Hooks::HookExecutor.new(registry: registry)
executor.dispatch(:pre_tool_use, payload: { tool: "bash", args: {} })
```

Hook types: `CommandHookDefinition`, `HttpHookDefinition`, `PromptHookDefinition`

The registry supports hot-reload via file watching with `start_watching!`.

## Skills

Skills are markdown files loaded on-demand into the LLM context:

```markdown
<!-- ~/.openharness/skills/ruby-testing.md -->
---
name: ruby-testing
description: Best practices for testing Ruby applications
---
## Ruby Testing Guide

Use Minitest or RSpec. Always write tests first...
```

```ruby
registry = Openharness::Rb::Skills::SkillRegistry.new
registry.load_all  # loads from ~/.openharness/skills/ and bundled skills

skill = registry.get("ruby-testing")
puts skill.content
```

## Memory

Cross-session memory stored as markdown files with weighted search:

```ruby
memory = Openharness::Rb::Memory::MemorySystem.new(project_dir: Dir.pwd)

# Scan all memory files (sorted by most recent)
headers = memory.scan_memory_files

# Find relevant memories for a query (metadata weighted 2x over body)
results = memory.find_relevant_memories("authentication flow")

# Generate a prompt section for the LLM
prompt = memory.load_memory_prompt
```

Memory files live in `.openharness/memory/` with an optional `MEMORY.md` index.

## MCP Integration

OpenHarness integrates with [Model Context Protocol](https://modelcontextprotocol.io/) servers via the [ruby_llm-mcp](https://github.com/patvice/ruby_llm-mcp) gem. MCP tools are automatically discovered and added alongside built-in tools.

### Via Harness Config (Recommended)

Pass MCP servers when creating the harness. Tools are connected and registered automatically:

```ruby
harness = Openharness::Rb::Harness.new(
  api_key: ENV["OPENAI_API_KEY"],
  model: "gpt-4o",
  mcp_servers: [
    # Stdio transport — runs a local process
    {
      name: "filesystem",
      transport: "stdio",
      config: {
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", Dir.pwd]
      }
    },
    # Playwright browser automation
    {
      name: "playwright",
      transport: "stdio",
      config: {
        command: "npx",
        args: ["@playwright/mcp@latest"]
      }
    },
    # HTTP/Streamable transport — connects to a remote server
    {
      name: "remote-api",
      transport: "http",
      config: {
        url: "https://mcp.example.com/api"
      }
    }
  ]
)

# MCP tools are now available alongside built-in tools
harness.query("List files modified today") do |event|
  print event.text if event.is_a?(Openharness::Rb::Models::AssistantTextDelta)
end
```

### Adding MCP Servers at Runtime

```ruby
harness = Openharness::Rb::Harness.new(api_key: "sk-key", model: "gpt-4o")

# Add a server after initialization — its tools are registered immediately
harness.add_mcp_server(
  name: "sqlite",
  transport: "stdio",
  config: { command: "mcp-server-sqlite", args: ["mydb.sqlite"] }
)
```

### Using McpClientManager Directly

For lower-level control:

```ruby
manager = Openharness::Rb::Mcp::McpClientManager.new

# Connect a server
manager.connect(
  name: "filesystem",
  transport: "stdio",
  config: { command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", Dir.pwd] }
)

# Get all tools (RubyLLM-compatible, pass directly to chat.with_tools)
tools = manager.tools

# Get resources from a specific server
resources = manager.client("filesystem").resources

# Check connection status
manager.statuses  # => { "filesystem" => :connected }

# Disconnect all
manager.disconnect_all
```

### Config Formats

Both formats work — nested `config:` (matching ruby_llm-mcp) or flat keys:

```ruby
# Format 1: Nested config (recommended)
{ name: "fs", transport: "stdio", config: { command: "npx", args: ["..."] } }

# Format 2: Flat keys
{ name: "fs", transport: "stdio", command: "npx", args: ["..."] }

# Format 3: McpServerConfig struct
Openharness::Rb::Mcp::McpServerConfig.new(
  name: "fs", transport: "stdio", command: "npx", args: ["..."]
)
```

### Supported Transports

| Transport | Config Key | Description |
|-----------|-----------|-------------|
| `stdio` | `command`, `args`, `env` | Spawns a local process |
| `http` / `streamable` | `url`, `headers` | Connects to a remote HTTP server |
| `sse` | `url`, `headers` | Server-Sent Events transport |

### Settings File with MCP

```yaml
# config.yml
api_key: sk-your-key
model: gpt-4o
mcp_servers:
  - name: filesystem
    transport: stdio
    config:
      command: npx
      args: ["-y", "@modelcontextprotocol/server-filesystem", "."]
  - name: github
    transport: http
    config:
      url: https://mcp-github.example.com
```

### Error Handling

Failed MCP connections log a warning and continue without those tools. The harness remains functional with its built-in tools:

```
MCP server 'broken-server' failed to connect: Connection refused
```

## Multi-Agent Coordination

Coordinate multiple agents with mailbox messaging:

```ruby
registry = Openharness::Rb::Agents::TeamRegistry.new

registry.register(Openharness::Rb::Agents::AgentDefinition.new(
  name: "coder",
  role: "developer",
  capabilities: ["write_code", "debug"],
  tool_access: ["read_file", "write_to_file", "bash"]
))

registry.register(Openharness::Rb::Agents::AgentDefinition.new(
  name: "reviewer",
  role: "code_reviewer",
  capabilities: ["review_code"]
))

# Send messages between agents
registry.send_message(from: "coder", to: "reviewer", content: "Please review PR #42")
messages = registry.receive_messages("reviewer")
```

## Plugins

Plugins bundle skills, hooks, agents, and MCP servers in a directory:

```
~/.openharness/plugins/my-plugin/
  plugin.json
  skills/
    my-skill.md
```

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "skills": ["my-skill"],
  "hooks": [],
  "mcp_servers": []
}
```

```ruby
loader = Openharness::Rb::Plugins::PluginLoader.new
plugins = loader.load_all
```

## Architecture

```
Openharness::Rb
├── Models/          # ConversationMessage, StreamEvents, ToolResult, QueryContext
├── Engine/          # QueryEngine, CostTracker, SystemPromptBuilder
├── Api/             # ProviderRegistry, RetryHandler
├── Tools/           # BaseTool, ToolRegistry, 16 built-in tools
├── Permissions/     # PermissionChecker, PathRule, 3 permission modes
├── Hooks/           # HookExecutor, HookRegistry, Command/HTTP/Prompt hooks
├── Mcp/             # McpClientManager (ruby_llm-mcp integration)
├── Skills/          # SkillDefinition, SkillRegistry
├── Plugins/         # PluginManifest, PluginLoader
├── Memory/          # MemorySystem, Tokenizer (ASCII + CJK)
├── Agents/          # TeamRegistry, AgentDefinition, mailbox messaging
├── Session/         # SessionStorage, BackgroundTaskManager
├── Config/          # Settings (YAML/JSON)
└── Cli/             # Thor CLI, InteractiveSession, SetupWizard
```

## Development

```bash
bin/setup          # install dependencies
rake test          # run tests
bin/console        # interactive prompt
```

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
