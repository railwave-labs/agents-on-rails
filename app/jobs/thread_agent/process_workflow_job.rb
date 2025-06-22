# frozen_string_literal: true

module ThreadAgent
  class ProcessWorkflowJob < ApplicationJob
    queue_as :default

    retry_on ::Slack::Web::Api::Errors::SlackError, wait: 30.seconds, attempts: 5

    def perform(payload)
      Rails.logger.info("ProcessWorkflowJob received: #{payload.inspect}")

      ActiveSupport::Notifications.instrument("thread_agent.workflow.process", payload) do
        # TODO: Implement actual workflow processing (Slack thread → Notion page transformation)
      end

      true
    end
  end
end
