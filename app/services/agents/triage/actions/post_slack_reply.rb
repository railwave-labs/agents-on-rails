# frozen_string_literal: true

module Agents
  module Triage
    module Actions
      class PostSlackReply
        HIGH_SEVERITIES = %w[high critical].freeze
        LOW_CONFIDENCE  = 0.6

        def initialize(agent_run:, payload:, slack_service: Slack::Service.new)
          @agent_run     = agent_run
          @payload       = payload
          @slack         = slack_service
        end

        def call
          text     = format_message
          response = @slack.client.chat_postMessage(
            channel:   @agent_run.slack_channel_id,
            thread_ts: @agent_run.slack_thread_ts,
            text:      text,
            mrkdwn:    true
          )
          @agent_run.add_step("slack_reply_posted", data: { ts: response["ts"] })
          Result.success(response)
        rescue StandardError => e
          err = ErrorHandler.standardize_error(
            e,
            service: "slack",
            context: { component: "triage_post_reply", agent_run_id: @agent_run.id }
          )
          @agent_run.fail_step("slack_reply_failed", err.message)
          Result.failure(err)
        end

        private

        def format_message
          mention = should_escalate? && escalation_user_id ? "<@#{escalation_user_id}> " : ""
          links   = @payload.context_links.map { |u| "- #{u}" }.join("\n")
          <<~MSG.strip
            #{mention}*Triage* — severity *#{@payload.severity}* (confidence #{@payload.confidence})
            *Hypothesis:* #{@payload.hypothesis}
            *Next step:* #{@payload.suggested_next_step}
            #{links.empty? ? "" : "\n*Context:*\n#{links}"}
          MSG
        end

        def should_escalate?
          HIGH_SEVERITIES.include?(@payload.severity) || @payload.confidence < LOW_CONFIDENCE
        end

        def escalation_user_id
          ENV.fetch("TRIAGE_ESCALATION_SLACK_USER_ID", nil).presence
        end
      end
    end
  end
end
