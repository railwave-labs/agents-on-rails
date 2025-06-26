# frozen_string_literal: true

module ThreadAgent
  module Openai
    class Service
      DEFAULT_TIMEOUT = 20

      attr_reader :openai_client, :message_builder, :retry_handler

      def initialize(api_key: nil, model: nil, timeout: DEFAULT_TIMEOUT, max_retries: 3)
        @openai_client = Client.new(
          api_key: api_key,
          model: model,
          timeout: timeout
        )
        @message_builder = MessageBuilder
        @retry_handler = RetryHandler.new(max_attempts: max_retries)
      end

      # Delegate configuration attributes to openai_client
      def api_key
        openai_client.api_key
      end

      def model
        openai_client.model
      end

      def timeout
        openai_client.timeout
      end

      # Delegate client access to openai_client
      def client
        openai_client.client
      end

      # Delegate message building to message_builder
      def build_messages(template: nil, thread_data:, custom_prompt: nil)
        message_builder.build_messages(template: template, thread_data: thread_data, custom_prompt: custom_prompt)
      end

      # Delegate permalink generation to message_builder
      def slack_permalink(channel_id, thread_ts)
        message_builder.slack_permalink(channel_id, thread_ts)
      end

      # Transform thread content using OpenAI
      # @param template [Template, nil] Optional template for custom system prompt
      # @param thread_data [Hash] Slack thread data with parent_message, replies, etc.
      # @param custom_prompt [String, nil] Optional custom prompt from user input
      # @return [ThreadAgent::Result] Result object with success/failure and data
      def transform_content(template: nil, thread_data:, custom_prompt: nil)
        validate_transform_inputs!(thread_data)

        messages = build_messages(template: template, thread_data: thread_data, custom_prompt: custom_prompt)
        response = make_openai_request(messages)

        content = extract_content_from_response(response)
        ThreadAgent::Result.success(content)
      rescue ThreadAgent::Error => e
        # Already a standardized error, just convert to result
        ThreadAgent::ErrorHandler.to_result(e, service: "openai")
      rescue StandardError => e
        ThreadAgent::ErrorHandler.to_result(
          e,
          context: {
            component: "content_transformation",
            model: model,
            template_present: !template.nil?,
            custom_prompt_present: !custom_prompt.nil?
          },
          service: "openai"
        )
      end

      private

      # Content transformation helper methods
      def validate_transform_inputs!(thread_data)
        unless thread_data.is_a?(Hash) && thread_data.key?(:parent_message)
          raise ThreadAgent::ValidationError.new(
            "Invalid thread_data: must be a hash with parent_message",
            context: {
              component: "input_validation",
              thread_data_type: thread_data.class.name,
              thread_data_keys: thread_data.is_a?(Hash) ? thread_data.keys : nil
            }
          )
        end
      end

      def make_openai_request(messages)
        retry_handler.retry_with do
          client.chat(
            parameters: {
              model: model,
              messages: messages,
              max_tokens: 1000,
              temperature: 0.7
            }
          )
        end
      rescue StandardError => e
        error = ThreadAgent::ErrorHandler.standardize_error(
          e,
          context: {
            component: "openai_api_request",
            model: model,
            message_count: messages&.length
          },
          service: "openai"
        )
        raise error
      end

      def extract_content_from_response(response)
        content = response.dig("choices", 0, "message", "content")

        unless content.present?
          raise ThreadAgent::ValidationError.new(
            "Invalid response from OpenAI: missing content",
            context: {
              component: "response_extraction",
              response_structure: response.keys,
              choices_present: response.key?("choices"),
              choices_count: response["choices"]&.length
            }
          )
        end

        content.strip
      end
    end
  end
end
