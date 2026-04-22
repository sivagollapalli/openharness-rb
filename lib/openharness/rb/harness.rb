# frozen_string_literal: true

module Openharness
  module Rb
    class Harness
      attr_reader :settings, :query_engine, :permission_checker, :hook_executor

      def initialize(settings: nil, **overrides)
        @settings = settings || Config::Settings.new(**overrides)
        @permission_checker = build_permission_checker
        @hook_executor = build_hook_executor
        @query_engine = build_query_engine
      end

      # Ask a question. Streams events via block.
      # Returns the final RubyLLM::Message.
      def query(message, &event_handler)
        ENV["OPENHARNESS_CWD"] ||= Dir.pwd
        @query_engine.ask(message, &event_handler)
      end

      # Add a RubyLLM::Tool class or instance at runtime.
      def add_tool(tool)
        @query_engine.add_tool(tool)
      end

      # Reset conversation history.
      def clear!
        @query_engine.clear!
      end

      # Cost tracker from the engine.
      def cost_tracker
        @query_engine.cost_tracker
      end

      private

      def build_query_engine
        Engine::QueryEngine.new(
          model: @settings.model,
          tools: default_tools,
          system_prompt_builder: build_system_prompt_builder,
          provider_config: build_provider_config,
          max_turns: @settings.max_turns,
          permission_checker: @permission_checker,
          hook_executor: @hook_executor
        )
      end

      def build_provider_config
        return nil unless @settings.api_key

        {
          openai_api_key: @settings.api_key,
          anthropic_api_key: @settings.api_key,
          gemini_api_key: @settings.api_key,
          openrouter_api_key: @settings.api_key
        }
      end

      def build_system_prompt_builder
        memory = Memory::MemorySystem.new(  )

        Engine::SystemPromptBuilder.new(
          skill_registry: nil,
          memory_system: memory,
          project_root: Dir.pwd
        )
      end

      def default_tools
        [
          Tools::Builtin::ReadFileTool,
          Tools::Builtin::WriteToFileTool,
          Tools::Builtin::EditFileTool,
          Tools::Builtin::GrepTool,
          Tools::Builtin::GlobTool,
          Tools::Builtin::BashTool,
          Tools::Builtin::WebFetchTool,
          Tools::Builtin::WebSearchTool,
          Tools::Builtin::AgentTool,
          Tools::Builtin::LspTool,
          Tools::Builtin::NotebookEditTool,
        ]
      end

      def build_permission_checker
        Permissions::PermissionChecker.new(
          mode: @settings.permission_mode,
          denied_tools: @settings.denied_tools,
          allowed_tools: @settings.allowed_tools,
          path_rules: @settings.path_rules.map { |r|
            r.is_a?(Permissions::PathRule) ? r : Permissions::PathRule.new(**r)
          },
          denied_commands: @settings.denied_commands
        )
      end

      def build_hook_executor
        registry = Hooks::HookRegistry.new
        Hooks::HookExecutor.new(registry: registry)
      end
    end
  end
end
