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
        error = ThreadAgent::ErrorHandler.standardize_error(
          e,
          context: { component: "openai_client_initialization", model: model, timeout: timeout },
          service: "openai"
        )
        raise error
      end

      def validate_configuration!
        unless api_key.present?
          raise ThreadAgent::OpenaiAuthError.new(
            "Missing OpenAI API key",
            context: { component: "openai_client_validation", model: model }
          )
        end

        unless model.present?
          raise ThreadAgent::ConfigurationError.new(
            "Missing OpenAI model configuration",
            context: { component: "openai_client_validation", api_key_present: api_key.present? }
          )
        end
      end
    end
  end
end
