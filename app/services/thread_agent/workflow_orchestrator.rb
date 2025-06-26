# frozen_string_literal: true

module ThreadAgent
  class WorkflowOrchestrator
    # Execute the complete workflow for a given workflow run
    # @param workflow_run [WorkflowRun] The workflow run to process
    # @return [ThreadAgent::Result] Result object with success or error
    def self.execute_workflow(workflow_run)
      Rails.logger.info("WorkflowOrchestrator executing workflow for workflow_run: #{workflow_run.id}")

      # Start the workflow execution
      workflow_run.mark_started!
      workflow_run.add_step("workflow_started")

      # Step 1: Slack Thread Fetching and Processing
      slack_result = process_with_slack(workflow_run)
      if slack_result.failure?
        fail_workflow_run(workflow_run, "slack_processing_failed", slack_result.error)
        return slack_result
      end

      thread_data = slack_result.data
      workflow_run.add_step("slack_processing_completed", data: {
        channel_id: thread_data[:channel_id],
        thread_ts: thread_data[:thread_ts],
        message_count: thread_data[:replies]&.length || 0
      })

      # Step 2: OpenAI Service Integration
      openai_result = process_with_openai(workflow_run, thread_data)
      if openai_result.failure?
        fail_workflow_run(workflow_run, "openai_processing_failed", openai_result.error)
        return openai_result
      end

      workflow_run.add_step("openai_processing_completed", data: {
        transformed_content: openai_result.data[:content],
        model_used: openai_result.data[:model]
      })

      # Step 3: Notion Service Integration
      notion_result = process_with_notion(workflow_run, thread_data, openai_result.data)
      if notion_result.failure?
        fail_workflow_run(workflow_run, "notion_processing_failed", notion_result.error)
        return notion_result
      end

      workflow_run.add_step("notion_processing_completed", data: {
        page_url: notion_result.data[:url],
        page_id: notion_result.data[:id],
        database_id: notion_result.data[:database_id]
      })

      # Mark workflow as completed
      workflow_run.mark_completed!({
        slack_thread_data: thread_data,
        openai_content: openai_result.data[:content],
        notion_page_url: notion_result.data[:url],
        notion_page_id: notion_result.data[:id]
      })

      Rails.logger.info("WorkflowOrchestrator completed workflow for workflow_run: #{workflow_run.id}")
      ThreadAgent::Result.success(workflow_run)
    end

    private_class_method

    def self.process_with_slack(workflow_run)
      Rails.logger.info("WorkflowOrchestrator: Starting Slack processing for workflow_run: #{workflow_run.id}")

      # Validate input using the new validator
      validation_result = ThreadAgent::Slack::WorkflowValidator.validate_workflow_input(workflow_run)
      return validation_result if validation_result.failure?

      # Initialize Slack service and delegate to thread processor
      slack_service = ThreadAgent::Slack::Service.new(max_retries: 3)
      slack_service.process_workflow_input(workflow_run)
    end

    def self.process_with_openai(workflow_run, thread_data)
      Rails.logger.info("WorkflowOrchestrator: Starting OpenAI processing for workflow_run: #{workflow_run.id}")

      begin
        # Initialize OpenAI service
        openai_service = ThreadAgent::Openai::Service.new

        # Transform content using the service
        result = openai_service.transform_content(
          template: workflow_run.template,
          thread_data: thread_data,
          custom_prompt: nil
        )

        if result.success?
          Rails.logger.info("WorkflowOrchestrator: OpenAI processing completed successfully for workflow_run: #{workflow_run.id}")

          ThreadAgent::Result.success({
            content: result.data,
            model: openai_service.model
          })
        else
          error_message = "OpenAI service returned error: #{result.error}"
          Rails.logger.error("WorkflowOrchestrator: OpenAI processing failed for workflow_run #{workflow_run.id}: #{error_message}")
          ThreadAgent::Result.failure(error_message)
        end

      rescue ThreadAgent::OpenaiError => e
        Rails.logger.error("WorkflowOrchestrator: OpenAI processing failed for workflow_run #{workflow_run.id}: #{e.message}")
        ThreadAgent::Result.failure("OpenAI processing failed: #{e.message}")
      rescue StandardError => e
        Rails.logger.error("WorkflowOrchestrator: Unexpected error during OpenAI processing for workflow_run #{workflow_run.id}: #{e.message}")
        ThreadAgent::Result.failure("Unexpected error: #{e.message}")
      end
    end

    def self.process_with_notion(workflow_run, thread_data, openai_data)
      Rails.logger.info("WorkflowOrchestrator: Starting Notion processing for workflow_run: #{workflow_run.id}")

      # Initialize Notion service and delegate to workflow page creation
      notion_service = ThreadAgent::Notion::Service.new(max_retries: 3)
      result = notion_service.create_page_from_workflow(
        thread_data: thread_data,
        workflow_run: workflow_run,
        openai_data: openai_data
      )

      if result.success?
        Rails.logger.info("WorkflowOrchestrator: Notion processing completed successfully for workflow_run: #{workflow_run.id}")

        # Return enriched result data
        ThreadAgent::Result.success({
          id: result.data[:id],
          url: result.data[:url],
          title: result.data[:title],
          database_id: workflow_run.template.notion_database.notion_database_id,
          created_time: result.data[:created_time]
        })
      else
        result
      end
    end

    def self.fail_workflow_run(workflow_run, step_name, error_message)
      workflow_run.fail_step(step_name, error_message)
      workflow_run.mark_failed!(error_message)
      Rails.logger.error("WorkflowOrchestrator: Workflow failed for workflow_run #{workflow_run.id}: #{error_message}")
    end
  end
end
