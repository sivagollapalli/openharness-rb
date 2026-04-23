require "../lib/openharness/rb"

DIM = "\e[2m"
CYAN = "\e[36m"
YELLOW = "\e[33m"
GREEN = "\e[32m"
RED = "\e[31m"
BOLD = "\e[1m"
RESET = "\e[0m"

harness = Openharness::Rb::Harness.new(
  api_key: ENV["OPENROUTER_API_KEY"],
  model: "openai/gpt-oss-120b",
  permission_mode: :full_auto,
  max_turns: 5,
  mcp_servers: [
    { name: "playwright", transport: "stdio", config: { command: "npx", args: ["@playwright/mcp@latest"] } }
  ]
)

in_thinking = false

harness.query("open google.com website in a browser, enter Ruby on Rails and then click on search and get the first 5 results websites") do |event|
  case event

  when Openharness::Rb::Models::TurnStarted
    puts "#{DIM}─── Turn #{event.turn_number}/#{event.max_turns} ───#{RESET}"
    in_thinking = true

  when Openharness::Rb::Models::AssistantTextDelta
    if in_thinking
      print "#{DIM}💭 #{RESET}"
      in_thinking = false
    end
    print event.text

  when Openharness::Rb::Models::ToolExecutionStarted
    in_thinking = false
    puts ""
    puts "#{YELLOW}⚡ Calling #{BOLD}#{event.tool_name}#{RESET}"

  when Openharness::Rb::Models::ToolExecutionCompleted
    text = event.result.text
    display = text.length > 500 ? text[0..497] + "..." : text

    if event.result.is_error
      puts "#{RED}   ✗ Error: #{display}#{RESET}"
    else
      display.lines.first(10).each do |line|
        puts "#{DIM}   │ #{line.rstrip}#{RESET}"
      end
      if text.lines.count > 10
        puts "#{DIM}   │ ... (#{text.lines.count - 10} more lines)#{RESET}"
      end
    end
    puts ""

  when Openharness::Rb::Models::AssistantTurnComplete
    puts ""
    summary = harness.cost_tracker.summary
    puts "#{DIM}─── Done (#{summary[:input_tokens]} in / #{summary[:output_tokens]} out tokens) ───#{RESET}"
    puts ""

  when Openharness::Rb::Models::ErrorOccurred
    puts "#{RED}⚠ #{event.error}#{RESET}"
  end
end
