# frozen_string_literal: true

module ThreadAgent
  class ProcessWorkflowJob < ApplicationJob
    queue_as :default

    # Job-level retry configuration as safety net for catastrophic failures
    # after service-level retries are exhausted

    # Slack service errors (after service-level retries fail)
    retry_on ThreadAgent::SlackError, wait: 30.seconds, attempts: 3

    # OpenAI service errors (after service-level retries fail)
    retry_on ThreadAgent::OpenaiError, wait: 30.seconds, attempts: 3

    # Generic network/connection errors that might bypass service-level handling
    retry_on Net::ReadTimeout, Net::OpenTimeout, Timeout::Error, wait: 30.seconds, attempts: 3
    retry_on Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError, wait: 30.seconds, attempts: 3

    # Faraday errors (HTTP client used by both services)
    retry_on Faraday::Error, wait: 30.seconds, attempts: 3

    # Database connection issues
    retry_on ActiveRecord::ConnectionTimeoutError, wait: 30.seconds, attempts: 3

    def perform(payload)
      Rails.logger.info("ProcessWorkflowJob received: #{payload.inspect}")

      ActiveSupport::Notifications.instrument("thread_agent.workflow.process", payload) do
        # TODO: Implement actual workflow processing (Slack thread → Notion page transformation)
      end

      true
    end
  end
end
