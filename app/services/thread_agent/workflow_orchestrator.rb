# frozen_string_literal: true

module ThreadAgent
  class WorkflowOrchestrator
    # Execute the complete workflow for a given workflow run
    # @param workflow_run [WorkflowRun] The workflow run to process
    # @return [ThreadAgent::Result] Result object with success or error
    def self.execute_workflow(workflow_run)
      log_with_context(workflow_run, "WorkflowOrchestrator executing workflow", step: "workflow_execution_started")

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
      # Skip Notion processing if no template or no database configured
      if workflow_run.template&.notion_database
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

        # Mark workflow as completed with Notion integration
        workflow_run.mark_completed!({
          slack_thread_data: thread_data,
          openai_content: openai_result.data[:content],
          ai_model_used: openai_result.data[:model],
          notion_page_url: notion_result.data[:url],
          notion_page_id: notion_result.data[:id]
        })
      else
        # Mark workflow as completed without Notion integration
        workflow_run.add_step("notion_processing_skipped", data: {
          reason: "No template or database configured"
        })

        workflow_run.mark_completed!({
          slack_thread_data: thread_data,
          openai_content: openai_result.data[:content],
          ai_model_used: openai_result.data[:model]
        })
      end

      log_with_context(workflow_run, "WorkflowOrchestrator completed workflow", step: "workflow_execution_completed")
      ThreadAgent::Result.success(workflow_run)
    end

    private_class_method

    def self.process_with_slack(workflow_run)
      log_with_context(workflow_run, "Starting Slack processing", step: "slack_processing_started")

      # Validate input using the new validator
      validation_result = ThreadAgent::Slack::WorkflowValidator.validate_workflow_input(workflow_run)
      return validation_result if validation_result.failure?

      # Initialize Slack service and delegate to thread processor
      slack_service = ThreadAgent::Slack::Service.new(max_retries: 3)
      slack_service.process_workflow_input(workflow_run)
    end

    def self.process_with_openai(workflow_run, thread_data)
      log_with_context(workflow_run, "Starting OpenAI processing",
                       step: "openai_processing_started",
                       thread_message_count: thread_data[:replies]&.length || 0)

      begin
        # Initialize OpenAI service
        openai_service = ThreadAgent::Openai::Service.new

        # Extract custom prompt from input_data if provided
        custom_prompt = workflow_run.input_data&.dig("custom_prompt") ||
                       workflow_run.input_data&.dig(:custom_prompt)

        # Transform content using the service
        result = openai_service.transform_content(
          template: workflow_run.template,
          thread_data: thread_data,
          custom_prompt: custom_prompt
        )

        if result.success?
          # Store model to avoid multiple calls for tests
          model_used = openai_service.model

          log_with_context(workflow_run, "OpenAI processing completed successfully",
                           step: "openai_processing_completed",
                           model_used: model_used,
                           content_length: result.data.length)

          ThreadAgent::Result.success({
            content: result.data,
            model: model_used
          })
        else
          # Create a proper OpenAI error instead of a string
          openai_error = ThreadAgent::OpenaiError.new(
            "OpenAI service returned error: #{result.error}",
            context: {
              component: "workflow_orchestrator_openai",
              workflow_run_id: workflow_run.id,
              template_id: workflow_run.template&.id
            }
          )

          log_with_context(workflow_run, "OpenAI processing failed",
                           step: "openai_processing_failed",
                           error: openai_error.message,
                           level: :error)
          ThreadAgent::Result.failure(openai_error)
        end

      rescue ThreadAgent::Error => e
        # Already standardized error - log and convert to result
        ThreadAgent::ErrorHandler.log_error(e, level: :error)
        log_with_context(workflow_run, "OpenAI processing failed with standardized error",
                         step: "openai_processing_failed",
                         error_code: e.code,
                         error: e.message,
                         level: :error)
        ThreadAgent::Result.failure(e)
      rescue StandardError => e
        # Handle unexpected errors with ErrorHandler
        standardized_error = ThreadAgent::ErrorHandler.standardize_error(
          e,
          context: {
            component: "workflow_orchestrator_openai",
            workflow_run_id: workflow_run.id,
            template_id: workflow_run.template&.id
          },
          service: "openai"
        )

        ThreadAgent::ErrorHandler.log_error(standardized_error, level: :error)
        log_with_context(workflow_run, "Unexpected error during OpenAI processing",
                         step: "openai_processing_failed",
                         error_code: standardized_error.code,
                         error: standardized_error.message,
                         backtrace: e.backtrace.first(3),
                         level: :error)
        ThreadAgent::Result.failure(standardized_error)
      end
    end

    def self.process_with_notion(workflow_run, thread_data, openai_data)
      log_with_context(workflow_run, "Starting Notion processing",
                       step: "notion_processing_started",
                       database_id: workflow_run.template&.notion_database&.notion_database_id)

      # Initialize Notion service and delegate to workflow page creation
      notion_service = ThreadAgent::Notion::Service.new(max_retries: 3)
      result = notion_service.create_page_from_workflow(
        thread_data: thread_data,
        workflow_run: workflow_run,
        openai_data: openai_data
      )

      if result.success?
        log_with_context(workflow_run, "Notion processing completed successfully",
                         step: "notion_processing_completed",
                         page_id: result.data[:id],
                         page_url: result.data[:url])

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
      log_with_context(workflow_run, "Workflow failed",
                       step: step_name,
                       error: error_message,
                       level: :error)
    end

    # Log with structured context including workflow_run_id and step_name
    # @param workflow_run [WorkflowRun] The workflow run for context
    # @param message [String] The log message
    # @param step [String] The current step name
    # @param level [Symbol] Log level (:info, :error, :warn, :debug)
    # @param **context [Hash] Additional context data
    def self.log_with_context(workflow_run, message, step:, level: :info, **context)
      structured_data = {
        workflow_run_id: workflow_run.id,
        step_name: step,
        service_class: self.name,
        workflow_name: workflow_run.workflow_name
      }.merge(context)

      case level
      when :error
        Rails.logger.error("#{message} - #{structured_data.to_json}")
      when :warn
        Rails.logger.warn("#{message} - #{structured_data.to_json}")
      when :debug
        Rails.logger.debug("#{message} - #{structured_data.to_json}")
      else
        Rails.logger.info("#{message} - #{structured_data.to_json}")
      end
    end
  end
end
