# frozen_string_literal: true

module Openharness
  module Rb
    module Hooks
      class HookEvent
        SESSION_START = :session_start
        SESSION_END = :session_end
        PRE_TOOL_USE = :pre_tool_use
        POST_TOOL_USE = :post_tool_use
      end
    end
  end
end
