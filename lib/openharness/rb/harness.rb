# frozen_string_literal: true

module Openharness
  module Rb
    class Harness
      attr_reader :settings, :api_adapter, :tool_registry, :permission_checker,
                  :hook_executor, :query_engine

      def initialize(settings: nil, **overrides)
        @settings = settings || Config::Settings.new(**overrides)
        @api_adapter = build_api_adapter
        @tool_registry = build_tool_registry
        @permission_checker = build_permission_checker
        @hook_executor = build_hook_executor
        @query_engine = build_query_engine
      end

      def query(message, &event_handler)
        @query_engine.run_query(message, &event_handler)
      end

      private

      def build_api_adapter
        provider_config = {}
        if @settings.api_key
          provider_config[:openai_api_key] = @settings.api_key
          provider_config[:anthropic_api_key] = @settings.api_key
          provider_config[:gemini_api_key] = @settings.api_key
        end
        Api::LlmAdapter.new(
          model: @settings.model,
          provider_config: provider_config.empty? ? nil : provider_config
        )
      end

      def build_tool_registry
        registry = Tools::ToolRegistry.new
        registry.register(Tools::Builtin::ReadFileTool.new)
        registry.register(Tools::Builtin::WriteToFileTool.new)
        registry.register(Tools::Builtin::EditFileTool.new)
        registry.register(Tools::Builtin::GrepTool.new)
        registry.register(Tools::Builtin::GlobTool.new)
        registry.register(Tools::Builtin::BashTool.new)
        registry.register(Tools::Builtin::WebFetchTool.new)
        registry.register(Tools::Builtin::WebSearchTool.new)
        registry.register(Tools::Builtin::AgentTool.new)
        registry.register(Tools::Builtin::LspTool.new)
        registry.register(Tools::Builtin::NotebookEditTool.new)

        registry
      end

      def build_permission_checker
        Permissions::PermissionChecker.new(
          mode: @settings.permission_mode.to_s,
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
        Hooks::HookExecutor.new(registry: registry, llm_adapter: @api_adapter)
      end

      def build_query_engine
        context = Models::QueryContext.new(
          max_turns: @settings.max_turns
        )
        Engine::QueryEngine.new(
          api_adapter: @api_adapter,
          tool_registry: @tool_registry,
          permission_checker: @permission_checker,
          context: context
        )
      end
    end
  end
end
