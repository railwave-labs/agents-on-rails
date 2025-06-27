# frozen_string_literal: true

module ThreadAgent
  module Slack
    class ThreadProcessor
      attr_reader :slack_service

      def initialize(slack_service)
        @slack_service = slack_service
      end

      # Process workflow input to get thread data, handling both pre-formatted data and API fetch
      # @param workflow_run [WorkflowRun] The workflow run to process
      # @return [ThreadAgent::Result] Result object with thread data or error
      def process_workflow_input(workflow_run)
        Rails.logger.info("Processing workflow input for workflow_run: #{workflow_run.id}")

        begin
          input_data = extract_input_data(workflow_run)

          # Check if we already have pre-formatted thread data
          if input_data[:thread_data] || input_data["thread_data"]
            thread_data = input_data[:thread_data] || input_data["thread_data"]
            thread_data = thread_data.deep_symbolize_keys if thread_data.respond_to?(:deep_symbolize_keys)

            Rails.logger.info("Using pre-formatted thread data for workflow_run: #{workflow_run.id}")
            return ThreadAgent::Result.success(thread_data)
          end

          # Extract channel and thread info for API fetch
          channel_id = input_data[:channel_id] || input_data["channel_id"]
          thread_ts = input_data[:thread_ts] || input_data["thread_ts"]

          unless channel_id.present? && thread_ts.present?
            return ThreadAgent::Result.failure("Missing channel_id or thread_ts in workflow input")
          end

          # Fetch thread data using the service
          fetch_result = slack_service.fetch_thread(channel_id, thread_ts)

          if fetch_result.failure?
            return ThreadAgent::Result.failure("Failed to fetch Slack thread: #{fetch_result.error}")
          end

          Rails.logger.info("Slack thread fetched successfully for workflow_run: #{workflow_run.id}")
          fetch_result

        rescue ThreadAgent::SlackError => e
          Rails.logger.error("Slack processing failed for workflow_run #{workflow_run.id}: #{e.message}")
          ThreadAgent::Result.failure("Slack processing failed: #{e.message}")
        rescue StandardError => e
          Rails.logger.error("Unexpected error during Slack processing for workflow_run #{workflow_run.id}: #{e.message}")
          ThreadAgent::Result.failure("Unexpected error: #{e.message}")
        end
      end

      private

      def extract_input_data(workflow_run)
        return {} if workflow_run.input_data.blank?

        if workflow_run.input_data.is_a?(String)
          JSON.parse(workflow_run.input_data)
        else
          workflow_run.input_data
        end
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse input_data: #{e.message}")
        {}
      end
    end
  end
end
