# frozen_string_literal: true

require "test_helper"

module Openharness
  module Rb
    module Tools
      # Simple test tool subclasses for testing

      class EchoTool < BaseTool
        def name = "echo"
        def description = "Echoes input text"
        def input_schema = { type: "object", properties: { text: { type: "string" } }, required: ["text"] }

        private

        def execute(input, _context)
          Models::ToolResult.new(text: input[:text] || input["text"] || "")
        end
      end

      class FailingTool < BaseTool
        def name = "failing"
        def description = "Always raises an error"
        def input_schema = { type: "object", properties: {}, required: [] }

        private

        def execute(_input, _context)
          raise "Something went wrong"
        end
      end

      class ConditionalFailTool < BaseTool
        def name = "conditional_fail"
        def description = "Raises on invalid inputs"
        def input_schema = { type: "object", properties: { value: { type: "integer" } }, required: ["value"] }

        private

        def execute(input, _context)
          val = input[:value] || input["value"]
          raise ArgumentError, "negative value: #{val}" if val.is_a?(Integer) && val < 0
          raise TypeError, "not an integer: #{val}" unless val.is_a?(Integer)

          Models::ToolResult.new(text: val.to_s)
        end
      end

      # 4.4.1 Test ToolRegistry register/get/unregister lifecycle
      class TestToolRegistryLifecycle < Minitest::Test
        # **Validates: Requirements 11.1, 11.5**

        def setup
          @registry = ToolRegistry.new
          @tool = EchoTool.new
        end

        def test_register_and_get_tool
          @registry.register(@tool)
          retrieved = @registry.get_tool("echo")
          assert_equal @tool, retrieved
        end

        def test_unregister_removes_tool
          @registry.register(@tool)
          @registry.unregister("echo")
          assert_raises(ToolNotFoundError) { @registry.get_tool("echo") }
        end

        def test_full_lifecycle
          @registry.register(@tool)
          assert_equal @tool, @registry.get_tool("echo")
          @registry.unregister("echo")
          assert_raises(ToolNotFoundError) { @registry.get_tool("echo") }
        end
      end

      # 4.4.2 Test ToolRegistry raises DuplicateToolError on duplicate name
      class TestToolRegistryDuplicateError < Minitest::Test
        # **Validates: Requirements 11.2**

        def setup
          @registry = ToolRegistry.new
          @tool = EchoTool.new
        end

        def test_raises_duplicate_tool_error
          @registry.register(@tool)
          assert_raises(DuplicateToolError) { @registry.register(EchoTool.new) }
        end
      end

      # 4.4.3 Test ToolRegistry raises ToolNotFoundError for unknown name
      class TestToolRegistryNotFoundError < Minitest::Test
        # **Validates: Requirements 11.3**

        def test_raises_tool_not_found_error
          registry = ToolRegistry.new
          assert_raises(ToolNotFoundError) { registry.get_tool("nonexistent") }
        end
      end

      # 4.4.4 Test BaseTool.call catches exceptions and returns error ToolResult
      class TestBaseToolErrorCatching < Minitest::Test
        # **Validates: Requirements 10.4**

        def test_call_catches_exception_and_returns_error_result
          tool = FailingTool.new
          context = Models::ToolExecutionContext.new(
            cwd: "/tmp", session_id: "test", event_emitter: proc {}
          )
          result = tool.call({}, context)

          assert_instance_of Models::ToolResult, result
          assert result.is_error, "Expected is_error to be true"
          assert_equal "Something went wrong", result.text
        end
      end

      # 4.4.5 [PBT] Property: Input validation error conditions
      class TestInputValidationErrorConditions < Minitest::Test
        # **Validates: Requirements 43.3**
        # Property 13: For all inputs that cause execute to raise,
        # BaseTool.call returns a ToolResult with is_error=true.

        def setup
          @tool = ConditionalFailTool.new
          @context = Models::ToolExecutionContext.new(
            cwd: "/tmp", session_id: "test", event_emitter: proc {}
          )
        end

        def test_invalid_inputs_always_produce_error_result
          100.times do |i|
            # Generate random invalid inputs: negative integers and non-integer types
            invalid_input = if rand < 0.5
                             { value: -(rand(1..10_000)) }
                           else
                             bad_values = ["string", 3.14, true, nil, [], {}]
                             { value: bad_values.sample }
                           end

            result = @tool.call(invalid_input, @context)

            assert_instance_of Models::ToolResult, result,
                               "Iteration #{i}: expected ToolResult, got #{result.class}"
            assert result.is_error,
                   "Iteration #{i}: expected is_error=true for input #{invalid_input.inspect}"
          end
        end
      end

      # 4.4.6 [PBT] Property: ToolRegistry unregister idempotence
      class TestToolRegistryUnregisterIdempotence < Minitest::Test
        # **Validates: Requirements 11.5**
        # Property 12: Unregistering a tool then attempting to get it raises
        # ToolNotFoundError; unregistering a non-existent tool is a no-op.

        def test_unregister_idempotence_property
          100.times do |i|
            registry = ToolRegistry.new
            tool_count = rand(1..5)
            tool_names = tool_count.times.map { |j| "tool_#{i}_#{j}" }

            # Create and register tools with unique names
            tools = tool_names.map do |name|
              tool = EchoTool.new
              tool.define_singleton_method(:name) { name }
              tool
            end
            tools.each { |t| registry.register(t) }

            # Pick a random tool to unregister
            target = tool_names.sample

            # Unregister once
            registry.unregister(target)

            # get_tool should raise ToolNotFoundError
            assert_raises(ToolNotFoundError,
                          "Iteration #{i}: get_tool should raise after unregister") do
              registry.get_tool(target)
            end

            # Double unregister should be a no-op (no error)
            registry.unregister(target) # should not raise
          end
        end
      end
    end
  end
end
