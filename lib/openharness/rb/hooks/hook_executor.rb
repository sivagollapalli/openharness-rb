# frozen_string_literal: true

require "json"
require "shellwords"
require "faraday"

module Openharness
  module Rb
    module Hooks
      class HookExecutor
        def initialize(registry:, http_client: nil, query_engine: nil)
          @registry = registry
          @http = http_client || Faraday.new
          @query_engine = query_engine
        end

        def dispatch(event, payload:, context_name: nil)
          hooks = @registry.hooks_for(event, context_name: context_name)
          results = hooks.map { |h| execute_hook(h, payload) }

          failures = results.select { |r| !r[:ok] }
          blocking_failures = hooks.zip(results)
            .select { |h, r| h.block_on_failure && !r[:ok] }

          if blocking_failures.any?
            { ok: false, failures: blocking_failures.map { |_, r| r } }
          else
            { ok: true, warnings: failures }
          end
        end

        private

        def execute_hook(hook, payload)
          case hook
          when CommandHookDefinition then execute_command(hook, payload)
          when HttpHookDefinition then execute_http(hook, payload)
          when PromptHookDefinition then execute_prompt(hook, payload)
          end
        end

        def execute_command(hook, payload)
          env = {
            "OPENHARNESS_HOOK_EVENT" => Shellwords.escape(hook.event.to_s),
            "OPENHARNESS_HOOK_PAYLOAD" => Shellwords.escape(JSON.generate(payload))
          }
          system(env, hook.command)
          { ok: true }
        rescue StandardError => e
          { ok: false, error: e.message }
        end

        def execute_http(hook, payload)
          resp = @http.post(hook.url) do |req|
            req.headers.merge!(hook.headers)
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.generate(payload)
          end
          resp.success? ? { ok: true } : { ok: false, error: "HTTP #{resp.status}" }
        rescue StandardError => e
          { ok: false, error: e.message }
        end

        def execute_prompt(hook, payload)
          prompt_text = hook.prompt_template.gsub("{{payload}}", JSON.generate(payload))
          response = @query_engine.ask(prompt_text)
          result = JSON.parse(response.content)
          result["ok"] ? { ok: true } : { ok: false, error: result["reason"] }
        rescue StandardError => e
          { ok: false, error: e.message }
        end
      end
    end
  end
end
