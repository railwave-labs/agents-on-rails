# frozen_string_literal: true

module ThreadAgent
  module Openai
    class Client
      attr_reader :api_key, :model, :timeout

      def initialize(api_key: nil, model: nil, timeout: 20)
        @api_key = api_key || ThreadAgent.configuration.openai_api_key
        @model = model || ThreadAgent.configuration.openai_model
        @timeout = timeout

        validate_configuration!
      end

      def client
        @client ||= initialize_client
      end

      private

      def initialize_client
        OpenAI::Client.new(
          access_token: api_key,
          request_timeout: timeout
        )
      rescue StandardError => e
        raise ThreadAgent::OpenaiError, "Failed to initialize OpenAI client: #{e.message}"
      end

      def validate_configuration!
        unless api_key.present?
          raise ThreadAgent::OpenaiError, "Missing OpenAI API key"
        end

        unless model.present?
          raise ThreadAgent::OpenaiError, "Missing OpenAI model configuration"
        end
      end
    end
  end
end
