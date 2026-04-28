# frozen_string_literal: true

module Agents
  module ThreadCapture
    class Orchestrator
      def self.execute(agent_run)
        execute_workflow(agent_run)
      end

      def self.execute_workflow(workflow_run)
        log_with_context(workflow_run, "Orchestrator executing workflow", step: "workflow_execution_started")

        workflow_run.mark_started!
        workflow_run.add_step("workflow_started")

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

        openai_result = process_with_openai(workflow_run, thread_data)
        if openai_result.failure?
          fail_workflow_run(workflow_run, "openai_processing_failed", openai_result.error)
          return openai_result
        end

        workflow_run.add_step("openai_processing_completed", data: {
          transformed_content: openai_result.data[:content],
          model_used: openai_result.data[:model]
        })

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

          workflow_run.mark_completed!({
            slack_thread_data: thread_data,
            openai_content: openai_result.data[:content],
            ai_model_used: openai_result.data[:model],
            notion_page_url: notion_result.data[:url],
            notion_page_id: notion_result.data[:id]
          })
        else
          workflow_run.add_step("notion_processing_skipped", data: { reason: "No template or database configured" })
          workflow_run.mark_completed!({
            slack_thread_data: thread_data,
            openai_content: openai_result.data[:content],
            ai_model_used: openai_result.data[:model]
          })
        end

        log_with_context(workflow_run, "Orchestrator completed workflow", step: "workflow_execution_completed")
        Result.success(workflow_run)
      end

      private_class_method

      def self.process_with_slack(workflow_run)
        log_with_context(workflow_run, "Starting Slack processing", step: "slack_processing_started")
        validation_result = Slack::WorkflowValidator.validate_workflow_input(workflow_run)
        return validation_result if validation_result.failure?

        slack_service = Slack::Service.new(max_retries: 3)
        slack_service.process_workflow_input(workflow_run)
      end

      def self.process_with_openai(workflow_run, thread_data)
        log_with_context(workflow_run, "Starting OpenAI processing",
                         step: "openai_processing_started",
                         thread_message_count: thread_data[:replies]&.length || 0)

        openai_service = Openai::Service.new

        result = openai_service.transform_content(
          template: workflow_run.template,
          thread_data: thread_data,
          custom_prompt: nil
        )

        if result.success?
          model_used = openai_service.model
          log_with_context(workflow_run, "OpenAI processing completed",
                           step: "openai_processing_completed",
                           model_used: model_used,
                           content_length: result.data.length)
          Result.success({ content: result.data, model: model_used })
        else
          openai_error = Openai::Error.new(
            "OpenAI service returned error: #{result.error}",
            context: { component: "orchestrator_openai", workflow_run_id: workflow_run.id }
          )
          log_with_context(workflow_run, "OpenAI processing failed",
                           step: "openai_processing_failed", error: openai_error.message, level: :error)
          Result.failure(openai_error)
        end
      rescue ApplicationError => e
        ErrorHandler.log_error(e, level: :error)
        Result.failure(e)
      rescue StandardError => e
        standardized = ErrorHandler.standardize_error(e,
          context: { component: "orchestrator_openai", workflow_run_id: workflow_run.id },
          service: "openai")
        ErrorHandler.log_error(standardized, level: :error)
        Result.failure(standardized)
      end

      def self.process_with_notion(workflow_run, thread_data, openai_data)
        log_with_context(workflow_run, "Starting Notion processing",
                         step: "notion_processing_started",
                         database_id: workflow_run.template&.notion_database&.notion_database_id)

        notion_service = Notion::Service.new(max_retries: 3)
        result = notion_service.create_page_from_workflow(
          thread_data: thread_data,
          workflow_run: workflow_run,
          openai_data: openai_data
        )

        if result.success?
          log_with_context(workflow_run, "Notion processing completed",
                           step: "notion_processing_completed",
                           page_id: result.data[:id], page_url: result.data[:url])
          Result.success({
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
                         step: step_name, error: error_message, level: :error)
      end

      def self.log_with_context(workflow_run, message, step:, level: :info, **context)
        data = {
          workflow_run_id: workflow_run.id,
          step_name: step,
          service_class: name,
          workflow_name: workflow_run.workflow_name
        }.merge(context)

        case level
        when :error then Rails.logger.error("#{message} - #{data.to_json}")
        when :warn  then Rails.logger.warn("#{message} - #{data.to_json}")
        when :debug then Rails.logger.debug("#{message} - #{data.to_json}")
        else             Rails.logger.info("#{message} - #{data.to_json}")
        end
      end
    end
  end
end
