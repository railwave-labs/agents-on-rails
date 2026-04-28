# frozen_string_literal: true

module Notion
  class ApiClient
    attr_reader :token, :timeout

    def initialize(token: nil, timeout: nil)
      @token = token || AppConfig.notion_token
      @timeout = timeout || AppConfig.default_timeout

      validate_configuration!
    end

    def client
      @client ||= initialize_client
    end

    private

    def initialize_client
      ::Notion::Client.new(
        token: token,
        timeout: timeout
      )
    rescue StandardError => e
      error = ErrorHandler.standardize_error(
        e,
        context: { component: "notion_client_initialization", timeout: timeout },
        service: "notion"
      )
      raise error
    end

    def validate_configuration!
      unless token.present?
        raise Notion::AuthError.new(
          "Missing Notion API token",
          context: { component: "notion_client_validation", timeout: timeout }
        )
      end
    end
  end
end
