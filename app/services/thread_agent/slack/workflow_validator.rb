# frozen_string_literal: true

module ThreadAgent
  module Slack
    class WorkflowValidator
      # Validate workflow input and structure for processing
      # @param workflow_run [WorkflowRun] The workflow run to validate
      # @return [ThreadAgent::Result] Result object with validation success or error
      def self.validate_workflow_input(workflow_run)
        # First check if we have input_data at all
        if workflow_run.input_data.blank?
          # If no input_data, we need channel_id and thread_ts from workflow_run directly
          if workflow_run.slack_channel_id.blank? || workflow_run.slack_thread_ts.blank?
            return ThreadAgent::Result.failure("Missing input data and workflow_run doesn't have slack channel/thread info")
          end
          return ThreadAgent::Result.success("Valid workflow_run with slack fields")
        end

        # Parse and validate input_data structure
        parse_result = parse_input_data(workflow_run.input_data)
        return parse_result if parse_result.failure?

        input_data = parse_result.data

        # Check if it's completely empty
        if input_data.empty?
          return ThreadAgent::Result.failure("Input data is empty")
        end

        # Check for thread_data specifically
        thread_data = input_data[:thread_data] || input_data["thread_data"]

        if thread_data
          validate_thread_data_structure(thread_data)
        else
          # If no thread_data, check for channel_id/thread_ts for API fetch
          channel_id = input_data[:channel_id] || input_data["channel_id"]
          thread_ts = input_data[:thread_ts] || input_data["thread_ts"]

          if channel_id.blank? || thread_ts.blank?
            return ThreadAgent::Result.failure("Input data missing required thread_data or channel_id/thread_ts for API fetch")
          end

          ThreadAgent::Result.success("Valid input data for API fetch")
        end
      end

      # Parse input data from string or hash
      # @param input_data [String, Hash] The input data to parse
      # @return [ThreadAgent::Result] Result object with parsed data or error
      def self.parse_input_data(input_data)
        return ThreadAgent::Result.success({}) if input_data.blank?

        parsed_data = if input_data.is_a?(String)
          JSON.parse(input_data)
        else
          input_data
        end

        ThreadAgent::Result.success(parsed_data)
      rescue JSON::ParserError => e
        ThreadAgent::Result.failure("Invalid input data format: #{e.message}")
      end

      # Validate thread data structure for OpenAI processing
      # @param thread_data [Hash] The thread data to validate
      # @return [ThreadAgent::Result] Result object with validation success or error
      def self.validate_thread_data_structure(thread_data)
        # Convert to hash with symbolized keys for validation
        thread_data = thread_data.deep_symbolize_keys if thread_data.respond_to?(:deep_symbolize_keys)

        # Validate required structure for OpenAI processing
        unless thread_data.is_a?(Hash)
          return ThreadAgent::Result.failure("Thread data must be a hash")
        end

        unless thread_data[:parent_message].present?
          return ThreadAgent::Result.failure("Thread data missing required parent_message")
        end

        unless thread_data[:replies].is_a?(Array)
          return ThreadAgent::Result.failure("Thread data missing required replies array")
        end

        ThreadAgent::Result.success("Valid thread data structure")
      end
    end
  end
end
