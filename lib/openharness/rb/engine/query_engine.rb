# frozen_string_literal: true

require "ruby_llm"
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

        def initialize(
          model:,
          tools: [],
          system_prompt: nil,
          system_prompt_builder: nil,
          provider_config: nil,
          max_turns: 10,
          permission_checker: nil,
          hook_executor: nil,
          input: $stdin,
          output: $stdout
        )
          configure_ruby_llm(provider_config) if provider_config

          @model = model
          @tools = tools
          @max_turns = max_turns
          @permission_checker = permission_checker
          @hook_executor = hook_executor
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
            # Set thread-locals so PermissionGuard in tools can access them
            Thread.current[:openharness_permission_checker] = @permission_checker
            Thread.current[:openharness_input] = @input
            Thread.current[:openharness_output] = @output
            Thread.current[:openharness_event_handler] = event_handler

            response = execute_turn(message, event_handler)

            while used_tools_this_turn?
              response = execute_turn(nil, event_handler)
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

          track_usage(response)
          response
        end

        def used_tools_this_turn?
          @tool_called_this_turn
        end

        def emit_text_delta(chunk, event_handler)
          return unless chunk.content
          event_handler&.call(Models::AssistantTextDelta.new(text: chunk.content))
        end

        def setup_callbacks(event_handler)
          @chat.on_tool_call do |tool_call|
            @tool_called_this_turn = true

            # Pre-tool hook
            dispatch_hook(Hooks::HookEvent::PRE_TOOL_USE, tool_call, event_handler)

            event_handler&.call(Models::ToolExecutionStarted.new(
              tool_name: tool_call.name.to_s,
              tool_use_id: tool_call.id.to_s
            ))
          end

          @chat.on_tool_result do |result|
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
