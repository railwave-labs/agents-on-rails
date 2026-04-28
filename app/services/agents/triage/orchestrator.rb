# frozen_string_literal: true

module Agents
  module Triage
    class Orchestrator
      def self.execute(agent_run)
        agent_run.add_step("triage_started")

        prompt      = PromptBuilder.build(agent_run: agent_run)
        mcp_servers = Anthropic::McpServers.load(:default)

        on_step = lambda do |name:, data:|
          agent_run.add_step(name, data: data)
          if name == "usage"
            agent_run.record_cost!(
              cents:  0,
              tokens: data.transform_keys(&:to_s)
            )
          end
        end

        text = Anthropic::ToolLoop
          .new(mcp_servers: mcp_servers, on_step: on_step)
          .run(system: prompt[:system], messages: prompt[:messages])

        payload = StructuredResponse.parse(text)
        agent_run.add_step("triage_parsed", data: payload.to_h)

        Actions::PostSlackReply.new(agent_run: agent_run, payload: payload).call

        agent_run.mark_completed!(payload.to_h)
        Result.success(payload)
      rescue ApplicationError => e
        agent_run.fail_step("triage_failed", e.message)
        agent_run.mark_failed!(e.message)
        ErrorHandler.to_result(e, service: "anthropic")
      end
    end
  end
end
