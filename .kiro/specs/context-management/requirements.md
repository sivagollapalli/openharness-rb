# Requirements Document

## Introduction

Context Window Management provides automatic summarization and compaction of conversation history for the openharness-rb Ruby agent harness. The system monitors token usage against the model's context window limit and triggers configurable strategies to keep conversations within bounds, ensuring long-running sessions remain functional without manual intervention.

## Glossary

- **ContextManager**: The coordinator class that monitors token usage ratios and delegates to strategies when thresholds are crossed.
- **Strategy**: A pluggable module interface defining `summarize` and `compact` methods for conversation history reduction.
- **DefaultStrategy**: The built-in Strategy implementation that uses LLM calls to generate summaries.
- **Thresholds**: A value object holding the two configurable ratios (summarize_ratio and compact_ratio) that determine when actions trigger.
- **QueryEngine**: The ReAct agent loop that processes user queries, manages tool calls, and integrates with the ContextManager.
- **Settings**: The application configuration object (Dry::Struct) that holds user-configurable parameters.
- **context_window**: The maximum number of tokens a model can process in a single request, resolved from the RubyLLM model registry.
- **usage_ratio**: The fraction of the context window consumed, computed as cumulative_input_tokens / context_window.
- **summarize_threshold**: The usage_ratio at which older messages are summarized (default 0.25).
- **compact_threshold**: The usage_ratio at which messages are compacted aggressively (default 0.50).
- **stream_event**: A typed event emitted to the event handler callback during query execution.

## Requirements

### Requirement 1: Token Usage Monitoring

**User Story:** As a developer using openharness-rb, I want the system to monitor token usage against the model's context window limit, so that I am aware of how much context capacity is consumed.

#### Acceptance Criteria

1. WHEN a response is received from the LLM, THE ContextManager SHALL update the cumulative input token count from the response's `input_tokens` field.
2. THE ContextManager SHALL compute the usage_ratio as the cumulative_input_tokens divided by the context_window size.
3. IF the context_window is zero, THEN THE ContextManager SHALL return a usage_ratio of 0.0 to avoid division by zero.
4. THE ContextManager SHALL resolve the context_window size from `RubyLLM.models.find(model).context_window` for the configured model.
5. IF the model is not found in the RubyLLM registry, THEN THE ContextManager SHALL fall back to a default context window of 100,000 tokens.

---

### Requirement 2: Threshold Configuration

**User Story:** As a developer, I want to configure the summarize and compact thresholds, so that I can tune context management behavior to my use case.

#### Acceptance Criteria

1. THE Settings SHALL expose a `summarize_threshold` attribute with a default value of 0.25.
2. THE Settings SHALL expose a `compact_threshold` attribute with a default value of 0.50.
3. WHEN creating Thresholds, THE Thresholds SHALL validate that summarize_ratio is strictly less than compact_ratio.
4. WHEN creating Thresholds, THE Thresholds SHALL validate that both ratios are within the range 0.0 to 1.0 inclusive.
5. IF summarize_ratio is greater than or equal to compact_ratio, THEN THE Thresholds SHALL raise an ArgumentError at construction time.
6. IF either ratio is outside the range 0.0 to 1.0, THEN THE Thresholds SHALL raise an ArgumentError at construction time.

---

### Requirement 3: Automatic Summarization

**User Story:** As a developer, I want the system to automatically summarize older messages when usage reaches the summarize threshold, so that the conversation can continue without exceeding context limits.

#### Acceptance Criteria

1. WHEN the usage_ratio reaches or exceeds the summarize_threshold AND the state is `:normal`, THE ContextManager SHALL invoke the Strategy's `summarize` method with the current conversation messages.
2. WHEN summarization is performed, THE DefaultStrategy SHALL preserve the system message (if present) as the first element in the output.
3. WHEN summarization is performed, THE DefaultStrategy SHALL preserve the most recent 4 messages unchanged in the output.
4. WHEN summarization is performed, THE DefaultStrategy SHALL generate an LLM-based summary of older messages (those between the system message and the recent 4).
5. WHEN summarization is performed, THE DefaultStrategy SHALL include the summary as a system-role message with content prefixed by "[Conversation Summary]".
6. IF the conversation has 4 or fewer messages, THEN THE DefaultStrategy SHALL return the messages unchanged without summarization.

---

### Requirement 4: Automatic Compaction

**User Story:** As a developer, I want the system to aggressively compact messages when usage reaches the compact threshold, so that even very long sessions can continue operating.

#### Acceptance Criteria

1. WHEN the usage_ratio reaches or exceeds the compact_threshold, THE ContextManager SHALL invoke the Strategy's `compact` method with the current conversation messages.
2. WHEN compaction is performed, THE DefaultStrategy SHALL preserve the system message (if present) as the first element in the output.
3. WHEN compaction is performed, THE DefaultStrategy SHALL preserve the most recent 2 messages unchanged in the output.
4. WHEN compaction is performed, THE DefaultStrategy SHALL generate an ultra-compact LLM-based summary (2-3 sentences) of all other messages.
5. WHEN compaction is performed, THE DefaultStrategy SHALL include the compact summary as a system-role message with content prefixed by "[Compacted Context]".
6. IF the conversation has 2 or fewer messages, THEN THE DefaultStrategy SHALL return the messages unchanged without compaction.

---

### Requirement 5: Monotonic State Transitions

**User Story:** As a developer, I want the context management state to progress in a predictable one-way direction, so that I can reason about the system's behavior.

#### Acceptance Criteria

1. THE ContextManager SHALL transition state only in the order: `:normal` → `:summarized` → `:compacted`.
2. WHILE the state is `:summarized`, THE ContextManager SHALL only transition to `:compacted` (not back to `:normal` or re-trigger summarization).
3. WHILE the state is `:compacted`, THE ContextManager SHALL remain in `:compacted` state unless explicitly reset.
4. WHEN `reset!` is called, THE ContextManager SHALL return the state to `:normal` and reset the cumulative token count to zero.
5. WHEN `QueryEngine#clear!` is called, THE ContextManager SHALL have its state reset via `reset!`.

---

### Requirement 6: Pluggable Strategy Interface

**User Story:** As a developer, I want to provide custom summarization and compaction logic, so that I can tailor context management to my specific needs.

#### Acceptance Criteria

1. THE Strategy module SHALL define a `summarize` method accepting messages and keyword options.
2. THE Strategy module SHALL define a `compact` method accepting messages and keyword options.
3. WHEN a custom Strategy is provided via Settings, THE ContextManager SHALL use it instead of the DefaultStrategy.
4. WHEN invoking Strategy methods, THE ContextManager SHALL pass the model identifier, context_window size, and current token count as keyword options.
5. THE Strategy methods SHALL return a new Array of message Hashes without mutating the input messages array.

---

### Requirement 7: Stream Event Emission

**User Story:** As a developer, I want to receive stream events when context management actions occur, so that I can display status information or log context management activity.

#### Acceptance Criteria

1. WHEN summarization is performed, THE QueryEngine SHALL emit a `ContextSummarized` stream event with the usage_ratio, messages_before count, and messages_after count.
2. WHEN compaction is performed, THE QueryEngine SHALL emit a `ContextCompacted` stream event with the usage_ratio, messages_before count, and messages_after count.
3. THE `ContextSummarized` event SHALL include attributes: `usage_ratio` (Float), `messages_before` (Integer), and `messages_after` (Integer).
4. THE `ContextCompacted` event SHALL include attributes: `usage_ratio` (Float), `messages_before` (Integer), and `messages_after` (Integer).

---

### Requirement 8: QueryEngine Integration

**User Story:** As a developer, I want context management to happen automatically within the existing query flow, so that I do not need to manually manage context.

#### Acceptance Criteria

1. WHEN the QueryEngine is initialized, THE QueryEngine SHALL resolve the model's context window and create a ContextManager instance.
2. WHEN a response is received and tracked, THE QueryEngine SHALL call `ContextManager#check_and_manage!` with the chat and response objects.
3. WHEN `check_and_manage!` returns `:summarized` or `:compacted`, THE QueryEngine SHALL emit the corresponding stream event.
4. THE QueryEngine SHALL pass Settings-configured thresholds and strategy to the ContextManager at initialization.

---

### Requirement 9: Error Resilience

**User Story:** As a developer, I want the context management system to handle errors gracefully, so that strategy failures do not break the main conversation flow.

#### Acceptance Criteria

1. IF the Strategy's `summarize` method raises an error, THEN THE ContextManager SHALL catch the error, log a warning, and return `:none` without modifying the conversation history.
2. IF the Strategy's `compact` method raises an error, THEN THE ContextManager SHALL catch the error, log a warning, and return `:none` without modifying the conversation history.
3. IF the chat messages are inaccessible or nil, THEN THE ContextManager SHALL return `:none` and log a warning.
4. WHEN a strategy error occurs, THE ContextManager SHALL preserve the conversation history in its pre-action state.
