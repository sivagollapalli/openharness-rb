# frozen_string_literal: true

module Openharness
  module Rb
    module Agents
      class TeamRegistry
        def initialize(parent_permission_checker: nil)
          @agents = {}
          @mailboxes = Hash.new { |h, k| h[k] = [] }
          @parent_permissions = parent_permission_checker
        end

        def register(agent_def)
          raise DuplicateAgentError, agent_def.name if @agents.key?(agent_def.name)

          @agents[agent_def.name] = agent_def
        end

        def get(name)
          @agents.fetch(name) { raise AgentNotFoundError, name }
        end

        def list_agents
          @agents.values
        end

        def send_message(from:, to:, content:)
          raise AgentNotFoundError, to unless @agents.key?(to)

          @mailboxes[to] << { from: from, content: content, timestamp: Time.now }
        end

        def receive_messages(agent_name)
          messages = @mailboxes[agent_name].dup
          @mailboxes[agent_name].clear
          messages
        end

        def propagate_permissions(permission_checker)
          @parent_permissions = permission_checker
        end
      end
    end
  end
end
