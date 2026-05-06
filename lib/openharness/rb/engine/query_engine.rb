# frozen_string_literal: true

require "ruby_llm"
require "json"
require "async"
require_relative "cost_tracker"
require_relative "system_prompt_builder"
require_relative "../errors"
require_relative "../models/stream_events"
require_relative "../api/retry_handler"

module Openharness
  module Rb
    module Engine
      # QueryEngine implements a ReAct (Reason → Act → Observe) agent loop.
      #
      # Permission enforcement:
      #   Each mutating tool (bash, write_to_file, edit_file, notebook_edit)
      #   includes PermissionGuard which checks Thread.current[:openharness_permission_checker]
      #   before executing. The QueryEngine sets this thread-local before each query.
      #   This way permission checks happen inside the tool's execute method,
      #   which is the only place we can actually block execution in RubyLLM.
      class QueryEngine
        include Api::RetryHandler

        attr_reader :cost_tracker, :chat, :turn_count, :max_turns

        REACT_SYSTEM_PROMPT = <<~PROMPT
          You are an autonomous agent that accomplishes tasks by reasoning step-by-step and using tools.

          For each task:
          1. THINK: Analyze what needs to be done. Break complex tasks into steps.
          2. ACT: Use the available tools to execute the current step.
          3. OBSERVE: Review the tool results carefully.
          4. REASON: Based on the results, decide:
             - If the step succeeded, move to the next step.
             - If something went wrong, diagnose the issue and try a different approach.
             - If the task is complete, provide your final answer.

          Important:
          - Always check tool results before proceeding. If a tool returns an error, address it.
          - If a tool returns a permission denied error, inform the user and do not retry that tool.
          - When the task is fully complete, respond with your final answer as plain text (no tool calls).
          - Be thorough but efficient. Don't repeat steps that already succeeded.
          - Check if any skills are matching for the task. If yes, use "skill" tool to load skills dynamically if it is not loaded.
        PROMPT

        CLASSIFIER_PROMPT = <<~PROMPT
          Given the task and its outcome decide whether its worth extracting memories.
          Always return either 0 or 1. Return 0 if the task is ephemeral/one-shot, return 1 if it contains useful lessons.

          Examples:
          - "List files in directory" → 0 (trivial, no lesson)
          - "Fix authentication bug by adding token refresh" → 1 (lesson learned)
          - "What time is it?" → 0 (ephemeral)
          - "Set up PostgreSQL with specific config after failed attempts" → 1 (mistake + fix)
        PROMPT

        MEMORY_EXTRACTION_PROMPT = <<~PROMPT
          Given this task and its outcome, extract memory items worth storing for future tasks.

          Respond ONLY with a JSON array (no markdown fences). Each element should have:
          - "name": short identifier (2-5 words, lowercase with hyphens)
          - "description": one-line summary
          - "type": one of "lesson", "mistake", "decision", "pattern"
          - "content": detailed explanation (1-3 paragraphs of markdown)

          If there is nothing worth remembering, respond with an empty array: []

          Rules:
          - Only extract genuinely useful insights, not trivial observations.
          - Focus on things that would help in future similar tasks.
          - Include specific details (file paths, commands, error messages) when relevant.
          - Do NOT include memories about the memory system itself.
        PROMPT

        def initialize(
          model:,
          tools: [],
          system_prompt: nil,
          system_prompt_builder: nil,
          provider_config: nil,
          max_turns: 10,
          permission_checker: nil,
          hook_executor: nil,
          memory_system: nil,
          session_storage: nil,
          input: $stdin,
          output: $stdout
        )
          configure_ruby_llm(provider_config) if provider_config

          @model = model
          @tools = tools
          @max_turns = max_turns
          @permission_checker = permission_checker
          @hook_executor = hook_executor
          @memory_system = memory_system
          @session_storage = session_storage
          @system_prompt_builder = system_prompt_builder
          @cost_tracker = CostTracker.new
          @turn_count = 0
          @input = input
          @output = output

          user_context = system_prompt || system_prompt_builder&.build
          @system_prompt = build_full_system_prompt(user_context)
          @chat = build_chat
        end

        def ask(message, &event_handler)
          begin
            # Rebuild system prompt with query-relevant memories
            if message && @system_prompt_builder
              user_context = @system_prompt_builder.build(query: message)
              @system_prompt = build_full_system_prompt(user_context)
              @chat = rebuild_chat_with_prompt
            end

            # Set thread-locals so PermissionGuard in tools can access them
            Thread.current[:openharness_permission_checker] = @permission_checker
            Thread.current[:openharness_input] = @input
            Thread.current[:openharness_output] = @output
            Thread.current[:openharness_event_handler] = event_handler

            @accumulated_text = String.new
            @tool_used_in_query = false

            # Record user message in session
            @session_storage&.record_user_message(message) if message

            response = execute_turn(message, event_handler)

            while used_tools_this_turn?
              @accumulated_text = String.new
              response = execute_turn(nil, event_handler)
            end

            # If no tools were used, the agent is asking for clarification
            unless @tool_used_in_query
              event_handler&.call(Models::ClarificationNeeded.new(
                question: @accumulated_text.strip
              ))
              
              follow_up = @input.gets
              message += follow_up

              response = execute_turn(message, event_handler)
            end

            # Record assistant response in session
            @session_storage&.record_assistant_message(@accumulated_text.strip) unless @accumulated_text.strip.empty?

            # Extract and save learnings from the completed task
            if @memory_system && @tool_used_in_query && @turn_count > 1
              extract_and_save_memories(message)
            end

            event_handler&.call(Models::AssistantTurnComplete.new(stop_reason: "end_turn"))
            response
          ensure
            # Clean up thread-locals
            Thread.current[:openharness_permission_checker] = nil
            Thread.current[:openharness_input] = nil
            Thread.current[:openharness_output] = nil
            Thread.current[:openharness_event_handler] = nil
          end
        end

        def clear!
          @chat = build_chat
          @turn_count = 0
          @tool_called_this_turn = false
          @tool_used_in_query = false
        end

        def add_tool(tool)
          @tools << tool
          @chat.with_tool(tool)
        end

        private

        def execute_turn(message, event_handler)
          @turn_count += 1
          if @turn_count > @max_turns
            event_handler&.call(Models::ErrorOccurred.new(
              error: MaxTurnsExceeded.new("Exceeded max turns (#{@max_turns})")
            ))
            raise MaxTurnsExceeded, "Exceeded max turns (#{@max_turns})"
          end

          event_handler&.call(Models::TurnStarted.new(
            turn_number: @turn_count,
            max_turns: @max_turns
          ))

          @tool_called_this_turn = false
          setup_callbacks(event_handler)

          response = with_retry do
            prompt = message || "Review the results above. If the task is complete, provide your final answer. Otherwise, continue with the next step."
            @chat.ask(prompt) do |chunk|
              emit_text_delta(chunk, event_handler)
            end
          end

          @tool_used_in_query = true if @tool_called_this_turn
          track_usage(response)
          response
        end

        def used_tools_this_turn?
          @tool_called_this_turn
        end

        def emit_text_delta(chunk, event_handler)
          return unless chunk.content
          @accumulated_text << chunk.content if @accumulated_text
          event_handler&.call(Models::AssistantTextDelta.new(text: chunk.content))
        end

        def setup_callbacks(event_handler)
          @chat.on_tool_call do |tool_call|
            @tool_called_this_turn = true

            # Record tool call in session
            @session_storage&.record_tool_call(
              tool_name: tool_call.name.to_s,
              tool_use_id: tool_call.id.to_s,
              arguments: tool_call.arguments
            )

            # Pre-tool hook
            dispatch_hook(Hooks::HookEvent::PRE_TOOL_USE, tool_call, event_handler)

            event_handler&.call(Models::ToolExecutionStarted.new(
              tool_name: tool_call.name.to_s,
              tool_use_id: tool_call.id.to_s
            ))
          end

          @chat.on_tool_result do |result|
            # Record tool result in session
            @session_storage&.record_tool_result(
              tool_use_id: "latest",
              result: result.to_s
            )

            if @hook_executor
              @hook_executor.dispatch(
                Hooks::HookEvent::POST_TOOL_USE,
                payload: { result: result.to_s }
              )
            end

            event_handler&.call(Models::ToolExecutionCompleted.new(
              tool_use_id: "latest",
              result: Models::ToolResult.new(text: result.to_s)
            ))
          end
        end

        def dispatch_hook(event, tool_call, event_handler)
          return unless @hook_executor

          result = @hook_executor.dispatch(
            event,
            payload: { tool_name: tool_call.name.to_s, arguments: tool_call.arguments },
            context_name: tool_call.name.to_s
          )

          return if result[:ok]

          event_handler&.call(Models::ErrorOccurred.new(
            error: "Hook failed for '#{tool_call.name}': #{result[:failures]&.map { |f| f[:error] }&.join(', ')}"
          ))
        end

        def track_usage(response)
          return unless response&.respond_to?(:input_tokens) && response.input_tokens

          @cost_tracker.record(
            input_tokens: response.input_tokens || 0,
            output_tokens: response.output_tokens || 0,
            cost: 0.0
          )
        end

        def build_chat
          chat = RubyLLM.chat(model: @model)
          chat.with_instructions(@system_prompt) if @system_prompt
          chat.with_tools(*@tools) unless @tools.empty?
          chat
        end

        # Rebuild the chat with an updated system prompt while preserving
        # the existing conversation history and tool bindings.
        def rebuild_chat_with_prompt
          @chat.with_instructions(@system_prompt) if @system_prompt
          @chat
        end

        def extract_and_save_memories(original_query)
          Async do
            begin
              # Build a summary of what happened in this task
              summary = "Original task: #{original_query}\n" \
                        "Turns used: #{@turn_count}/#{@max_turns}\n" \
                        "Tools were called during this task."

              # Step 1: Classify whether this task is worth remembering
              classifier = RubyLLM.chat(model: @model)
              classifier.with_instructions("You are a classifier. You decide whether we should extract memories from a given task. Respond with only 0 or 1.")
              classify_response = classifier.ask("#{summary}\n\n#{CLASSIFIER_PROMPT}")

              return unless classify_response&.content&.strip == "1"

              # Step 2: Extract structured memories
              extraction_chat = RubyLLM.chat(model: @model)
              extraction_chat.with_instructions("You extract structured learnings from agent conversations.")

              response = extraction_chat.ask("#{summary}\n\n#{MEMORY_EXTRACTION_PROMPT}")
              return unless response&.content

              parse_and_save_memories(response.content)
            rescue StandardError => e
              # Memory extraction is best-effort — never break the main flow
              @output.puts "\e[2m⚠ Memory extraction failed: #{e.message}\e[0m"
            end
          end
        end

        def parse_and_save_memories(raw_json)
          # Strip markdown code fences if present
          json_str = raw_json.strip
          json_str = json_str.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")

          memories = JSON.parse(json_str)
          return unless memories.is_a?(Array) && !memories.empty?

          memories.each do |mem|
            next unless mem["name"] && mem["content"]

            header = @memory_system.save_memory(
              name: mem["name"],
              description: mem["description"] || "",
              content: mem["content"],
              type: mem["type"]
            )
          end
        rescue JSON::ParserError
          # LLM didn't return valid JSON — skip silently
          nil
        end

        def build_full_system_prompt(user_context)
          parts = [REACT_SYSTEM_PROMPT]
          parts << user_context if user_context && !user_context.strip.empty?
          parts.join("\n\n")
        end

        def configure_ruby_llm(config)
          RubyLLM.configure do |c|
            c.openai_api_key = config[:openai_api_key] if config[:openai_api_key]
            c.anthropic_api_key = config[:anthropic_api_key] if config[:anthropic_api_key]
            c.gemini_api_key = config[:gemini_api_key] if config[:gemini_api_key]
            c.openrouter_api_key = config[:openrouter_api_key] if config[:openrouter_api_key]
          end
        end
      end
    end
  end
end
