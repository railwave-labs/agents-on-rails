# frozen_string_literal: true

module ThreadAgent
  class ProcessWorkflowJob < ApplicationJob
    include SafetyNetRetries

    queue_as :default

    def perform(payload)
      Rails.logger.info("ProcessWorkflowJob received: #{payload.inspect}")

      ActiveSupport::Notifications.instrument("thread_agent.workflow.process", payload) do
        process_workflow(payload)
      end

      true
    end

    private

    def process_workflow(payload)
      # Basic safety checks - return nil for unsupported cases
      return nil if payload.nil? || !payload.is_a?(Hash)

      # Only proceed if we have a workflow_run_id (the "new" workflow format)
      workflow_run_id = payload[:workflow_run_id]
      return nil unless workflow_run_id.present?

      thread_data = payload[:thread_data]

      # Load the workflow run with its template
      workflow_run = ThreadAgent::WorkflowRun.find(workflow_run_id)
      template = workflow_run.template

      # Transform thread content using OpenAI
      openai_service = create_openai_service
      transformed_content = openai_service.transform_content(
        template: template,
        thread_data: thread_data
      )

      Rails.logger.info("OpenAI transformation completed for workflow_run_id: #{workflow_run_id}")

      # TODO: Send transformed content to Notion
      # This will be implemented when NotionService is ready
      Rails.logger.info("Transformed content ready for Notion: #{transformed_content.length} characters")

      transformed_content
    end

    def create_openai_service
      ThreadAgent::Openai::Service.new(
        api_key: ThreadAgent.configuration.openai_api_key,
        model: ThreadAgent.configuration.openai_model,
        timeout: 30,
        max_retries: 3
      )
    end
  end
end
