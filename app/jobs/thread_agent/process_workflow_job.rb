# frozen_string_literal: true

module ThreadAgent
  class ProcessWorkflowJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Rails.logger.info("ProcessWorkflowJob running. Payload: #{payload.inspect}")

      # Extract workflow details from the modal submission
      user_id = payload.dig("user", "id")
      view = payload["view"]
      state_values = view&.dig("state", "values") || {}

      Rails.logger.info("Processing workflow for user: #{user_id}")
      Rails.logger.info("Modal state values: #{state_values.inspect}")

      # TODO: implement workflow processing logic in later iteration
      # This will include:
      # - Extracting workspace and template selections
      # - Fetching thread data from Slack
      # - Processing the thread through the selected workflow
      # - Creating Notion pages/databases as needed

      Rails.logger.info("ProcessWorkflowJob completed successfully")
    rescue StandardError => e
      Rails.logger.error("ProcessWorkflowJob failed: #{e.message}")
      Rails.logger.error("Backtrace: #{e.backtrace.join("\n")}")
      raise e
    end
  end
end
