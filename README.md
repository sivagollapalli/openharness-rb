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
| `--resume` | Resume a previous session (UUID or path to `.json` file) |

### Slash Commands

Inside an interactive session:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/memory` | Display memory index |
| `/skill <name>` | Load a skill into the conversation |
| `/clear` | Clear conversation history |
| `/cost` | Show token usage and cost |
| `/export` | Export conversation to a session JSON file |
| `/exit` | Exit the session (auto-exports) |

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

Hooks let you run custom logic on lifecycle events — shell commands, HTTP webhooks, or LLM-based prompt checks. They fire automatically at key points in the agent loop.

### Hook Events

| Event | When it fires |
|-------|---------------|
| `:session_start` | When an interactive session begins |
| `:session_end` | When an interactive session ends |
| `:pre_tool_use` | Before a tool is executed |
| `:post_tool_use` | After a tool finishes executing |

### Hook Types

| Type | What it does |
|------|-------------|
| `CommandHookDefinition` | Runs a shell command. Payload is available via `OPENHARNESS_HOOK_PAYLOAD` env var. |
| `HttpHookDefinition` | POSTs the payload as JSON to a URL with optional headers. |
| `PromptHookDefinition` | Sends a prompt (with `{{payload}}` interpolation) to the LLM and checks the response. |

### Defining Hooks in a Config File

Hooks can be defined in `.openharness/hooks.yml` (or any YAML/JSON file you point the registry at). Each hook specifies an event, an optional matcher (glob pattern for tool names), and the action:

```yaml
# .openharness/hooks.yml
hooks:
  - event: pre_tool_use
    matcher: "bash"           # only fires for the bash tool (nil = all tools)
    block_on_failure: true    # block the tool if the hook fails
    type: command
    command: "echo 'About to run bash'"

  - event: post_tool_use
    matcher: null             # fires for all tools
    block_on_failure: false
    type: http
    url: "https://hooks.example.com/notify"
    headers:
      Authorization: "Bearer token"

  - event: pre_tool_use
    matcher: "write_to_file"
    block_on_failure: true
    type: prompt
    prompt_template: "Review this write operation: {{payload}}. Respond with JSON {\"ok\": true} or {\"ok\": false, \"reason\": \"...\"}."
```

### Programmatic Registration

```ruby
registry = Openharness::Rb::Hooks::HookRegistry.new

# Run a shell command before every tool execution
registry.register(Openharness::Rb::Hooks::CommandHookDefinition.new(
  event: :pre_tool_use,
  matcher: nil,           # nil matches all tools
  block_on_failure: false,
  command: "echo 'Tool about to run'"
))

# POST to a webhook after bash tool execution
registry.register(Openharness::Rb::Hooks::HttpHookDefinition.new(
  event: :post_tool_use,
  matcher: "bash",
  block_on_failure: false,
  url: "https://hooks.example.com/notify",
  headers: { "Authorization" => "Bearer token" }
))

# LLM-based review before file writes
registry.register(Openharness::Rb::Hooks::PromptHookDefinition.new(
  event: :pre_tool_use,
  matcher: "write_to_file",
  block_on_failure: true,
  prompt_template: "Review this write: {{payload}}. Respond with JSON {\"ok\": true/false}."
))

executor = Openharness::Rb::Hooks::HookExecutor.new(registry: registry)
executor.dispatch(:pre_tool_use, payload: { tool_name: "bash", arguments: { command: "ls" } })
```

### Blocking vs Non-Blocking

Each hook has a `block_on_failure` flag:

- `false` (default) — if the hook fails, a warning is logged but the tool still runs.
- `true` — if the hook fails, the tool execution is blocked and an error event is emitted.

### Environment Variables for Command Hooks

When a `CommandHookDefinition` runs, these environment variables are set:

| Variable | Description |
|----------|-------------|
| `OPENHARNESS_HOOK_EVENT` | The event name (e.g. `pre_tool_use`) |
| `OPENHARNESS_HOOK_PAYLOAD` | JSON-encoded payload with tool name and arguments |

### Hot Reload

The `HookRegistry` supports file watching. When a config file changes on disk, hooks are automatically reloaded:

```ruby
registry = Openharness::Rb::Hooks::HookRegistry.new(
  config_paths: [".openharness/hooks.yml"]
)
registry.start_watching!

# ... hooks are reloaded when the file changes ...

registry.stop_watching!
```

### CLI Usage

Hooks are active during interactive sessions. The `Harness` creates a `HookExecutor` automatically, so any hooks registered in the registry fire during tool execution.

To see hooks in action during a session, watch for the hook-related output:

```bash
# Start a session — hooks fire automatically during tool use
openharness start --model gpt-4o --api-key sk-your-key

> Write a hello world file
─── Turn 1/10 ───
⚡ Calling write_to_file        # pre_tool_use hooks fire here
   │ File written: hello.rb     # post_tool_use hooks fire here
```

If a blocking hook fails, you'll see an error:

```
⚠ Hook failed for 'write_to_file': Command exited with non-zero status
```

## Skills

Skills are domain-knowledge documents that the agent can load on demand. They live as markdown files in your project and are lazy-loaded — only the catalog (name + description) is included in the system prompt, and the full content is fetched when the agent calls the built-in `skill` tool.

### Directory Layout

```
your-project/
└── .openharness/
    ├── skills.yml              # Skill catalog (name → description + file)
    └── skills/
        ├── ruby-on-rails.md    # Skill content files
        └── gin-golang.md
```

### Defining the Catalog (`skills.yml`)

`skills.yml` lists every skill the agent can see. Each entry has a name, description, and the filename in the `skills/` directory:

```yaml
# .openharness/skills.yml
skills:
  ruby-on-rails:
    description: "Complete guide to Ruby on Rails — project setup, folder structure, commands"
    file: "ruby-on-rails.md"

  gin-golang:
    description: "Guide to building web apps with Gin in Go — project structure, commands"
    file: "gin-golang.md"
```

The agent sees these descriptions in the system prompt and decides which skill to load based on the task.

### Writing a Skill File

Each skill is a markdown file in `.openharness/skills/`. Add optional YAML frontmatter for metadata:

```markdown
---
name: ruby-on-rails
description: Complete guide to Ruby on Rails — project setup, folder structure, commands
---

## Creating a New Rails Project

```bash
rails new myapp --database=postgresql
```

## Folder Structure
...
```

Frontmatter fields:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | No | Display name (defaults to filename without `.md`) |
| `description` | No | Short summary shown in the catalog |

Files without frontmatter are also valid — the first heading line is used as the name and the first non-empty line after it as the description.

### Auto-Discovery

Any `.md` file in `.openharness/skills/` that isn't listed in `skills.yml` is automatically discovered and added to the catalog. The registry parses just the frontmatter for the description, so you can skip the YAML catalog entirely if you prefer:

```
.openharness/skills/
├── ruby-on-rails.md    # listed in skills.yml
└── docker-basics.md    # not in skills.yml — auto-discovered
```

Both skills will appear in the agent's catalog.

### How It Works

1. On `Harness.new`, the `SkillRegistry` reads `.openharness/skills.yml` and scans the `skills/` directory.
2. Only names and descriptions are loaded — no file content is read yet.
3. The `SystemPromptBuilder` includes the catalog in the system prompt so the LLM knows what's available.
4. When the agent decides it needs a skill, it calls the `skill` tool with the skill name.
5. The `SkillTool` lazy-loads the full markdown content from disk, caches it, and returns it to the LLM.

### Automatic Integration via Harness

Just create the files — the `Harness` picks them up:

```ruby
harness = Openharness::Rb::Harness.new(
  api_key: "sk-your-key",
  model: "gpt-4o",
  permission_mode: :full_auto
)

# The agent will automatically load the "ruby-on-rails" skill
# when it encounters a Rails-related task.
harness.query("Create a new Rails API app with user CRUD") do |event|
  case event
  when Openharness::Rb::Models::AssistantTextDelta
    print event.text
  when Openharness::Rb::Models::SkillLoaded
    puts "[Skill loaded: #{event.skill_name}]"
  end
end
```

### Adding Skills at Runtime

```ruby
harness.add_skill(
  name: "docker-basics",
  description: "Docker containerization guide",
  content: "## Docker\n\nUse multi-stage builds..."
)
```

### Programmatic API

```ruby
registry = Openharness::Rb::Skills::SkillRegistry.new
registry.load_all

# List available skills
registry.catalog_entries
# => [{ name: "ruby-on-rails", description: "...", loaded: false }, ...]

# Load a skill (lazy — reads file on first access)
skill = registry.get("ruby-on-rails")
puts skill.name        # => "ruby-on-rails"
puts skill.description # => "Complete guide to Ruby on Rails..."
puts skill.content     # => full markdown content
```

### CLI

Inside an interactive session, use `/skill <name>` to load a skill into the conversation.

## Memory

Memory gives the agent persistent, cross-session context about your project. Memory files are markdown documents stored in `.openharness/memory/` and are automatically injected into the system prompt every time you create a `Harness` instance — no extra wiring needed.

### Directory Layout

```
your-project/
└── .openharness/
    └── memory/
        ├── MEMORY.md          # Index file (always included first)
        ├── architecture.md    # Any number of topic files
        └── conventions.md
```

### Index File (`MEMORY.md`)

`MEMORY.md` is a special file that is always loaded at the top of the memory prompt. Use it for high-level project facts the agent should always know:

```markdown
## Location
My location is in India. Always show results with respective location

## Stack
- Ruby 3.3, Rails 7.1, PostgreSQL 16
- Frontend: Hotwire + Tailwind CSS
```

### Topic Memory Files

Additional `.md` files in the same directory are scanned and summarized for the agent. Add optional YAML frontmatter for richer metadata:

```markdown
---
name: auth-flow
description: How authentication and session management work
type: architecture
---

## Authentication Flow

1. User submits credentials to `/sessions`
2. `SessionsController` calls `AuthService.authenticate`
3. On success a signed JWT is stored in an HttpOnly cookie
...
```

Frontmatter fields:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | No | Display name (defaults to filename without `.md`) |
| `description` | No | Short summary shown in the memory catalog |
| `type` | No | Free-form category (e.g. `architecture`, `convention`, `decision`) |

Files without frontmatter are still loaded — the filename is used as the name.

### How It Works

1. On `Harness.new`, the `MemorySystem` scans `.openharness/memory/` for all `.md` files (excluding `MEMORY.md`).
2. The `SystemPromptBuilder` calls `load_memory_prompt`, which concatenates the index file content and a catalog of available memories.
3. This combined text is appended to the agent's system prompt, so the LLM is aware of project context from the first turn.
4. When the agent needs deeper detail, `find_relevant_memories(query)` performs token-based search with metadata weighted 2× over body content, returning the most relevant files.

### Automatic Integration via Harness

Just create the files — the `Harness` picks them up automatically:

```ruby
harness = Openharness::Rb::Harness.new(
  api_key: "sk-your-key",
  model: "gpt-4o"
)

# Memory is already loaded into the system prompt.
# The agent knows your project context from the start.
harness.query("Explain our auth flow") do |event|
  print event.text if event.is_a?(Openharness::Rb::Models::AssistantTextDelta)
end
```

### Programmatic API

For lower-level access:

```ruby
memory = Openharness::Rb::Memory::MemorySystem.new(project_dir: Dir.pwd)

# Scan all memory files (sorted by most recent)
headers = memory.scan_memory_files

# Find relevant memories for a query (metadata weighted 2x over body)
results = memory.find_relevant_memories("authentication flow")

# Generate the prompt section that gets injected into the system prompt
prompt = memory.load_memory_prompt
```

### CLI

Inside an interactive session, use the `/memory` slash command to display the current memory index.

## Sessions

Every interactive session is automatically tracked and can be exported to a JSON file for later review or resumption. Session files are stored in `.openharness/sessions/` as `<uuid>.json`.

### How It Works

1. When a `Harness` is created, a new session is started with a unique UUID.
2. Every user message, assistant response, tool call, and tool result is recorded in the session log.
3. On `/exit`, the full conversation is auto-exported to `.openharness/sessions/<uuid>.json`.
4. You can also export mid-session with `/export`.

### Directory Layout

```
your-project/
└── .openharness/
    └── sessions/
        ├── a1b2c3d4-e5f6-7890-abcd-ef1234567890.json
        └── f9e8d7c6-b5a4-3210-fedc-ba0987654321.json
```

### Session File Format

Each session file contains the full conversation log:

```json
{
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "started_at": "2026-04-29T10:00:00+05:30",
  "exported_at": "2026-04-29T10:15:00+05:30",
  "metadata": { "model": "gpt-4o" },
  "cost": { "input_tokens": 5200, "output_tokens": 1800, "total_cost": 0.0 },
  "conversation": [
    { "role": "user", "content": "Create a hello world app", "timestamp": "..." },
    { "role": "tool_call", "tool_name": "write_to_file", "tool_use_id": "...", "arguments": { "path": "hello.rb" }, "timestamp": "..." },
    { "role": "tool_result", "tool_use_id": "...", "result": "File written", "timestamp": "..." },
    { "role": "assistant", "content": "Done! I created hello.rb for you.", "timestamp": "..." }
  ]
}
```

### Exporting a Session

From the CLI during an interactive session:

```
> /export
✓ Session exported to .openharness/sessions/a1b2c3d4-e5f6-7890-abcd-ef1234567890.json
```

Sessions are also auto-exported when you `/exit`.

Programmatically:

```ruby
harness = Openharness::Rb::Harness.new(api_key: "sk-key", model: "gpt-4o")

harness.query("Create a hello world app") do |event|
  print event.text if event.is_a?(Openharness::Rb::Models::AssistantTextDelta)
end

# Export the session at any point
path = harness.export_session
puts "Saved to #{path}"

# Access the session ID
puts harness.session_id
```

### Resuming a Session

Resume a previous session from the CLI using `--resume` with a UUID or file path. The prior conversation is replayed into the LLM context so it picks up where you left off:

```bash
# Resume by UUID (looks in .openharness/sessions/)
openharness start --resume a1b2c3d4-e5f6-7890-abcd-ef1234567890

# Resume by file path
openharness start --resume .openharness/sessions/a1b2c3d4-e5f6-7890-abcd-ef1234567890.json
```

Programmatically:

```ruby
harness = Openharness::Rb::Harness.new(
  api_key: "sk-key",
  model: "gpt-4o",
  resume_from: ".openharness/sessions/a1b2c3d4.json"
)

# The agent has full context from the previous session.
harness.query("Now add tests for what we built") do |event|
  print event.text if event.is_a?(Openharness::Rb::Models::AssistantTextDelta)
end
```

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
