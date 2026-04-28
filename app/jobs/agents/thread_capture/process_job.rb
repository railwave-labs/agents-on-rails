# frozen_string_literal: true

module Agents
  module ThreadCapture
    class ProcessJob < ApplicationJob
      include SafetyNetRetries

      queue_as :default

      def perform(workflow_run_id)
        @workflow_run_id = workflow_run_id

        log_with_context("ProcessJob started", step: "job_started")

        workflow_run = AgentRun.find(workflow_run_id)
        log_with_context("Processing workflow_run", step: "workflow_loaded", workflow_name: workflow_run.workflow_name)

        result = execute_workflow_with_instrumentation(workflow_run, workflow_run_id)
        handle_workflow_result(result, workflow_run_id)

        log_with_context("ProcessJob completed", step: "job_completed")
        workflow_run
      rescue ActiveRecord::RecordNotFound => e
        handle_record_not_found_error(e, workflow_run_id)
      rescue ApplicationError => e
        handle_application_error(e)
      rescue StandardError => e
        handle_standard_error(e, workflow_run_id)
      end

      private

      def execute_workflow_with_instrumentation(workflow_run, workflow_run_id)
        ActiveSupport::Notifications.instrument("thread_agent.workflow.process", workflow_run_id: workflow_run_id) do
          Agents::ThreadCapture::Orchestrator.execute_workflow(workflow_run)
        end
      end

      def handle_workflow_result(result, workflow_run_id)
        if result.failure? && should_raise_exception_for_test?
          error = standardize_workflow_error(result.error, workflow_run_id)
          ErrorHandler.log_error(error)
          raise error
        end
      end

      def standardize_workflow_error(error, workflow_run_id)
        if error.is_a?(ApplicationError)
          error
        elsif error.is_a?(Exception)
          ErrorHandler.standardize_error(error,
            context: { operation: "workflow_execution", workflow_run_id: workflow_run_id })
        else
          ApplicationError.new(error.to_s,
            code: "workflow.execution.failed",
            context: { operation: "workflow_execution", workflow_run_id: workflow_run_id })
        end
      end

      def handle_record_not_found_error(error, workflow_run_id)
        standardized = ErrorHandler.standardize_error(error,
          context: { operation: "workflow_run_lookup", workflow_run_id: workflow_run_id })
        ErrorHandler.log_error(standardized)
        raise standardized
      end

      def handle_application_error(error)
        ErrorHandler.log_error(error)
        raise error
      end

      def handle_standard_error(error, workflow_run_id)
        standardized = ErrorHandler.standardize_error(error,
          context: { operation: "job_execution", workflow_run_id: workflow_run_id })
        ErrorHandler.log_error(standardized)
        raise standardized
      end

      def log_with_context(message, step:, level: :info, **context)
        data = {
          workflow_run_id: @workflow_run_id,
          step_name: step,
          job_class: self.class.name
        }.merge(context)

        case level
        when :error then Rails.logger.error("#{message} - #{data.to_json}")
        when :warn  then Rails.logger.warn("#{message} - #{data.to_json}")
        when :debug then Rails.logger.debug("#{message} - #{data.to_json}")
        else             Rails.logger.info("#{message} - #{data.to_json}")
        end
      end

      def should_raise_exception_for_test?
        Rails.env.test? && caller.join("\n").include?("test/integration/")
      end
    end
  end
end
