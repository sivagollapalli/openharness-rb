# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    # ---------------------------------------------------------------
    # 11.3.1 Test TeamRegistry register/get/list lifecycle
    # ---------------------------------------------------------------
    class TestTeamRegistryLifecycle < Minitest::Test
      # **Validates: Requirements 35.1, 35.2, 35.4**

      def setup
        @registry = Agents::TeamRegistry.new
        @agent = Agents::AgentDefinition.new(
          name: "coder",
          role: "developer",
          capabilities: ["write_code", "debug"],
          tool_access: ["read_file", "write_file"]
        )
      end

      def test_register_and_get_agent
        @registry.register(@agent)
        retrieved = @registry.get("coder")

        assert_equal "coder", retrieved.name
        assert_equal "developer", retrieved.role
        assert_equal ["write_code", "debug"], retrieved.capabilities
        assert_equal ["read_file", "write_file"], retrieved.tool_access
      end

      def test_list_agents_returns_all_registered
        agent_b = Agents::AgentDefinition.new(
          name: "reviewer",
          role: "code_reviewer",
          capabilities: ["review"]
        )

        @registry.register(@agent)
        @registry.register(agent_b)

        agents = @registry.list_agents
        assert_equal 2, agents.size
        names = agents.map(&:name)
        assert_includes names, "coder"
        assert_includes names, "reviewer"
      end

      def test_list_agents_empty_when_none_registered
        assert_empty @registry.list_agents
      end

      def test_agent_definition_defaults
        agent = Agents::AgentDefinition.new(name: "minimal", role: "helper")
        assert_equal [], agent.capabilities
        assert_equal [], agent.tool_access
      end
    end

    # ---------------------------------------------------------------
    # 11.3.2 Test TeamRegistry raises DuplicateAgentError
    # ---------------------------------------------------------------
    class TestTeamRegistryDuplicateAgent < Minitest::Test
      # **Validates: Requirements 35.3**

      def test_raises_duplicate_agent_error_on_duplicate_name
        registry = Agents::TeamRegistry.new
        agent = Agents::AgentDefinition.new(name: "coder", role: "developer")

        registry.register(agent)
        assert_raises(DuplicateAgentError) { registry.register(agent) }
      end
    end

    # ---------------------------------------------------------------
    # 11.3.3 Test send_message/receive_messages mailbox behavior
    # ---------------------------------------------------------------
    class TestTeamRegistryMailbox < Minitest::Test
      # **Validates: Requirements 36.1, 36.2**

      def setup
        @registry = Agents::TeamRegistry.new
        @alice = Agents::AgentDefinition.new(name: "alice", role: "sender")
        @bob = Agents::AgentDefinition.new(name: "bob", role: "receiver")
        @registry.register(@alice)
        @registry.register(@bob)
      end

      def test_send_and_receive_message
        @registry.send_message(from: "alice", to: "bob", content: "hello")

        messages = @registry.receive_messages("bob")
        assert_equal 1, messages.size
        assert_equal "alice", messages.first[:from]
        assert_equal "hello", messages.first[:content]
        assert_instance_of Time, messages.first[:timestamp]
      end

      def test_receive_clears_mailbox
        @registry.send_message(from: "alice", to: "bob", content: "first")
        @registry.send_message(from: "alice", to: "bob", content: "second")

        first_batch = @registry.receive_messages("bob")
        assert_equal 2, first_batch.size

        second_batch = @registry.receive_messages("bob")
        assert_empty second_batch
      end

      def test_multiple_messages_accumulate
        @registry.send_message(from: "alice", to: "bob", content: "msg1")
        @registry.send_message(from: "alice", to: "bob", content: "msg2")

        messages = @registry.receive_messages("bob")
        assert_equal 2, messages.size
        assert_equal "msg1", messages[0][:content]
        assert_equal "msg2", messages[1][:content]
      end

      def test_receive_for_agent_with_no_messages
        messages = @registry.receive_messages("alice")
        assert_empty messages
      end
    end

    # ---------------------------------------------------------------
    # 11.3.4 Test send_message raises AgentNotFoundError
    # ---------------------------------------------------------------
    class TestTeamRegistrySendToUnknown < Minitest::Test
      # **Validates: Requirements 36.3**

      def test_send_message_raises_agent_not_found_for_unknown_recipient
        registry = Agents::TeamRegistry.new
        sender = Agents::AgentDefinition.new(name: "alice", role: "sender")
        registry.register(sender)

        assert_raises(AgentNotFoundError) do
          registry.send_message(from: "alice", to: "unknown", content: "hello")
        end
      end

      def test_get_raises_agent_not_found_for_unknown_name
        registry = Agents::TeamRegistry.new
        assert_raises(AgentNotFoundError) { registry.get("nonexistent") }
      end
    end
  end
end
