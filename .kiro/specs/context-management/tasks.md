# Implementation Plan: Context Window Management

## Overview

Implement a context management system that monitors token usage against the model's context window limit and automatically triggers summarization and compaction strategies. The system integrates into the existing QueryEngine loop, is configured via Settings, and emits stream events when actions occur.

## Tasks

- [x] 1. Create the Context module with Strategy interface and Thresholds value object
  - [x] 1.1 Create `lib/openharness/rb/context/strategy.rb` with the Strategy module
    - Define `Openharness::Rb::Context::Strategy` module
    - Define `summarize(messages, **opts)` and `compact(messages, **opts)` methods that raise `NotImplementedError`
    - Include documentation comments describing the interface contract
    - _Requirements: 6.1, 6.2, 6.5_

  - [x] 1.2 Create `lib/openharness/rb/context/thresholds.rb` with the Thresholds value object
    - Define `Openharness::Rb::Context::Thresholds` class with `summarize_ratio` and `compact_ratio` attr_readers
    - Accept keyword arguments with defaults (summarize_ratio: 0.25, compact_ratio: 0.50)
    - Validate that summarize_ratio < compact_ratio; raise `ArgumentError` otherwise
    - Validate both ratios are within 0.0..1.0 inclusive; raise `ArgumentError` otherwise
    - _Requirements: 2.3, 2.4, 2.5, 2.6_

  - [ ]* 1.3 Write property test for Thresholds validation
    - **Property 2: Threshold validation**
    - **Validates: Requirements 2.3, 2.4, 2.5, 2.6**

- [x] 2. Implement the ContextManager class
  - [x] 2.1 Create `lib/openharness/rb/context/context_manager.rb` with ContextManager class
    - Define `Openharness::Rb::Context::ContextManager` class
    - Accept `context_window:`, `thresholds:`, and `strategy:` in constructor
    - Implement `check_and_manage!(chat, response)` that updates token count, computes ratio, and dispatches to strategy
    - Implement `usage_ratio` returning 0.0 when context_window is zero, otherwise cumulative_input_tokens / context_window
    - Implement `reset!` to set state to `:normal` and cumulative_input_tokens to 0
    - Implement `self.resolve_context_window(model)` class method using `RubyLLM.models.find(model)` with 100,000 fallback
    - Wrap strategy calls in begin/rescue to catch errors, log warning, and return `:none`
    - State transitions: `:normal` → `:summarized` → `:compacted` (monotonic, except on reset!)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 3.1, 4.1, 5.1, 5.2, 5.3, 5.4, 9.1, 9.2, 9.3, 9.4_

  - [ ]* 2.2 Write property test for usage ratio correctness
    - **Property 1: Usage ratio correctness**
    - **Validates: Requirements 1.1, 1.2**

  - [ ]* 2.3 Write property test for correct threshold-based dispatch
    - **Property 3: Correct threshold-based dispatch**
    - **Validates: Requirements 3.1, 4.1**

  - [ ]* 2.4 Write property test for monotonic state transitions
    - **Property 4: Monotonic state transitions**
    - **Validates: Requirements 5.1, 5.2, 5.3**

  - [ ]* 2.5 Write property test for reset restoring initial state
    - **Property 9: Reset restores initial state**
    - **Validates: Requirements 5.4**

  - [ ]* 2.6 Write property test for error resilience preserving conversation history
    - **Property 10: Error resilience preserves conversation history**
    - **Validates: Requirements 9.1, 9.2, 9.4**

- [x] 3. Checkpoint - Verify core module structure
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement the DefaultStrategy
  - [x] 4.1 Create `lib/openharness/rb/context/default_strategy.rb` with DefaultStrategy class
    - Define `Openharness::Rb::Context::DefaultStrategy` class that includes `Strategy`
    - Implement `summarize(messages, **opts)`: return unchanged if <= 4 messages; preserve system message, summarize older messages via LLM, keep last 4
    - Implement `compact(messages, **opts)`: return unchanged if <= 2 messages; preserve system message, ultra-compact summary via LLM, keep last 2
    - Implement private `generate_summary(messages, model)` and `generate_compact_summary(messages, model)` using `RubyLLM.chat`
    - Ensure no mutation of input messages array
    - _Requirements: 3.2, 3.3, 3.4, 3.5, 3.6, 4.2, 4.3, 4.4, 4.5, 4.6, 6.5_

  - [ ]* 4.2 Write property test for system prompt preservation
    - **Property 5: System prompt preservation**
    - **Validates: Requirements 3.2, 4.2**

  - [ ]* 4.3 Write property test for recent message preservation
    - **Property 6: Recent message preservation**
    - **Validates: Requirements 3.3, 4.3**

  - [ ]* 4.4 Write property test for idempotency on small conversations
    - **Property 7: Idempotency on small conversations**
    - **Validates: Requirements 3.6, 4.6**

  - [ ]* 4.5 Write property test for no mutation of input
    - **Property 8: No mutation of input**
    - **Validates: Requirements 6.5**

- [x] 5. Extend Settings and add stream events
  - [x] 5.1 Add `summarize_threshold`, `compact_threshold`, and `context_strategy` attributes to `Config::Settings`
    - Add `attribute :summarize_threshold, Types::Float.default(0.25)` to Settings
    - Add `attribute :compact_threshold, Types::Float.default(0.50)` to Settings
    - Add `attribute :context_strategy, Types::Any.optional.default(nil)` to Settings
    - _Requirements: 2.1, 2.2_

  - [x] 5.2 Add `ContextSummarized` and `ContextCompacted` stream event classes to `Models::StreamEvents`
    - Define `ContextSummarized < StreamEvent` with attributes: `usage_ratio` (Float), `messages_before` (Integer), `messages_after` (Integer)
    - Define `ContextCompacted < StreamEvent` with attributes: `usage_ratio` (Float), `messages_before` (Integer), `messages_after` (Integer)
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [x] 6. Checkpoint - Verify settings and events
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Integrate ContextManager into QueryEngine
  - [x] 7.1 Modify `Engine::QueryEngine#initialize` to create a ContextManager instance
    - Resolve context_window using `Context::ContextManager.resolve_context_window(@model)`
    - Build `Context::Thresholds` from settings' `summarize_threshold` and `compact_threshold`
    - Instantiate `Context::ContextManager` with resolved context_window, thresholds, and settings' `context_strategy` (or DefaultStrategy if nil)
    - Accept optional settings parameter or extract thresholds/strategy from initialization params
    - _Requirements: 8.1, 8.4_

  - [x] 7.2 Modify `Engine::QueryEngine#track_usage` to call `check_and_manage!` and emit context events
    - After recording cost, call `@context_manager.check_and_manage!(@chat, response)`
    - If action is `:summarized`, emit `Models::ContextSummarized` event via the stored event_handler
    - If action is `:compacted`, emit `Models::ContextCompacted` event via the stored event_handler
    - Include `usage_ratio`, `messages_before`, and `messages_after` in the events
    - _Requirements: 8.2, 8.3, 7.1, 7.2_

  - [x] 7.3 Modify `Engine::QueryEngine#clear!` to call `@context_manager.reset!`
    - Add `@context_manager.reset!` call after existing reset logic
    - _Requirements: 5.5_

  - [ ]* 7.4 Write unit tests for QueryEngine context management integration
    - Test that ContextManager is initialized with correct parameters
    - Test that `check_and_manage!` is called in `track_usage`
    - Test that context events are emitted correctly
    - Test that `clear!` resets the context manager
    - _Requirements: 8.1, 8.2, 8.3, 5.5_

- [x] 8. Wire up Harness and require files
  - [x] 8.1 Modify `lib/openharness/rb.rb` to require context module files
    - Add `require_relative "rb/context/strategy"`
    - Add `require_relative "rb/context/thresholds"`
    - Add `require_relative "rb/context/context_manager"`
    - Add `require_relative "rb/context/default_strategy"`
    - Place requires before the engine/query_engine require since QueryEngine depends on Context
    - _Requirements: 8.1_

  - [x] 8.2 Modify `Harness#build_query_engine` to pass new settings to QueryEngine
    - Pass `summarize_threshold`, `compact_threshold`, and `context_strategy` from settings to QueryEngine constructor (or ensure QueryEngine receives settings)
    - _Requirements: 8.4_

- [x] 9. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The `rantly` gem is used for property-based testing in Ruby
- All strategy methods must return new arrays without mutating input (Property 8)
- Error handling wraps strategy calls so failures never break the main conversation flow

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3", "2.1", "5.1", "5.2"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "2.5", "2.6", "4.1"] },
    { "id": 3, "tasks": ["4.2", "4.3", "4.4", "4.5", "7.1"] },
    { "id": 4, "tasks": ["7.2", "7.3", "8.1"] },
    { "id": 5, "tasks": ["7.4", "8.2"] }
  ]
}
```
