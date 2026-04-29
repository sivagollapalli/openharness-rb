# frozen_string_literal: true

module Openharness
  module Rb
    class Harness
      attr_reader :settings, :query_engine, :permission_checker, :hook_executor,
                  :mcp_manager, :skill_registry, :memory, :session

      def initialize(settings: nil, input: $stdin, output: $stdout, resume_from: nil, **overrides)
        @settings = settings || Config::Settings.new(**overrides)
        @input = input
        @output = output
        @permission_checker = build_permission_checker
        @hook_executor = build_hook_executor
        @mcp_manager = build_mcp_manager
        @skill_registry = build_skill_registry
        @memory = build_memory_system
        @session = build_session_storage
        @query_engine = build_query_engine
        replay_session(resume_from) if resume_from
        print_loaded_skills
      end

      def query(message, &event_handler)
        ENV["OPENHARNESS_CWD"] ||= Dir.pwd
        @query_engine.ask(message, &event_handler)
      end

      def add_tool(tool)
        @query_engine.add_tool(tool)
      end

      # Connect an MCP server at runtime and add its tools to the engine.
      def add_mcp_server(config)
        client = @mcp_manager.connect(config)
        return unless client

        client.tools.each { |t| @query_engine.add_tool(t) }
        client
      end

      # Add a skill at runtime.
      def add_skill(name:, description:, content:)
        skill = Skills::SkillDefinition.new(name: name, description: description, content: content)
        @skill_registry.instance_variable_get(:@skills)[name] = skill
        skill
      end

      def clear!
        @query_engine.clear!
      end

      def cost_tracker
        @query_engine.cost_tracker
      end

      def session_id
        @session.session_id
      end

      # Export the current conversation to a JSON file.
      # Returns the file path.
      def export_session
        @session.export(
          cost_summary: cost_tracker.summary,
          metadata: { model: @settings.model }
        )
      end

      private

      def build_query_engine
        all_tools = default_tools + mcp_tools
        Engine::QueryEngine.new(
          model: @settings.model,
          tools: all_tools,
          system_prompt_builder: build_system_prompt_builder,
          provider_config: build_provider_config,
          max_turns: @settings.max_turns,
          permission_checker: @permission_checker,
          hook_executor: @hook_executor,
          memory_system: @memory,
          session_storage: @session,
          input: @input,
          output: @output
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
        Engine::SystemPromptBuilder.new(
          skill_registry: @skill_registry,
          memory_system: @memory,
          project_root: Dir.pwd
        )
      end

      def build_skill_registry
        registry = Skills::SkillRegistry.new
        registry.load_all
        registry
      end

      def default_tools
        tools = [
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

        # Add SkillTool with the loaded registry so the LLM can load skills on demand
        tools << Tools::Builtin::SkillTool.new(@skill_registry)

        tools
      end

      # Connect MCP servers from settings and collect their tools.
      def mcp_tools
        return [] if @settings.mcp_servers.empty?

        @mcp_manager.connect_all(@settings.mcp_servers)
        @mcp_manager.tools
      rescue StandardError => e
        warn "Failed to load MCP tools: #{e.message}"
        []
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

      def build_mcp_manager
        Mcp::McpClientManager.new
      end

      def build_memory_system
        Memory::MemorySystem.new
      end

      def build_session_storage
        Session::SessionStorage.new
      end

      # Replay a previous session's conversation into the current chat
      # so the LLM has the full context from the prior session.
      def replay_session(file_path)
        data = Session::SessionStorage.load(file_path)
        @output.puts "\e[2m📂 Resuming session #{data[:session_id]} (#{data[:conversation].length} messages)\e[0m"

        data[:conversation].each do |entry|
          role = entry[:role]
          case role
          when "user"
            @query_engine.chat.ask(entry[:content]) { |_| } # replay silently
          end
        end
      rescue StandardError => e
        @output.puts "\e[31m⚠ Failed to resume session: #{e.message}\e[0m"
      end

      def print_loaded_skills
        entries = @skill_registry.catalog_entries
        if entries.empty?
          @output.puts "\e[2m📚 No skills available\e[0m"
        else
          @output.puts "\e[2m📚 Skills available (#{entries.length}):\e[0m"
          entries.each do |e|
            @output.puts "\e[2m   • #{e[:name]} — #{e[:description]}\e[0m"
          end
        end
      end
    end
  end
end
