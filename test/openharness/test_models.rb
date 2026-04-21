# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    module Models
      class TestConversationMessageRoundTrip < Minitest::Test
        # **Validates: Requirements 1.5**
        # Property 1: For all valid ConversationMessage instances,
        # ConversationMessage.from_h(msg.to_h) produces an object equal to the original.

        VALID_ROLES = %w[user assistant system].freeze
        BLOCK_TYPES = %w[text image tool_use tool_result].freeze

        def random_content_hash
          keys = %w[text url id name input output]
          selected = keys.sample(rand(1..3))
          selected.each_with_object({}) { |k, h| h[k.to_sym] = "val_#{rand(1000)}" }
        end

        def random_content_block
          ContentBlock.new(
            type: BLOCK_TYPES.sample,
            content: random_content_hash
          )
        end

        def random_message
          role = VALID_ROLES.sample
          block_count = rand(1..4)
          blocks = Array.new(block_count) { random_content_block }
          ConversationMessage.new(role: role, content_blocks: blocks)
        end

        def test_round_trip_property
          100.times do |i|
            msg = random_message
            hash = msg.to_h
            restored = ConversationMessage.from_h(hash)

            assert_equal msg.role, restored.role, "Round-trip failed on iteration #{i}: role mismatch"
            assert_equal msg.content_blocks.size, restored.content_blocks.size,
                         "Round-trip failed on iteration #{i}: block count mismatch"

            msg.content_blocks.zip(restored.content_blocks).each_with_index do |(orig, rest), j|
              assert_equal orig.type, rest.type,
                           "Round-trip failed on iteration #{i}, block #{j}: type mismatch"
              assert_equal orig.content, rest.content,
                           "Round-trip failed on iteration #{i}, block #{j}: content mismatch"
            end
          end
        end

        def test_round_trip_with_empty_content_blocks
          msg = ConversationMessage.new(role: "user", content_blocks: [])
          restored = ConversationMessage.from_h(msg.to_h)
          assert_equal msg.role, restored.role
          assert_equal msg.content_blocks, restored.content_blocks
        end
      end

      class TestConversationMessageRoleValidation < Minitest::Test
        # **Validates: Requirements 1.1, 1.3**
        # Property 3: ConversationMessage creation succeeds only for roles in
        # {"user", "assistant", "system"} and raises for all other strings.

        VALID_ROLES = %w[user assistant system].freeze

        def test_valid_roles_succeed
          VALID_ROLES.each do |role|
            msg = ConversationMessage.new(
              role: role,
              content_blocks: [ContentBlock.new(type: "text", content: { text: "hello" })]
            )
            assert_equal role, msg.role
          end
        end

        def test_invalid_roles_raise
          invalid_roles = %w[admin moderator tool USER Assistant SYSTEM]
          50.times do
            invalid_roles << "random_#{rand(10_000)}"
          end

          invalid_roles.each do |role|
            assert_raises(Dry::Struct::Error, Dry::Types::ConstraintError) do
              ConversationMessage.new(
                role: role,
                content_blocks: [ContentBlock.new(type: "text", content: { text: "hello" })]
              )
            end
          end
        end

        def test_empty_string_role_raises
          assert_raises(Dry::Struct::Error, Dry::Types::ConstraintError) do
            ConversationMessage.new(
              role: "",
              content_blocks: [ContentBlock.new(type: "text", content: { text: "hello" })]
            )
          end
        end
      end

      class TestQueryContextDefaults < Minitest::Test
        # **Validates: Requirements 6.2, 6.3**

        def test_default_cwd_is_current_directory
          ctx = QueryContext.new
          assert_equal Dir.pwd, ctx.cwd
        end

        def test_default_max_turns_is_10
          ctx = QueryContext.new
          assert_equal 10, ctx.max_turns
        end

        def test_custom_values_override_defaults
          ctx = QueryContext.new(cwd: "/tmp", max_turns: 5)
          assert_equal "/tmp", ctx.cwd
          assert_equal 5, ctx.max_turns
        end
      end

      class TestToolExecutionContextImmutability < Minitest::Test
        # **Validates: Requirements 12.2**

        def test_no_attribute_writers
          emitter = proc { |event| event }
          ctx = ToolExecutionContext.new(
            cwd: "/home/user",
            session_id: "sess-123",
            event_emitter: emitter
          )

          # Dry::Struct does not expose setter methods — assignment should raise NoMethodError
          assert_raises(NoMethodError) do
            ctx.cwd = "/other"
          end

          assert_raises(NoMethodError) do
            ctx.session_id = "other"
          end

          assert_raises(NoMethodError) do
            ctx.event_emitter = proc {}
          end
        end

        def test_new_returns_different_instance_for_different_values
          emitter = proc { |event| event }
          ctx1 = ToolExecutionContext.new(cwd: "/a", session_id: "s1", event_emitter: emitter)
          ctx2 = ToolExecutionContext.new(cwd: "/b", session_id: "s2", event_emitter: emitter)

          refute_equal ctx1.cwd, ctx2.cwd
          refute_equal ctx1.session_id, ctx2.session_id
        end

        def test_no_setter_methods
          emitter = proc { |event| event }
          ctx = ToolExecutionContext.new(
            cwd: "/home/user",
            session_id: "sess-123",
            event_emitter: emitter
          )

          refute ctx.respond_to?(:cwd=), "Should not have cwd= setter"
          refute ctx.respond_to?(:session_id=), "Should not have session_id= setter"
          refute ctx.respond_to?(:event_emitter=), "Should not have event_emitter= setter"
        end
      end
    end
  end
end
