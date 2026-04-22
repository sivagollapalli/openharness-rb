# Requirements Document

## Introduction

This document specifies the requirements for **openharness-rb**, a Ruby gem that ports the OpenHarness Python agent harness to idiomatic Ruby. OpenHarness provides lightweight infrastructure to turn an LLM into a functional software engineering agent, supporting tool-use, skills, memory, permissions, hooks, and multi-agent coordination. The Ruby port targets Ruby >= 3.2.0 and follows standard gem conventions, using idiomatic Ruby patterns and libraries (dry-types, Async, Faraday, Thor).

## Glossary

- **QueryEngine**: The high-level state manager that holds conversation history, cost tracking, and drives the thought-action-observation loop
- **ConversationMessage**: A data structure representing a single message in the conversation, containing role, content blocks, and tool use references
- **CostTracker**: A component that accumulates token usage and cost metrics across LLM API calls
- **StreamEvent**: A typed event emitted during streaming LLM responses (e.g., text deltas, tool execution signals, turn completion)
- **ApiClient**: An adapter that communicates with a specific LLM provider's API, translating between the harness's internal schema and the provider's wire format
- **ProviderSpec**: A configuration record describing an LLM provider's endpoint, authentication method, and capabilities
- **ProviderRegistry**: A registry that maps provider names to their ProviderSpec definitions and supports auto-detection
- **BaseTool**: The abstract base class for all tools, defining the interface for name, description, input schema, and execution
- **ToolRegistry**: A registry that discovers, stores, and manages the lifecycle of tool instances
- **ToolExecutionContext**: A data structure carrying runtime context for tool execution, including working directory, session ID, and event emitters
- **ToolResult**: A data structure representing the output of a tool execution, containing text content and an error flag
- **PermissionChecker**: A component that evaluates whether a given tool invocation or file access is allowed, requires confirmation, or is denied
- **PermissionMode**: An enumeration of permission enforcement levels: DEFAULT, PLAN, and FULL_AUTO
- **PermissionDecision**: A data structure representing the outcome of a permission evaluation (allowed, requires_confirmation, denied)
- **PathRule**: A rule that matches file paths using glob patterns to determine permission behavior
- **HookEvent**: An enumeration of lifecycle events that can trigger hooks: SESSION_START, SESSION_END, PRE_TOOL_USE, POST_TOOL_USE
- **HookDefinition**: The base configuration for a hook, including event matcher (glob pattern) and block_on_failure flag
- **HookExecutor**: A component that manages the HookRegistry and dispatches hook executions
- **HookRegistry**: A registry that stores and retrieves hook definitions by event type
- **McpClientManager**: An orchestrator that manages connections to all MCP servers and routes tool/resource requests
- **McpToolAdapter**: A wrapper that exposes an MCP server's tool as a BaseTool instance with dynamically generated input validation
- **McpServerConfig**: A configuration record for an MCP server connection (transport type, command, URL, environment)
- **SkillDefinition**: A data structure representing a skill with name, description, and markdown content
- **SkillRegistry**: A registry that aggregates skills from bundled, user, and plugin sources
- **PluginManifest**: A JSON manifest describing a plugin's contributions (skills, commands, agents, hooks, MCP servers)
- **LoadedPlugin**: A runtime representation of a plugin loaded from a directory with its manifest and contributed components
- **MemoryHeader**: A data structure representing metadata about a memory file (name, description, type, modification time)
- **TeamRegistry**: A registry that manages agent definitions and their lifecycle in multi-agent coordination
- **AgentDefinition**: A configuration record describing an agent's role, capabilities, and tool access
- **BackgroundTaskManager**: A component that manages long-running background tasks with start, stop, list, and output retrieval
- **Settings**: A configuration model holding permission settings, provider configs, and runtime options
- **SystemPromptBuilder**: A component that assembles the system prompt from tool schemas, skills, memory, and project context

## Requirements

### Requirement 1: Conversation Message Model

**User Story:** As a developer, I want a structured conversation message model, so that I can represent LLM conversation history with typed content blocks and tool use references.

#### Acceptance Criteria

1. THE ConversationMessage SHALL represent a message with a role attribute constrained to "user", "assistant", or "system"
2. THE ConversationMessage SHALL contain an ordered list of content blocks, where each block is one of: text, image, tool_use, or tool_result
3. WHEN a ConversationMessage is created with an invalid role value, THE ConversationMessage SHALL raise a validation error specifying the invalid value
4. THE ConversationMessage SHALL support serialization to a Hash and deserialization from a Hash using consistent key names
5. FOR ALL valid ConversationMessage instances, serializing to Hash then deserializing back SHALL produce an equivalent ConversationMessage (round-trip property)

### Requirement 2: Cost Tracker

**User Story:** As a developer, I want to track token usage and costs across LLM API calls, so that I can monitor and control spending.

#### Acceptance Criteria

1. THE CostTracker SHALL accumulate input_tokens, output_tokens, and total_cost across multiple recording calls
2. WHEN a usage record is added, THE CostTracker SHALL increment the running totals by the recorded amounts
3. THE CostTracker SHALL initialize all counters to zero
4. THE CostTracker SHALL provide a summary Hash containing input_tokens, output_tokens, and total_cost

### Requirement 3: Stream Event Hierarchy

**User Story:** As a developer, I want typed streaming events, so that I can react to different phases of an LLM response in a type-safe manner.

#### Acceptance Criteria

1. THE StreamEvent hierarchy SHALL define the following event types: AssistantTextDelta, ToolExecutionStarted, ToolExecutionCompleted, AssistantTurnComplete, and ErrorOccurred
2. THE AssistantTextDelta event SHALL carry a text attribute containing the incremental text content
3. THE ToolExecutionStarted event SHALL carry tool_name and tool_use_id attributes
4. THE ToolExecutionCompleted event SHALL carry tool_use_id and a ToolResult attribute
5. THE AssistantTurnComplete event SHALL carry a stop_reason attribute
6. THE ErrorOccurred event SHALL carry an error attribute containing the exception instance

### Requirement 4: Query Engine Core Loop

**User Story:** As a developer, I want a query engine that drives the thought-action-observation cycle, so that the LLM can iteratively reason and use tools to complete tasks.

#### Acceptance Criteria

1. WHEN run_query is called with a user message, THE QueryEngine SHALL append the message to conversation history and send the full history to the ApiClient
2. WHEN the ApiClient response contains tool_use blocks, THE QueryEngine SHALL execute each referenced tool via the ToolRegistry and append tool_result messages to the conversation history
3. WHEN the ApiClient response contains no tool_use blocks, THE QueryEngine SHALL treat the response as the final answer and emit an AssistantTurnComplete event
4. WHILE the turn count has not exceeded max_turns, THE QueryEngine SHALL continue the thought-action-observation loop
5. WHEN the turn count exceeds max_turns, THE QueryEngine SHALL raise a MaxTurnsExceeded error
6. WHEN multiple tool_use blocks are present in a single response, THE QueryEngine SHALL execute the tools concurrently using asynchronous fibers
7. THE QueryEngine SHALL emit StreamEvent instances for each phase of the loop (text deltas, tool starts, tool completions, turn completion)

### Requirement 5: Conversation History Auto-Compaction

**User Story:** As a developer, I want automatic compaction of conversation history when the context window fills, so that the agent can continue operating on long tasks without exceeding token limits.

#### Acceptance Criteria

1. WHEN the total token count of the conversation history exceeds a configurable context_window_threshold, THE QueryEngine SHALL compact the history by summarizing older messages
2. THE QueryEngine SHALL preserve the system prompt and the most recent N messages (where N is configurable) during compaction
3. THE QueryEngine SHALL replace compacted messages with a single summary message that retains key context
4. AFTER compaction, the total token count of the conversation history SHALL be below the context_window_threshold

### Requirement 6: Query Context

**User Story:** As a developer, I want a query context object that carries runtime configuration, so that each query execution has access to working directory, turn limits, and callback hooks.

#### Acceptance Criteria

1. THE QueryContext SHALL carry cwd (working directory path), max_turns (integer), permission_prompt (callable), and ask_user_prompt (callable) attributes
2. WHEN QueryContext is created without max_turns, THE QueryContext SHALL default max_turns to 10
3. WHEN QueryContext is created without cwd, THE QueryContext SHALL default cwd to the current working directory


### Requirement 7: Multi-Provider API Client Layer

**User Story:** As a developer, I want a pluggable API client layer supporting multiple LLM providers, so that I can switch between providers without changing application code.

#### Acceptance Criteria

1. Please use https://rubyllm.com/ gem to integrate with LLM APIs like openAI, gemini.

### Requirement 8: Provider Registry and Auto-Detection

**User Story:** As a developer, I want automatic provider detection from API keys and base URLs, so that I can configure the harness with minimal boilerplate.

#### Acceptance Criteria

1. THE ProviderRegistry SHALL store ProviderSpec entries keyed by provider name
2. WHEN detect_provider is called with an api_key and optional base_url, THE ProviderRegistry SHALL return the matching ProviderSpec based on key prefix patterns and URL patterns
3. IF detect_provider cannot match any registered provider, THEN THE ProviderRegistry SHALL raise an UnknownProviderError with the provided key prefix
4. THE ProviderSpec SHALL carry name, base_url, auth_type, model_pattern, and default_model attributes

### Requirement 9: API Error Hierarchy

**User Story:** As a developer, I want a structured error hierarchy for API failures, so that I can handle different failure modes appropriately.

#### Acceptance Criteria

1. THE error hierarchy SHALL define OpenHarnessApiError as the base class, with AuthenticationFailure, RateLimitFailure, and RequestFailure as subclasses
2. THE RateLimitFailure SHALL carry a retry_after attribute indicating the recommended wait time in seconds
3. THE RequestFailure SHALL carry status_code and response_body attributes

### Requirement 10: Base Tool Interface

**User Story:** As a developer, I want a standard tool interface, so that all tools share a consistent contract for name, description, input validation, and execution.

#### Acceptance Criteria

1. THE BaseTool SHALL define abstract methods: execute(input, context), and readers: name, description, input_schema
2. THE input_schema SHALL return a Hash describing the tool's input parameters using JSON Schema-compatible structure
3. WHEN execute is called, THE BaseTool SHALL return a ToolResult containing text content and an is_error boolean flag
4. WHEN execute raises an unhandled exception, THE BaseTool SHALL catch the exception and return a ToolResult with is_error set to true and the exception message as text

### Requirement 11: Tool Registry

**User Story:** As a developer, I want a tool registry for discovering and managing tools, so that the engine can look up tools by name and generate schemas for the LLM system prompt.

#### Acceptance Criteria

1. THE ToolRegistry SHALL support registering BaseTool instances by name
2. WHEN a tool is registered with a name that already exists, THE ToolRegistry SHALL raise a DuplicateToolError
3. WHEN get_tool is called with an unregistered name, THE ToolRegistry SHALL raise a ToolNotFoundError
4. THE ToolRegistry SHALL provide a method to generate an array of tool schema Hashes suitable for LLM system prompt injection
5. THE ToolRegistry SHALL support unregistering tools by name

### Requirement 12: Tool Execution Context

**User Story:** As a developer, I want a tool execution context, so that tools have access to runtime information like working directory and session identity.

#### Acceptance Criteria

1. THE ToolExecutionContext SHALL carry cwd (String), session_id (String), and event_emitter (callable) attributes
2. THE ToolExecutionContext SHALL be immutable after creation

### Requirement 13: Built-in File I/O Tools

**User Story:** As a developer, I want built-in file I/O tools, so that the agent can read, write, edit, search, and glob files on the filesystem.

#### Acceptance Criteria

1. THE ReadFileTool SHALL read a file at a given path relative to cwd and return its contents as a ToolResult
2. WHEN the target file does not exist, THE ReadFileTool SHALL return a ToolResult with is_error set to true and a descriptive message
3. THE WriteToFileTool SHALL write content to a file at a given path relative to cwd, creating parent directories as needed
4. THE EditFileTool SHALL apply a specified text replacement (old_str, new_str) to a file, failing with an error if old_str is not found or matches multiple locations
5. THE GrepTool SHALL search files matching a glob pattern for lines matching a regex pattern and return matching lines with file paths and line numbers
6. THE GlobTool SHALL return a list of file paths matching a given glob pattern relative to cwd

### Requirement 14: Built-in Shell Tool

**User Story:** As a developer, I want a shell execution tool with timeout and safety controls, so that the agent can run commands while respecting security boundaries.

#### Acceptance Criteria

1. WHEN a command is provided, THE BashTool SHALL execute the command in a subprocess with the working directory set to cwd from the ToolExecutionContext
2. WHEN a timeout value is specified, THE BashTool SHALL terminate the subprocess and return a timeout error if execution exceeds the timeout duration in seconds
3. WHEN no timeout is specified, THE BashTool SHALL use a default timeout of 120 seconds
4. THE BashTool SHALL return a ToolResult containing combined stdout and stderr output
5. IF the command matches a denied_commands pattern from the PermissionChecker, THEN THE BashTool SHALL return a ToolResult with is_error set to true without executing the command

### Requirement 15: Background Task Management Tools

**User Story:** As a developer, I want background task management, so that the agent can start, monitor, and stop long-running processes.

#### Acceptance Criteria

1. Please use async gem https://socketry.github.io/async/guides/getting-started/index to work with fibers
2. THE BackgroundTaskManager SHALL support starting a named task that runs a command in a background fiber
3. THE BackgroundTaskManager SHALL support listing all active tasks with their names and statuses
4. THE BackgroundTaskManager SHALL support stopping a task by name, terminating its underlying process
5. THE BackgroundTaskManager SHALL support retrieving the latest output (stdout and stderr) of a running task by name
6. IF a task with the given name does not exist, THEN THE BackgroundTaskManager SHALL raise a TaskNotFoundError

### Requirement 16: Permission Checker

**User Story:** As a developer, I want a permission system that controls tool and file access, so that the agent operates within defined security boundaries.

#### Acceptance Criteria

1. THE PermissionChecker SHALL evaluate tool invocations and return a PermissionDecision (allowed, requires_confirmation, or denied)
2. WHILE PermissionMode is set to FULL_AUTO, THE PermissionChecker SHALL allow all tool invocations without confirmation
3. WHILE PermissionMode is set to PLAN, THE PermissionChecker SHALL deny all mutating tool invocations
4. WHILE PermissionMode is set to DEFAULT, THE PermissionChecker SHALL require confirmation for mutating tool invocations
5. THE PermissionChecker SHALL deny access to paths matching SENSITIVE_PATH_PATTERNS (SSH keys, AWS/GCP/Azure credentials, Kubernetes tokens) regardless of PermissionMode
6. THE PermissionChecker SHALL evaluate rules in strict precedence order: sensitive paths, denied tools, allowed tools, path rules, command patterns, mode resolution
7. WHEN a tool is listed in denied_tools, THE PermissionChecker SHALL deny the invocation regardless of other rules
8. WHEN a tool is listed in allowed_tools, THE PermissionChecker SHALL allow the invocation without confirmation


### Requirement 17: Sensitive Path Protection

**User Story:** As a developer, I want hardcoded protection for sensitive credential files, so that the agent cannot read or modify secrets regardless of configuration.

#### Acceptance Criteria

1. THE PermissionChecker SHALL maintain a SENSITIVE_PATH_PATTERNS list containing glob patterns for: ~/.ssh/*, ~/.aws/credentials, ~/.config/gcloud/*, ~/.kube/config, and equivalent platform-specific paths
2. WHEN a file operation targets a path matching any SENSITIVE_PATH_PATTERNS entry, THE PermissionChecker SHALL return a denied PermissionDecision with a descriptive reason
3. THE SENSITIVE_PATH_PATTERNS list SHALL NOT be modifiable through user configuration

### Requirement 18: Path Rules with Glob Matching

**User Story:** As a developer, I want configurable path rules using glob patterns, so that I can define fine-grained file access policies.

#### Acceptance Criteria

1. THE PathRule SHALL carry a glob pattern and an action (allow or deny)
2. WHEN a file path matches a PathRule glob pattern, THE PermissionChecker SHALL apply the PathRule's action to the PermissionDecision
3. WHEN multiple PathRules match a file path, THE PermissionChecker SHALL apply the most specific (longest) matching rule

### Requirement 19: Denied Command Patterns

**User Story:** As a developer, I want configurable denied command patterns, so that dangerous shell commands are blocked before execution.

#### Acceptance Criteria

1. THE PermissionChecker SHALL maintain a list of denied_commands patterns (e.g., "rm -rf /", "mkfs", "dd if=")
2. WHEN a shell command matches any denied_commands pattern, THE PermissionChecker SHALL return a denied PermissionDecision
3. THE denied_commands patterns SHALL support both exact string matching and regex matching

### Requirement 20: Hook Event System

**User Story:** As a developer, I want a hook system that triggers actions on lifecycle events, so that I can extend the harness behavior at well-defined extension points.

#### Acceptance Criteria

1. THE HookEvent enumeration SHALL define: SESSION_START, SESSION_END, PRE_TOOL_USE, and POST_TOOL_USE values
2. THE HookDefinition SHALL carry an event type, a matcher glob pattern, and a block_on_failure boolean flag
3. THE HookExecutor SHALL dispatch all matching hooks when a HookEvent is emitted
4. WHEN block_on_failure is true and a hook execution fails, THE HookExecutor SHALL halt the current operation and return the aggregated failure result
5. WHEN block_on_failure is false and a hook execution fails, THE HookExecutor SHALL log the failure and continue the current operation

### Requirement 21: Command Hook Type

**User Story:** As a developer, I want command hooks that execute shell commands on lifecycle events, so that I can integrate external scripts into the agent workflow.

#### Acceptance Criteria

1. WHEN a CommandHookDefinition is triggered, THE HookExecutor SHALL execute the specified shell command in a subprocess
2. THE HookExecutor SHALL inject OPENHARNESS_HOOK_EVENT and OPENHARNESS_HOOK_PAYLOAD environment variables into the subprocess
3. THE HookExecutor SHALL sanitize all injected environment variable values using shell escaping to prevent shell injection

### Requirement 22: HTTP Hook Type

**User Story:** As a developer, I want HTTP hooks that send POST requests to webhooks, so that I can notify external services of agent lifecycle events.

#### Acceptance Criteria

1. WHEN an HttpHookDefinition is triggered, THE HookExecutor SHALL send an HTTP POST request to the configured URL with the hook payload as JSON body
2. IF the HTTP request fails or returns a non-2xx status code, THEN THE HookExecutor SHALL treat the hook as failed

### Requirement 23: Prompt Hook Type

**User Story:** As a developer, I want prompt hooks that use an LLM to validate tool invocations, so that I can add intelligent guardrails to agent behavior.

#### Acceptance Criteria

1. WHEN a PromptHookDefinition is triggered, THE HookExecutor SHALL send the hook payload to an LLM via the configured ApiClient
2. THE PromptHookDefinition SHALL expect the LLM response to contain a JSON object with "ok" (boolean) and "reason" (string) fields
3. WHEN the LLM response contains ok=false, THE HookExecutor SHALL treat the hook as failed with the provided reason

### Requirement 24: Hook Configuration Hot-Reload

**User Story:** As a developer, I want hooks to reload automatically when configuration files change, so that I can update hook behavior without restarting the agent.

#### Acceptance Criteria

1. THE HookRegistry SHALL monitor hook configuration files for changes using a file watcher
2. WHEN a hook configuration file is modified, THE HookRegistry SHALL reload the affected hook definitions within 5 seconds
3. WHEN a hook configuration file contains invalid syntax, THE HookRegistry SHALL log a warning and retain the previous valid configuration

### Requirement 25: MCP Client Manager

**User Story:** As a developer, I want an MCP client manager that orchestrates connections to MCP servers, so that the agent can access external tools and resources via the Model Context Protocol.

#### Acceptance Criteria

1. THE McpClientManager SHALL support connecting to MCP servers via stdio transport (spawning local processes)
2. THE McpClientManager SHALL support connecting to MCP servers via HTTP transport (streamable HTTP)
3. THE McpClientManager SHALL track connection status for each configured MCP server
4. WHEN a connection to an MCP server fails, THE McpClientManager SHALL report the failure via McpServerNotConnectedError and continue operating with remaining servers
5. THE McpClientManager SHALL support disconnecting from all servers gracefully on shutdown

### Requirement 26: MCP Tool Adapter

**User Story:** As a developer, I want MCP tools exposed as standard BaseTool instances, so that the engine can use MCP tools identically to built-in tools.

#### Acceptance Criteria

1. THE McpToolAdapter SHALL wrap an MCP server tool as a BaseTool instance with name, description, and input_schema derived from the MCP tool's JSON Schema
2. WHEN execute is called on an McpToolAdapter, THE McpToolAdapter SHALL forward the invocation to the MCP server and return the response as a ToolResult
3. THE McpToolAdapter SHALL dynamically generate input validation from the MCP tool's JSON Schema definition
4. IF the MCP server is not connected when execute is called, THEN THE McpToolAdapter SHALL return a ToolResult with is_error set to true

### Requirement 27: MCP Resource Access

**User Story:** As a developer, I want to access MCP resources by URI, so that the agent can read data exposed by MCP servers.

#### Acceptance Criteria

1. THE ReadMcpResourceTool SHALL accept a URI string and return the resource content as a ToolResult
2. WHEN the URI references a resource on a disconnected MCP server, THE ReadMcpResourceTool SHALL return a ToolResult with is_error set to true
3. THE McpClientManager SHALL provide a method to list all available resources across connected MCP servers

### Requirement 28: MCP Server Configuration

**User Story:** As a developer, I want to configure MCP servers via settings files, so that I can declaratively define which MCP servers the agent connects to.

#### Acceptance Criteria

1. THE McpServerConfig SHALL support stdio configuration with command, args, and env attributes
2. THE McpServerConfig SHALL support HTTP configuration with url and headers attributes
3. WHEN MCP server configuration is loaded from a settings file, THE McpClientManager SHALL initialize connections for each configured server
4. IF a configuration entry contains invalid or missing required fields, THEN THE McpClientManager SHALL log a warning and skip the invalid entry

### Requirement 29: Skill Definition and Registry

**User Story:** As a developer, I want a skill system that loads markdown-based skill definitions, so that the agent can access domain-specific knowledge on demand.

#### Acceptance Criteria

1. THE SkillDefinition SHALL carry name, description, and content (markdown string) attributes
2. THE SkillRegistry SHALL aggregate skills from three sources: bundled (gem-packaged), user (~/.openharness/skills/), and plugin-contributed
3. WHEN a skill markdown file contains YAML frontmatter, THE SkillRegistry SHALL parse name and description from the frontmatter
4. WHEN a skill markdown file lacks YAML frontmatter, THE SkillRegistry SHALL derive name from the H1 heading and description from the first paragraph
5. THE SkillRegistry SHALL provide a method to retrieve a skill by name, returning the SkillDefinition or raising SkillNotFoundError

### Requirement 30: Skill Tool

**User Story:** As a developer, I want a skill tool that loads skill content into the conversation on demand, so that skills are not included in the system prompt by default but available when needed.

#### Acceptance Criteria

1. WHEN the SkillTool is invoked with a skill name, THE SkillTool SHALL retrieve the skill from the SkillRegistry and return its content as a ToolResult
2. IF the requested skill name does not exist in the SkillRegistry, THEN THE SkillTool SHALL return a ToolResult with is_error set to true and a list of available skill names


### Requirement 31: Plugin System

**User Story:** As a developer, I want a plugin system that loads extensions from directories, so that third-party packages can contribute skills, commands, agents, hooks, and MCP servers.

#### Acceptance Criteria

1. THE PluginManifest SHALL be defined in a plugin.json file containing name, version, and contribution declarations (skills, commands, agents, hooks, mcp_servers)
2. THE plugin loader SHALL discover plugins from user directory (~/.openharness/plugins/) and project directory (./.openharness/plugins/)
3. WHEN a plugin directory contains a valid plugin.json, THE plugin loader SHALL create a LoadedPlugin instance and register all declared contributions
4. IF a plugin.json file is missing or contains invalid JSON, THEN THE plugin loader SHALL log a warning and skip the plugin directory
5. THE LoadedPlugin SHALL provide access to contributed SkillDefinitions, HookDefinitions, and McpServerConfigs

### Requirement 32: Memory System

**User Story:** As a developer, I want a cross-session memory system using structured markdown files, so that the agent retains knowledge across sessions.

#### Acceptance Criteria

1. THE memory system SHALL store memory files as markdown documents in a project-scoped directory returned by get_project_memory_dir
2. THE memory system SHALL maintain a MEMORY.md file as the central index listing all memory files
3. WHEN a memory file contains YAML frontmatter, THE memory system SHALL parse name, description, and type metadata into a MemoryHeader
4. THE scan_memory_files method SHALL return an array of MemoryHeader objects sorted by file modification time (most recent first)
5. THE find_relevant_memories method SHALL score memory files against a query using weighted matching (metadata weight 2x, body weight 1x) and return the top-scoring results

### Requirement 33: Memory Tokenization

**User Story:** As a developer, I want multi-language tokenization for memory search, so that memory relevance scoring works across ASCII and CJK text.

#### Acceptance Criteria

1. THE memory tokenizer SHALL split text on whitespace and punctuation boundaries for ASCII content
2. THE memory tokenizer SHALL segment Han ideograph sequences into individual characters for CJK content
3. THE memory tokenizer SHALL normalize tokens to lowercase before scoring

### Requirement 34: Memory Prompt Injection

**User Story:** As a developer, I want memory content injected into the system prompt, so that the agent has access to relevant memories at the start of each session.

#### Acceptance Criteria

1. WHEN load_memory_prompt is called, THE memory system SHALL scan memory files and return a formatted string containing the MEMORY.md index and relevant memory summaries
2. THE load_memory_prompt output SHALL be suitable for direct inclusion in the system prompt

### Requirement 35: Multi-Agent Team Registry

**User Story:** As a developer, I want a team registry for managing agent definitions, so that multiple agents can be coordinated for complex tasks.

#### Acceptance Criteria

1. THE TeamRegistry SHALL store AgentDefinition instances keyed by agent name
2. THE AgentDefinition SHALL carry name, role, capabilities (array of strings), and tool_access (array of tool names) attributes
3. WHEN an agent is registered with a name that already exists, THE TeamRegistry SHALL raise a DuplicateAgentError
4. THE TeamRegistry SHALL support listing all registered agents with their roles and capabilities

### Requirement 36: Multi-Agent Messaging

**User Story:** As a developer, I want mailbox-based messaging between agents, so that agents can communicate and coordinate work.

#### Acceptance Criteria

1. THE messaging system SHALL provide a send_message method that delivers a message from one agent to another by name
2. THE messaging system SHALL provide a receive_messages method that returns all pending messages for a given agent, clearing the mailbox
3. IF a message is sent to an unregistered agent name, THEN THE messaging system SHALL raise an AgentNotFoundError

### Requirement 37: Multi-Agent Permission Synchronization

**User Story:** As a developer, I want permission settings synchronized across agents in a team, so that all agents operate under consistent security policies.

#### Acceptance Criteria

1. WHEN a team is created, THE TeamRegistry SHALL propagate the parent PermissionChecker configuration to all child agents
2. WHEN the parent PermissionChecker configuration changes, THE TeamRegistry SHALL update all active child agents within 5 seconds

### Requirement 38: Session Storage

**User Story:** As a developer, I want session storage for conversation persistence, so that conversations can be saved and resumed.

#### Acceptance Criteria

1. THE session storage SHALL serialize a conversation (messages, cost tracker state, metadata) to a JSON file
2. THE session storage SHALL deserialize a conversation from a JSON file, restoring all messages and state
3. FOR ALL valid conversation states, serializing then deserializing SHALL produce an equivalent conversation state (round-trip property)
4. THE session storage SHALL store session files in a configurable directory, defaulting to ~/.openharness/sessions/

### Requirement 39: Settings Model

**User Story:** As a developer, I want a structured settings model, so that all configuration is validated and accessible through a consistent interface.

#### Acceptance Criteria

1. THE Settings model SHALL carry permission_settings (PermissionMode, denied_tools, allowed_tools, path_rules, denied_commands), provider_config (api_key, base_url, model), and runtime options (max_turns, context_window_threshold)
2. WHEN Settings is loaded from a YAML or JSON file, THE Settings model SHALL validate all fields and raise a ConfigurationError for invalid values
3. WHEN a settings field is not provided, THE Settings model SHALL use documented default values
4. FOR ALL valid Settings instances, serializing to Hash then deserializing back SHALL produce an equivalent Settings instance (round-trip property)

### Requirement 40: System Prompt Builder

**User Story:** As a developer, I want a system prompt builder that assembles context from multiple sources, so that the LLM receives a comprehensive prompt including tools, skills, memory, and project context.

#### Acceptance Criteria

1. THE SystemPromptBuilder SHALL compose the system prompt from: tool schemas (from ToolRegistry), active skills, memory prompt (from load_memory_prompt), and project context files
2. THE SystemPromptBuilder SHALL load project context from CLAUDE.md or .openharness/context.md files if present in the project root
3. WHEN no project context file exists, THE SystemPromptBuilder SHALL omit the project context section without error
4. THE SystemPromptBuilder SHALL return the assembled prompt as a single string

### Requirement 41: CLI Entry Point

**User Story:** As a developer, I want a CLI entry point for interactive use, so that I can run the agent from the terminal.

#### Acceptance Criteria

1. THE CLI SHALL provide an `openharness` command (aliased as `oh`) that starts an interactive session
2. THE CLI SHALL provide an `openharness setup` subcommand that guides the user through initial configuration (provider selection, API key entry)
3. THE CLI SHALL accept --provider, --model, --api-key, and --cwd flags to override settings for a single session
4. WHEN the CLI is started without a configured provider, THE CLI SHALL prompt the user to run setup

### Requirement 42: CLI Slash Commands

**User Story:** As a developer, I want slash commands in the interactive session, so that I can control the agent with quick commands.

#### Acceptance Criteria

1. THE CLI SHALL support the following slash commands: /help, /memory, /skill, /clear, /cost, /exit
2. WHEN /help is entered, THE CLI SHALL display a list of available slash commands with descriptions
3. WHEN /memory is entered, THE CLI SHALL display the current memory index
4. WHEN /skill is entered with a skill name argument, THE CLI SHALL load the specified skill into the conversation
5. WHEN /clear is entered, THE CLI SHALL reset the conversation history
6. WHEN /cost is entered, THE CLI SHALL display the current CostTracker summary
7. WHEN /exit is entered, THE CLI SHALL gracefully shut down the session

### Requirement 43: Input Validation Framework

**User Story:** As a developer, I want a consistent input validation framework for tool inputs, so that invalid inputs are caught before tool execution with clear error messages.

#### Acceptance Criteria

1. THE validation framework SHALL support defining input schemas using dry-types or an equivalent Ruby validation library
2. THE validation framework SHALL validate tool inputs against the defined schema before execute is called
3. WHEN validation fails, THE validation framework SHALL return a ToolResult with is_error set to true and a message listing all validation errors
4. THE validation framework SHALL support the following field types: String, Integer, Float, Boolean, Array, Hash, and optional/required modifiers

### Requirement 44: Retry Logic with Exponential Backoff

**User Story:** As a developer, I want standardized retry logic with exponential backoff and jitter, so that transient API failures are handled gracefully across all clients.

#### Acceptance Criteria

1. THE retry logic SHALL compute delay as: base_delay * (2 ^ attempt_number) + random_jitter, where random_jitter is between 0 and 1 second
2. THE retry logic SHALL respect a Retry-After header value from the API response when present, using it as the minimum delay
3. THE retry logic SHALL retry on HTTP status codes 429 (rate limit) and 5xx (server errors)
4. THE retry logic SHALL NOT retry on HTTP status codes 401 (authentication) or 400 (bad request)
5. WHEN max_retries is reached, THE retry logic SHALL raise the last encountered error

### Requirement 45: Agent Tool for Sub-Agent Spawning

**User Story:** As a developer, I want an agent tool that spawns sub-agents for delegated tasks, so that complex work can be broken into parallel agent executions.

#### Acceptance Criteria

1. WHEN the AgentTool is invoked with a task description and optional agent_name, THE AgentTool SHALL create a new QueryEngine instance with the specified or default agent configuration
2. THE AgentTool SHALL execute the sub-agent's query loop and return the final response as a ToolResult
3. THE AgentTool SHALL inherit the parent's PermissionChecker configuration for the sub-agent
4. IF the specified agent_name is not found in the TeamRegistry, THEN THE AgentTool SHALL return a ToolResult with is_error set to true

### Requirement 46: Web Search and Fetch Tools

**User Story:** As a developer, I want web search and fetch tools, so that the agent can retrieve information from the internet.

#### Acceptance Criteria

1. WHEN the WebSearchTool is invoked with a query string, THE WebSearchTool SHALL perform a web search and return results as a ToolResult containing titles, URLs, and snippets
2. WHEN the WebFetchTool is invoked with a URL, THE WebFetchTool SHALL fetch the page content and return it as a ToolResult
3. IF the URL is unreachable or returns a non-2xx status, THEN THE WebFetchTool SHALL return a ToolResult with is_error set to true and the HTTP status code

### Requirement 47: LSP Integration Tool

**User Story:** As a developer, I want an LSP integration tool, so that the agent can leverage language server features like go-to-definition and diagnostics.

#### Acceptance Criteria

1. WHEN the LspTool is invoked with an action (e.g., "diagnostics", "definition", "references") and file location, THE LspTool SHALL communicate with a running LSP server and return the results as a ToolResult
2. IF no LSP server is available for the requested language, THEN THE LspTool SHALL return a ToolResult with is_error set to true indicating no LSP server is configured

### Requirement 48: Notebook Edit Tool

**User Story:** As a developer, I want a notebook editing tool, so that the agent can read and modify Jupyter-style notebook files.

#### Acceptance Criteria

1. WHEN the NotebookEditTool is invoked with a notebook file path and cell index, THE NotebookEditTool SHALL read the specified cell content and return it as a ToolResult
2. WHEN the NotebookEditTool is invoked with a notebook file path, cell index, and new content, THE NotebookEditTool SHALL update the specified cell and write the modified notebook back to disk
3. IF the notebook file does not exist or the cell index is out of range, THEN THE NotebookEditTool SHALL return a ToolResult with is_error set to true

