# Implementation Tasks: openharness-rb

## Phase 1: Foundation — Types, Errors, and Data Models

- [x] 1.1 Create `lib/openharness/rb/types.rb` with Dry::Types module definition (Types::String, Types::Integer, Types::Bool, Types::Array, Types::Hash, Types::Symbol, Types::Any, Types::Time)
- [x] 1.2 Create `lib/openharness/rb/errors.rb` with all error classes: OpenHarnessApiError, AuthenticationFailure, RateLimitFailure (with retry_after), RequestFailure (with status_code, response_body), MaxTurnsExceeded, DuplicateToolError, ToolNotFoundError, DuplicateAgentError, AgentNotFoundError, TaskNotFoundError, SkillNotFoundError, McpServerNotConnectedError, SessionNotFoundError, ConfigurationError, UnknownProviderError, DuplicateTaskError
- [x] 1.3 Create `lib/openharness/rb/models/content_block.rb` with ContentBlock Dry::Struct (type enum: text/image/tool_use/tool_result, content Hash)
- [x] 1.4 Create `lib/openharness/rb/models/conversation_message.rb` with ConversationMessage Dry::Struct (role enum, content_blocks array, to_h/from_h methods)
- [x] 1.5 Create `lib/openharness/rb/models/tool_result.rb` with ToolResult Dry::Struct (text, is_error default false)
- [x] 1.6 Create `lib/openharness/rb/models/stream_events.rb` with StreamEvent base and subclasses: AssistantTextDelta, ToolExecutionStarted, ToolExecutionCompleted, AssistantTurnComplete, ErrorOccurred
- [x] 1.7 Create `lib/openharness/rb/models/query_context.rb` with QueryContext Dry::Struct (cwd default Dir.pwd, max_turns default 10, permission_prompt, ask_user_prompt)
- [x] 1.8 Create `lib/openharness/rb/models/tool_execution_context.rb` with ToolExecutionContext Dry::Struct (cwd, session_id, event_emitter)
- [x] 1.9 Write tests for ConversationMessage round-trip serialization, role validation, and all model creation/defaults
  - [x] 1.9.1 [PBT] Property: ConversationMessage round-trip — for all valid messages, `from_h(msg.to_h) == msg` (Property 1)
  - [x] 1.9.2 [PBT] Property: ConversationMessage role validation — creation succeeds only for valid roles, raises for others (Property 3)
  - [x] 1.9.3 Test QueryContext defaults (cwd=Dir.pwd, max_turns=10)
  - [x] 1.9.4 Test ToolExecutionContext immutability

## Phase 2: Cost Tracker and Engine Utilities

- [x] 2.1 Create `lib/openharness/rb/engine/cost_tracker.rb` with CostTracker class (initialize to zero, record method with mutex, summary method)
- [x] 2.2 Write tests for CostTracker
  - [x] 2.2.1 [PBT] Property: CostTracker accumulation — totals equal sum of all recorded entries (Property 2)
  - [x] 2.2.2 Test CostTracker initializes to zero
  - [x] 2.2.3 Test CostTracker summary returns correct Hash structure

## Phase 3: API Layer — RubyLLM Adapter and Provider Registry

- [x] 3.1 Add `ruby_llm` and `faraday` to gemspec dependencies
- [x] 3.2 Create `lib/openharness/rb/api/provider_spec.rb` with ProviderSpec Dry::Struct (name, base_url, auth_type, model_pattern, default_model)
- [x] 3.3 Create `lib/openharness/rb/api/provider_registry.rb` with ProviderRegistry class (PROVIDERS hash, detect_provider method, register method)
- [x] 3.4 Create `lib/openharness/rb/api/retry_handler.rb` with RetryHandler module (with_retry method implementing exponential backoff + jitter)
- [x] 3.5 Create `lib/openharness/rb/api/llm_adapter.rb` with LlmAdapter class wrapping RubyLLM.chat (configure, stream_messages, chunk_to_stream_event)
- [x] 3.6 Write tests for API layer
  - [x] 3.6.1 [PBT] Property: ProviderRegistry detection — known prefixes return correct provider, unknown raise error (Property 14)
  - [x] 3.6.2 [PBT] Property: Retry delay bounds — delay for attempt N is within [base*2^N, base*2^N + 1.0] (Property 9)
  - [x] 3.6.3 Test RetryHandler does not retry on 401/400
  - [x] 3.6.4 Test LlmAdapter configuration passes keys to RubyLLM

## Phase 4: Tools System — Base, Registry, and Validation

- [x] 4.1 Add `dry-types`, `dry-struct`, `dry-validation` to gemspec dependencies
- [x] 4.2 Create `lib/openharness/rb/tools/base_tool.rb` with BaseTool class (name, description, input_schema abstract methods; call method with validation and error catching)
- [x] 4.3 Create `lib/openharness/rb/tools/tool_registry.rb` with ToolRegistry class (register, get_tool, unregister, schemas, execute methods)
- [x] 4.4 Write tests for tools system
  - [x] 4.4.1 Test ToolRegistry register/get/unregister lifecycle
  - [x] 4.4.2 Test ToolRegistry raises DuplicateToolError on duplicate name
  - [x] 4.4.3 Test ToolRegistry raises ToolNotFoundError for unknown name
  - [x] 4.4.4 Test BaseTool.call catches exceptions and returns error ToolResult
  - [x] 4.4.5 [PBT] Property: Input validation error conditions — invalid inputs always produce is_error=true ToolResult (Property 13)
  - [x] 4.4.6 [PBT] Property: ToolRegistry unregister idempotence — unregister then get raises; double unregister is no-op (Property 12)

## Phase 5: Built-in Tools

- [x] 5.1 Create `lib/openharness/rb/tools/builtin/read_file_tool.rb`
- [x] 5.2 Create `lib/openharness/rb/tools/builtin/write_to_file_tool.rb`
- [x] 5.3 Create `lib/openharness/rb/tools/builtin/edit_file_tool.rb`
- [x] 5.4 Create `lib/openharness/rb/tools/builtin/grep_tool.rb`
- [x] 5.5 Create `lib/openharness/rb/tools/builtin/glob_tool.rb`
- [x] 5.6 Create `lib/openharness/rb/tools/builtin/bash_tool.rb` (with timeout, denied command check)
- [x] 5.7 Create `lib/openharness/rb/tools/builtin/skill_tool.rb`
- [x] 5.8 Create `lib/openharness/rb/tools/builtin/agent_tool.rb`
- [x] 5.9 Create `lib/openharness/rb/tools/builtin/web_search_tool.rb`
- [x] 5.10 Create `lib/openharness/rb/tools/builtin/web_fetch_tool.rb`
- [x] 5.11 Create `lib/openharness/rb/tools/builtin/lsp_tool.rb`
- [x] 5.12 Create `lib/openharness/rb/tools/builtin/notebook_edit_tool.rb`
- [x] 5.13 Create background task tools: `create_task_tool.rb`, `list_tasks_tool.rb`, `stop_task_tool.rb`, `get_task_output_tool.rb`
- [x] 5.14 Write tests for built-in tools
  - [x] 5.14.1 Test ReadFileTool reads file content, returns error for missing file
  - [x] 5.14.2 Test WriteToFileTool creates file and parent directories
  - [x] 5.14.3 Test EditFileTool applies replacement, errors on not-found or ambiguous match
  - [x] 5.14.4 Test GrepTool returns matching lines with paths and line numbers
  - [x] 5.14.5 Test GlobTool returns matching file paths
  - [x] 5.14.6 Test BashTool executes command, respects timeout, blocks denied commands

## Phase 6: Permission System

- [x] 6.1 Create `lib/openharness/rb/permissions/permission_mode.rb` with PermissionMode constants (DEFAULT, PLAN, FULL_AUTO)
- [x] 6.2 Create `lib/openharness/rb/permissions/permission_decision.rb` with PermissionDecision Dry::Struct (status enum, reason)
- [x] 6.3 Create `lib/openharness/rb/permissions/path_rule.rb` with PathRule Dry::Struct (pattern, action enum)
- [x] 6.4 Create `lib/openharness/rb/permissions/permission_checker.rb` with PermissionChecker class (SENSITIVE_PATH_PATTERNS frozen, evaluate method with strict precedence)
- [x] 6.5 Write tests for permission system
  - [x] 6.5.1 [PBT] Property: Sensitive path always denied — regardless of mode/config, sensitive paths produce "denied" (Property 4)
  - [x] 6.5.2 [PBT] Property: Mode behavior — FULL_AUTO allows, PLAN denies mutating, DEFAULT requires confirmation (Property 5)
  - [x] 6.5.3 [PBT] Property: SENSITIVE_PATH_PATTERNS is frozen (Property 6)
  - [x] 6.5.4 Test denied_tools override
  - [x] 6.5.5 Test allowed_tools override
  - [x] 6.5.6 Test path rules with glob matching (most specific wins)
  - [x] 6.5.7 Test denied command patterns (exact and regex)

## Phase 7: Hooks System

- [x] 7.1 Add `listen` gem to gemspec dependencies
- [x] 7.2 Create `lib/openharness/rb/hooks/hook_event.rb` with HookEvent constants
- [x] 7.3 Create `lib/openharness/rb/hooks/hook_definition.rb` with HookDefinition base and subclasses (CommandHookDefinition, HttpHookDefinition, PromptHookDefinition)
- [x] 7.4 Create `lib/openharness/rb/hooks/hook_registry.rb` with HookRegistry class (register, hooks_for, start_watching!, stop_watching!, reload)
- [x] 7.5 Create `lib/openharness/rb/hooks/hook_executor.rb` with HookExecutor class (dispatch, execute_command, execute_http, execute_prompt)
- [x] 7.6 Write tests for hooks system
  - [x] 7.6.1 Test HookRegistry register and hooks_for filtering by event and matcher
  - [x] 7.6.2 Test HookExecutor dispatches command hooks with env injection and shell escaping
  - [x] 7.6.3 Test HookExecutor dispatches HTTP hooks (mocked Faraday)
  - [x] 7.6.4 Test block_on_failure halts operation on hook failure
  - [x] 7.6.5 Test block_on_failure=false logs and continues on hook failure

## Phase 8: MCP Integration

- [x] 8.1 Create `lib/openharness/rb/mcp/mcp_server_config.rb` with McpServerConfig Dry::Struct (name, transport, command, args, env, url, headers)
- [x] 8.2 Create `lib/openharness/rb/mcp/mcp_client_manager.rb` with McpClientManager class (connect, disconnect_all, call_tool, list_resources, read_resource)
- [x] 8.3 Create `lib/openharness/rb/mcp/mcp_tool_adapter.rb` with McpToolAdapter extending BaseTool
- [x] 8.4 Create `lib/openharness/rb/mcp/read_mcp_resource_tool.rb` with ReadMcpResourceTool extending BaseTool
- [x] 8.5 Write tests for MCP integration
  - [x] 8.5.1 Test McpToolAdapter wraps MCP tool as BaseTool with correct name/description/schema
  - [x] 8.5.2 Test McpToolAdapter returns error ToolResult when server disconnected
  - [x] 8.5.3 Test McpClientManager tracks connection status
  - [x] 8.5.4 Test McpServerConfig validates stdio and http configurations

## Phase 9: Skills and Plugins

- [x] 9.1 Create `lib/openharness/rb/skills/skill_definition.rb` with SkillDefinition Dry::Struct
- [x] 9.2 Create `lib/openharness/rb/skills/skill_registry.rb` with SkillRegistry class (load_all, get, available_names, parse_skill_file with YAML frontmatter and H1 fallback)
- [x] 9.3 Create `lib/openharness/rb/plugins/plugin_manifest.rb` with PluginManifest Dry::Struct
- [x] 9.4 Create `lib/openharness/rb/plugins/loaded_plugin.rb` with LoadedPlugin class
- [x] 9.5 Create `lib/openharness/rb/plugins/plugin_loader.rb` with PluginLoader class (load_all, load_from_directory)
- [ ] 9.6 Write tests for skills and plugins
  - [x] 9.6.1 Test SkillRegistry parses YAML frontmatter skills
  - [x] 9.6.2 Test SkillRegistry falls back to H1/first-paragraph for skills without frontmatter
  - [x] 9.6.3 Test SkillRegistry raises SkillNotFoundError for unknown skill
  - [x] 9.6.4 Test PluginLoader discovers plugins from directories
  - [x] 9.6.5 Test PluginLoader skips invalid plugin.json with warning

## Phase 10: Memory System

- [x] 10.1 Create `lib/openharness/rb/memory/memory_header.rb` with MemoryHeader Dry::Struct
- [x] 10.2 Create `lib/openharness/rb/memory/tokenizer.rb` with Tokenizer class (tokenize method handling ASCII + CJK)
- [x] 10.3 Create `lib/openharness/rb/memory/memory_system.rb` with MemorySystem class (scan_memory_files, find_relevant_memories, load_memory_prompt)
- [ ] 10.4 Write tests for memory system
  - [x] 10.4.1 [PBT] Property: Tokenizer lowercase invariant — all tokens are lowercase (Property 10)
  - [x] 10.4.2 [PBT] Property: Tokenizer CJK segmentation — Han-only strings produce single-char tokens (Property 11)
  - [x] 10.4.3 Test MemorySystem scan_memory_files returns sorted by modification time
  - [x] 10.4.4 Test MemorySystem find_relevant_memories scores metadata 2x vs body
  - [x] 10.4.5 Test MemorySystem parses YAML frontmatter into MemoryHeader

## Phase 11: Multi-Agent Coordination

- [x] 11.1 Create `lib/openharness/rb/agents/agent_definition.rb` with AgentDefinition Dry::Struct
- [x] 11.2 Create `lib/openharness/rb/agents/team_registry.rb` with TeamRegistry class (register, get, list_agents, send_message, receive_messages, propagate_permissions)
- [x] 11.3 Write tests for multi-agent system
  - [x] 11.3.1 Test TeamRegistry register/get/list lifecycle
  - [x] 11.3.2 Test TeamRegistry raises DuplicateAgentError
  - [x] 11.3.3 Test send_message/receive_messages mailbox behavior (receive clears mailbox)
  - [x] 11.3.4 Test send_message raises AgentNotFoundError for unknown agent

## Phase 12: Session Storage

- [x] 12.1 Create `lib/openharness/rb/session/session_storage.rb` with SessionStorage class (save, load)
- [x] 12.2 Add `async` gem to gemspec dependencies
- [x] 12.3 Create `lib/openharness/rb/session/background_task_manager.rb` with BackgroundTaskManager class using Async (start, stop, list, output)
- [x] 12.4 Write tests for session and background tasks
  - [x] 12.4.1 [PBT] Property: Session storage round-trip — save then load produces equivalent state (Property 7)
  - [x] 12.4.2 Test SessionStorage raises SessionNotFoundError for missing session
  - [x] 12.4.3 Test BackgroundTaskManager start/stop/list lifecycle
  - [x] 12.4.4 Test BackgroundTaskManager raises TaskNotFoundError

## Phase 13: Settings and System Prompt Builder

- [x] 13.1 Create `lib/openharness/rb/config/settings.rb` with Settings Dry::Struct (load_file from YAML/JSON, defaults, to_h)
- [x] 13.2 Create `lib/openharness/rb/engine/system_prompt_builder.rb` with SystemPromptBuilder class (build method composing tools, skills, memory, project context)
- [x] 13.3 Write tests for settings and prompt builder
  - [x] 13.3.1 [PBT] Property: Settings round-trip — Settings.new(**settings.to_h) == settings (Property 8)
  - [x] 13.3.2 Test Settings.load_file from YAML
  - [x] 13.3.3 Test Settings.load_file raises ConfigurationError for invalid values
  - [x] 13.3.4 Test SystemPromptBuilder includes tool schemas
  - [x] 13.3.5 Test SystemPromptBuilder loads CLAUDE.md project context
  - [x] 13.3.6 Test SystemPromptBuilder omits project context when no file exists

## Phase 14: Query Engine

- [x] 14.1 Create `lib/openharness/rb/engine/query_engine.rb` with QueryEngine class (run_query loop, concurrent tool execution via Async, compaction, event emission)
- [x] 14.2 Write tests for QueryEngine
  - [x] 14.2.1 Test run_query appends user message and calls ApiClient
  - [x] 14.2.2 Test run_query executes tools when response contains tool_use blocks
  - [x] 14.2.3 Test run_query emits AssistantTurnComplete when no tool_use blocks
  - [x] 14.2.4 Test run_query raises MaxTurnsExceeded when turn limit exceeded
  - [x] 14.2.5 Test concurrent tool execution (multiple tools execute in parallel)
  - [x] 14.2.6 Test auto-compaction triggers when token count exceeds threshold

## Phase 15: CLI

- [x] 15.1 Add `thor` gem to gemspec dependencies
- [x] 15.2 Create `lib/openharness/rb/cli/main.rb` with Thor CLI (start, setup commands, --provider/--model/--api-key/--cwd options)
- [x] 15.3 Create `lib/openharness/rb/cli/interactive_session.rb` with InteractiveSession class (run loop, slash command dispatch)
- [x] 15.4 Create `lib/openharness/rb/cli/setup_wizard.rb` with SetupWizard class (provider selection, API key entry)
- [x] 15.5 Create `exe/openharness` and `exe/oh` executables
- [x] 15.6 Write tests for CLI
  - [x] 15.6.1 Test slash command dispatch (/help, /memory, /skill, /clear, /cost, /exit)
  - [x] 15.6.2 Test CLI accepts --provider, --model, --api-key flags

## Phase 16: Integration and Wiring

- [x] 16.1 Update `lib/openharness/rb.rb` to require all modules in correct dependency order
- [x] 16.2 Update `openharness-rb.gemspec` with summary, description, homepage, and all runtime dependencies
- [x] 16.3 Create `lib/openharness/rb/harness.rb` — top-level Harness class that wires together all components (Settings → ApiAdapter → ToolRegistry → PermissionChecker → HookExecutor → QueryEngine)
- [x] 16.4 Write integration test: full query cycle with mocked LLM (user message → tool call → tool result → final answer)
