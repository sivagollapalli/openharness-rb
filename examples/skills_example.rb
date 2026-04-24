require "./lib/openharness/rb"

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
  max_turns: 20,
)

# harness = Openharness::Rb::Harness.new(
#   api_key: ENV["OPENAI_API_KEY"],
#   model: "gpt-4o-mini",
#   permission_mode: :full_auto,
#   max_turns: 5,
# )

in_thinking = false

problem_statement = "Create new golang project name as harness-demo with golang versio. Added user and profile model. User has one profile. User has first_name, last_name, email attributes. All string attributes. profile has language, bio. All are string attributes. Create user CRUD where it can create user with profile in single action"

harness.query(problem_statement) do |event|
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

  when Openharness::Rb::Models::SkillLoaded
    puts "#{CYAN}📖 Skill loaded: #{BOLD}#{event.skill_name}#{RESET}#{CYAN} — #{event.description} (#{event.content_length} chars)#{RESET}"
  end
end
