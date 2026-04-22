# frozen_string_literal: true

require "set"
require_relative "permission_mode"
require_relative "permission_decision"
require_relative "path_rule"

module Openharness
  module Rb
    module Permissions
      class PermissionChecker
        SENSITIVE_PATH_PATTERNS = [
          "~/.ssh/*",
          "~/.aws/credentials",
          "~/.aws/config",
          "~/.config/gcloud/*",
          "~/.kube/config",
          "**/.env",
          "**/.env.*"
        ].freeze

        # Short suffixes of mutating tools.
        # RubyLLM generates names like "openharness--rb--tools--builtin--bash"
        # from class names. We extract the last segment for matching.
        MUTATING_TOOL_SUFFIXES = %w[write_to_file edit_file bash notebook_edit].freeze

        def initialize(mode:, denied_tools: [], allowed_tools: [], path_rules: [], denied_commands: [])
          @mode = mode
          @denied_tools = denied_tools.to_set
          @allowed_tools = allowed_tools.to_set
          @path_rules = path_rules
          @denied_commands = denied_commands
        end

        def evaluate(tool_name:, file_path: nil, command: nil)
          # 1. Sensitive paths (always deny)
          return denied("Sensitive path") if file_path && sensitive_path?(file_path)

          # 2. Denied tools (match full name or short suffix)
          return denied("Tool denied by configuration") if tool_denied?(tool_name)

          # 3. Allowed tools (match full name or short suffix)
          return allowed if tool_allowed?(tool_name)

          # 4. Path rules (most specific wins)
          if file_path
            decision = evaluate_path_rules(file_path)
            return decision if decision
          end

          # 5. Command patterns (string include or regex match)
          return denied("Command denied") if command && denied_command?(command)

          # 6. Mode resolution
          resolve_by_mode(tool_name)
        end

        # Check if a tool is mutating (public for tools to query)
        def mutating_tool?(tool_name)
          MUTATING_TOOL_SUFFIXES.include?(short_name(tool_name))
        end

        private

        # Extract short name from RubyLLM's namespaced tool name.
        # "openharness--rb--tools--builtin--bash" → "bash"
        # "bash" → "bash"
        def short_name(tool_name)
          tool_name.to_s.split("--").last
        end

        def tool_denied?(tool_name)
          @denied_tools.include?(tool_name) ||
            @denied_tools.include?(short_name(tool_name))
        end

        def tool_allowed?(tool_name)
          @allowed_tools.include?(tool_name) ||
            @allowed_tools.include?(short_name(tool_name))
        end

        def sensitive_path?(path)
          expanded = File.expand_path(path)
          SENSITIVE_PATH_PATTERNS.any? do |pat|
            if pat.start_with?("**/")
              File.fnmatch?(pat, expanded, File::FNM_PATHNAME | File::FNM_DOTMATCH)
            else
              File.fnmatch?(File.expand_path(pat), expanded)
            end
          end
        end

        def evaluate_path_rules(path)
          matching = @path_rules.select { |r| File.fnmatch?(r.pattern, path) }
          return nil if matching.empty?

          rule = matching.max_by { |r| r.pattern.length }
          rule.action == "allow" ? allowed : denied("Path denied by rule")
        end

        def denied_command?(command)
          @denied_commands.any? do |pattern|
            pattern.is_a?(Regexp) ? command.match?(pattern) : command.include?(pattern)
          end
        end

        def resolve_by_mode(tool_name)
          case @mode
          when PermissionMode::FULL_AUTO then allowed
          when PermissionMode::PLAN
            mutating_tool?(tool_name) ? denied("Plan mode") : allowed
          else
            mutating_tool?(tool_name) ? requires_confirmation : allowed
          end
        end

        def allowed = PermissionDecision.new(status: "allowed")
        def denied(reason) = PermissionDecision.new(status: "denied", reason: reason)
        def requires_confirmation = PermissionDecision.new(status: "requires_confirmation")
      end
    end
  end
end
