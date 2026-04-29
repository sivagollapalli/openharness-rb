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
          "/export" => :cmd_export,
          "/exit" => :cmd_exit
        }.freeze

        # ANSI color codes for terminal output
        DIM = "\e[2m"
        CYAN = "\e[36m"
        YELLOW = "\e[33m"
        GREEN = "\e[32m"
        RED = "\e[31m"
        BOLD = "\e[1m"
        RESET = "\e[0m"

        def initialize(settings:, input: $stdin, output: $stdout, resume_from: nil)
          @settings = settings
          @input = input
          @output = output
          @harness = Harness.new(settings: settings, resume_from: resume_from)
        end

        def run
          @output.puts "#{BOLD}OpenHarness#{RESET} interactive session. Type /help for commands."
          @output.puts "#{DIM}Session: #{@harness.session_id}#{RESET}\n\n"
          catch(:exit) do
            loop do
              @output.print "#{GREEN}> #{RESET}"
              @output.flush
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
          path = @harness.export_session
          @output.puts "#{DIM}Session saved to #{path}#{RESET}"
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
          @output.puts "  /export  - Export conversation to session file"
          @output.puts "  /exit    - Exit the session"
        end

        def cmd_memory(*)
          prompt = @harness.memory.load_memory_prompt
          @output.puts prompt
        end

        def cmd_skill(*args)
          if args.empty?
            entries = @harness.skill_registry.catalog_entries
            if entries.empty?
              @output.puts "No skills available."
            else
              @output.puts "Available skills:"
              entries.each { |e| @output.puts "  #{e[:name]} — #{e[:description]}" }
            end
          else
            begin
              skill = @harness.skill_registry.get(args.first)
              @output.puts "#{CYAN}📖 #{skill.name}#{RESET}: #{skill.description}"
              @output.puts skill.content
            rescue Openharness::Rb::SkillNotFoundError => e
              @output.puts "#{RED}#{e.message}#{RESET}"
            end
          end
        end

        def cmd_clear(*)
          @harness.clear!
          @output.puts "Conversation history cleared."
        end

        def cmd_cost(*)
          summary = @harness.cost_tracker.summary
          @output.puts "Tokens — input: #{summary[:input_tokens]}, output: #{summary[:output_tokens]}"
          @output.puts "Total cost: $#{'%.4f' % summary[:total_cost]}"
        end

        def cmd_export(*)
          path = @harness.export_session
          @output.puts "#{GREEN}✓ Session exported to #{path}#{RESET}"
        end

        def cmd_exit(*)
          throw :exit
        end

        def process_query(message)
          begin
            @harness.query(message) do |event|
              handle_event(event)
            end
          rescue MaxTurnsExceeded
            @output.puts "\n#{RED}⚠ Max turns (#{@harness.query_engine.max_turns}) exceeded#{RESET}\n"
          rescue StandardError => e
            @output.puts "\n#{RED}⚠ Error: #{e.message}#{RESET}\n"
          end
        end

        def handle_event(event)
          case event

          when Models::TurnStarted
            @output.puts "#{DIM}─── Turn #{event.turn_number}/#{event.max_turns} ───#{RESET}"
            @in_thinking = true

          when Models::AssistantTextDelta
            if @in_thinking
              @output.print "#{DIM}💭 #{RESET}"
              @in_thinking = false
            end
            @output.print event.text
            @output.flush

          when Models::ToolExecutionStarted
            @in_thinking = false
            @output.puts ""
            @output.puts "#{YELLOW}⚡ Calling #{BOLD}#{event.tool_name}#{RESET}"

          when Models::ToolExecutionCompleted
            result_text = event.result.text
            display = if result_text.length > 500
                        result_text[0..497] + "..."
                      else
                        result_text
                      end

            if event.result.is_error
              @output.puts "#{RED}   ✗ Error: #{display}#{RESET}"
            else
              display.lines.first(10).each do |line|
                @output.puts "#{DIM}   │ #{line.rstrip}#{RESET}"
              end
              if result_text.lines.count > 10
                @output.puts "#{DIM}   │ ... (#{result_text.lines.count - 10} more lines)#{RESET}"
              end
            end
            @output.puts ""

          when Models::AssistantTurnComplete
            @output.puts ""
            summary = @harness.cost_tracker.summary
            @output.puts "#{DIM}─── Done (#{summary[:input_tokens]} in / #{summary[:output_tokens]} out tokens) ───#{RESET}"
            @output.puts ""

          when Models::ErrorOccurred
            @output.puts "#{RED}⚠ #{event.error}#{RESET}"

          when Models::SkillLoaded
            @output.puts "#{CYAN}📖 Skill loaded: #{BOLD}#{event.skill_name}#{RESET}#{CYAN} (#{event.content_length} chars)#{RESET}"

          when Models::MemorySaved
            @output.puts "#{CYAN}🧠 Memory saved: #{BOLD}#{event.memory_name}#{RESET}#{CYAN} — #{event.description}#{RESET}"

          when Models::ClarificationNeeded
            @output.print "#{GREEN}> #{RESET}"
            @output.flush
          end
        end
      end
    end
  end
end
