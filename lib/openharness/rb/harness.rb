# frozen_string_literal: true

module Openharness
  module Rb
    class Harness
      attr_reader :settings, :api_adapter, :tools, :permission_checker, :hook_executor

      def initialize(settings: nil, **overrides)
        @settings = settings || Config::Settings.new(**overrides)
        @api_adapter = build_api_adapter
        @tools = default_tools
        @permission_checker = build_permission_checker
        @hook_executor = build_hook_executor
      end

      # Run a query with all registered tools.
      # Yields StreamEvent instances for real-time UI updates.
      # Returns the final RubyLLM::Message.
      def query(message, &event_handler)
        ENV["OPENHARNESS_CWD"] = @settings.respond_to?(:cwd) ? @settings.cwd : Dir.pwd
        @api_adapter.ask(message, tools: @tools, &event_handler)
      end

      # Add a RubyLLM::Tool class or instance to the tool list.
      def add_tool(tool)
        @tools << tool
      end

      # Replace all tools.
      def set_tools(*tool_list)
        @tools = tool_list.flatten
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
    end
  end
end
