# frozen_string_literal: true

module Anthropic
  class ApiClient
    attr_reader :api_key, :model, :timeout

    def initialize(api_key: nil, model: nil, timeout: 30)
      @api_key = api_key || AppConfig.anthropic_api_key
      @model   = model   || AppConfig.anthropic_model
      @timeout = timeout

      validate_configuration!
    end

    # Creates a message via the Anthropic Messages API.
    # Returns an Anthropic::Message object; raises Anthropic::* errors on failure.
    def messages_create(**params)
      client.messages.create(params)
    rescue ::Anthropic::Errors::AuthenticationError => e
      raise Anthropic::AuthError.new(e.message, context: { component: "api_client" })
    rescue ::Anthropic::Errors::RateLimitError => e
      raise Anthropic::ApiRateLimitError.new(e.message, context: { component: "api_client" })
    rescue ::Anthropic::Errors::APIError => e
      raise Anthropic::Error.new(e.message, context: { component: "api_client" })
    rescue StandardError => e
      raise ErrorHandler.standardize_error(e, service: "anthropic", context: { component: "api_client" })
    end

    private

    def client
      @client ||= ::Anthropic::Client.new(
        api_key: api_key,
        timeout: timeout
      )
    end

    def validate_configuration!
      unless api_key.present?
        raise Anthropic::AuthError.new(
          "Missing Anthropic API key",
          context: { component: "anthropic_client_validation", model: model }
        )
      end

      unless model.present?
        raise ::ConfigurationError.new(
          "Missing Anthropic model configuration",
          context: { component: "anthropic_client_validation", api_key_present: api_key.present? }
        )
      end
    end
  end
end
