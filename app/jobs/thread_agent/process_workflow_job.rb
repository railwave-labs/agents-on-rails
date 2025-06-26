# frozen_string_literal: true

module ThreadAgent
  class ProcessWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_run_id)
      Rails.logger.info("ProcessWorkflowJob started for workflow_run_id: #{workflow_run_id}")

      # Validate required parameter
      raise ArgumentError, "workflow_run_id cannot be nil or blank" unless workflow_run_id.present?

      # Load the workflow run
      workflow_run = ThreadAgent::WorkflowRun.find(workflow_run_id)

      Rails.logger.info("Processing workflow_run: #{workflow_run.id}")

      # Placeholder for actual workflow processing logic
      # This will be implemented in subsequent tasks

      Rails.logger.info("ProcessWorkflowJob completed for workflow_run_id: #{workflow_run_id}")
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("WorkflowRun not found for ID #{workflow_run_id}: #{e.message}")
      raise
    end
  end
end
