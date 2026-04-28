# frozen_string_literal: true

module Agents
  module Triage
    class AnalyzeJob < ApplicationJob
      include SafetyNetRetries

      queue_as :default

      def perform(slack_event_payload:)
        event   = slack_event_payload["event"] || {}
        channel = event["channel"]
        ts      = event["ts"]

        agent_run = AgentRun.create_for_kind(
          :triage,
          workflow_name:    "triage",
          slack_channel_id: channel,
          slack_thread_ts:  ts,
          input_data:       { slack_event: slack_event_payload }
        )

        agent_run.mark_started!
        Agents::Triage::Orchestrator.execute(agent_run)
      end
    end
  end
end
