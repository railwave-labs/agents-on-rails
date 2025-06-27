# frozen_string_literal: true

module ThreadAgent
  module Slack
    class WorkflowValidator
      REQUIRED_FIELDS = %w[channel_id thread_ts].freeze
      THREAD_DATA_FIELDS = %w[parent_message replies].freeze

      # Validate workflow input and structure for processing
      # @param workflow_run [WorkflowRun] The workflow run to validate
      # @return [ThreadAgent::Result] Result object with validation success or error
      def self.validate_workflow_input(workflow_run)
        return validate_workflow_run_fields(workflow_run) if workflow_run.input_data.blank?

        parse_result = parse_input_data(workflow_run.input_data)
        return parse_result if parse_result.failure?

        validate_parsed_input_data(parse_result.data)
      end

      # Parse input data from string or hash
      # @param input_data [String, Hash] The input data to parse
      # @return [ThreadAgent::Result] Result object with parsed data or error
      def self.parse_input_data(input_data)
        return success_result({}) if input_data.blank?

        parsed_data = input_data.is_a?(String) ? JSON.parse(input_data) : input_data
        success_result(parsed_data)
      rescue JSON::ParserError => e
        parsing_error("Invalid input data format: #{e.message}")
      end

      # Validate thread data structure for OpenAI processing
      # @param thread_data [Hash] The thread data to validate
      # @return [ThreadAgent::Result] Result object with validation success or error
      def self.validate_thread_data_structure(thread_data)
        normalized_data = normalize_thread_data(thread_data)

        return structure_error("Thread data must be a hash") unless normalized_data.is_a?(Hash)
        return structure_error("Thread data missing required parent_message") unless normalized_data[:parent_message].present?
        return structure_error("Thread data missing required replies array") unless normalized_data[:replies].is_a?(Array)

        success_result("Valid thread data structure")
      end

      def self.validate_workflow_run_fields(workflow_run)
        return workflow_run_field_error unless has_required_slack_fields?(workflow_run)

        success_result("Valid workflow_run with slack fields")
      end

      def self.validate_parsed_input_data(input_data)
        return input_data_error("Input data is empty") if input_data.empty?

        thread_data = extract_thread_data(input_data)
        return validate_thread_data_structure(thread_data) if thread_data

        validate_api_fetch_requirements(input_data)
      end

      def self.validate_api_fetch_requirements(input_data)
        channel_id = extract_field(input_data, "channel_id")
        thread_ts = extract_field(input_data, "thread_ts")

        return missing_fetch_fields_error if channel_id.blank? || thread_ts.blank?

        success_result("Valid input data for API fetch")
      end

      def self.has_required_slack_fields?(workflow_run)
        workflow_run.slack_channel_id.present? && workflow_run.slack_thread_ts.present?
      end

      def self.extract_thread_data(input_data)
        extract_field(input_data, "thread_data")
      end

      def self.extract_field(data, field_name)
        data[field_name.to_sym] || data[field_name]
      end

      def self.normalize_thread_data(thread_data)
        return thread_data unless thread_data.respond_to?(:deep_symbolize_keys)

        thread_data.deep_symbolize_keys
      end

      # Error creation helpers
      def self.workflow_run_field_error
        input_data_error("Missing input data and workflow_run doesn't have slack channel/thread info")
      end

      def self.missing_fetch_fields_error
        input_data_error("Input data missing required thread_data or channel_id/thread_ts for API fetch")
      end

      def self.input_data_error(message)
        create_error(message, "input_data")
      end

      def self.parsing_error(message)
        create_error(message, "input_data_parsing")
      end

      def self.structure_error(message)
        create_error(message, "thread_data_structure")
      end

      def self.create_error(message, validation_type)
        error = ThreadAgent::OpenaiError.new(
          message,
          context: { component: "workflow_validator", validation_type: validation_type }
        )
        ThreadAgent::Result.failure(error)
      end

      def self.success_result(message)
        ThreadAgent::Result.success(message)
      end

      private_class_method :validate_workflow_run_fields,
                           :validate_parsed_input_data,
                           :validate_api_fetch_requirements,
                           :has_required_slack_fields?,
                           :extract_thread_data,
                           :extract_field,
                           :normalize_thread_data,
                           :workflow_run_field_error,
                           :missing_fetch_fields_error,
                           :input_data_error,
                           :parsing_error,
                           :structure_error,
                           :create_error,
                           :success_result
    end
  end
end
