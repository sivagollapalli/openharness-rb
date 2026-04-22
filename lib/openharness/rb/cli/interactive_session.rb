# frozen_string_literal: true

module Openharness
  module Rb
    module Cli
      class InteractiveSession
        SLASH_COMMANDS = {
          "/help" => :cmd_help,
          "/memory" => :cmd_memory,
          "/skill" => :cmd_skill,
          "/clear" => :cmd_clear,
          "/cost" => :cmd_cost,
          "/exit" => :cmd_exit
        }.freeze

        def initialize(settings:, input: $stdin, output: $stdout)
          @settings = settings
          @input = input
          @output = output
          @harness = Harness.new(settings: settings)
          @cost_tracker = @harness.query_engine.cost_tracker
          register_builtin_tools
        end

        def run
          @output.puts "OpenHarness interactive session. Type /help for commands."
          catch(:exit) do
            loop do
              @output.print "> "
              line = @input.gets
              break if line.nil?

              input = line.chomp.strip
              next if input.empty?

              if input.start_with?("/")
                handle_slash_command(input)
              else
                process_query(input)
              end
            end
          end
          @output.puts "Goodbye!"
        end

        def handle_slash_command(input)
          cmd, *args = input.split(" ")
          method = SLASH_COMMANDS[cmd]
          if method
            send(method, *args)
          else
            @output.puts "Unknown command: #{cmd}. Type /help for available commands."
          end
        end

        private

        def cmd_help(*)
          @output.puts "Available commands:"
          @output.puts "  /help    - Show this help message"
          @output.puts "  /memory  - Display memory index"
          @output.puts "  /skill   - Load a skill (usage: /skill <name>)"
          @output.puts "  /clear   - Clear conversation history"
          @output.puts "  /cost    - Show token usage and cost"
          @output.puts "  /exit    - Exit the session"
        end

        def cmd_memory(*)
          @output.puts "Memory index: (no memories loaded)"
        end

        def cmd_skill(*args)
          if args.empty?
            @output.puts "Usage: /skill <name>"
          else
            @output.puts "Skill '#{args.first}' requested."
          end
        end

        def cmd_clear(*)
          @harness.query_engine.messages.clear
          @output.puts "Conversation history cleared."
        end

        def cmd_cost(*)
          summary = @cost_tracker.summary
          @output.puts "Tokens — input: #{summary[:input_tokens]}, output: #{summary[:output_tokens]}"
          @output.puts "Total cost: $#{'%.4f' % summary[:total_cost]}"
        end

        def cmd_exit(*)
          throw :exit
        end

        def process_query(message)
          @harness.query(message) do |event|
            case event
            when Models::AssistantTextDelta
              @output.print event.text
            when Models::ToolExecutionStarted
              @output.puts "\n[Executing #{event.tool_name}...]"
            when Models::ToolExecutionCompleted
              if event.result.is_error
                @output.puts "[Tool error: #{event.result.text}]"
              else
                @output.puts "[Tool result: #{event.result.text[0..200]}]"
              end
            when Models::AssistantTurnComplete
              @output.puts ""
            end
          end
        rescue MaxTurnsExceeded
          @output.puts "\n[Max turns exceeded]"
        rescue StandardError => e
          @output.puts "\n[Error: #{e.message}]"
        end

        def register_builtin_tools
          registry = @harness.tool_registry
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
        end
      end
    end
  end
end
