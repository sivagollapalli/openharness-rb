# frozen_string_literal: true

module Openharness
  module Rb
    module Tools
      module Builtin
        # Mixin for mutating tools that need permission checks.
        # Reads the permission checker and I/O from environment/globals
        # set by the QueryEngine before each query.
        module PermissionGuard
          def check_permission!
            checker = Thread.current[:openharness_permission_checker]
            return :allowed unless checker

            decision = checker.evaluate(tool_name: name)

            case decision.status
            when "allowed"
              :allowed
            when "requires_confirmation"
              prompt_user_for_confirmation(decision)
            when "denied"
              :denied
            end
          end

          def permission_denied_message(reason = nil)
            msg = "⛔ Permission denied for '#{name}'"
            msg += ": #{reason}" if reason
            msg += ". This tool is blocked by the current permission mode."
            { error: msg }
          end

          def user_denied_message
            { error: "⛔ User denied permission for '#{name}'. Do not retry this tool without asking the user first." }
          end

          private

          def prompt_user_for_confirmation(decision)
            output = Thread.current[:openharness_output] || $stdout
            input = Thread.current[:openharness_input] || $stdin

            output.print "\n⚠️  Tool '#{name}' wants to modify your system. Allow? (y/n): "
            output.flush
            answer = input.gets&.chomp&.strip&.downcase

            if answer == "y" || answer == "yes"
              :allowed
            else
              :denied_by_user
            end
          end
        end
      end
    end
  end
end
