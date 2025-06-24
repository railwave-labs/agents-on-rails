# frozen_string_literal: true

module ThreadAgent
  module Notion
    class Client
      attr_reader :token, :timeout

      def initialize(token: nil, timeout: nil)
        @token = token || ThreadAgent.configuration.notion_token
        @timeout = timeout || ThreadAgent.configuration.default_timeout

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
        raise ThreadAgent::NotionError, "Failed to initialize Notion client: #{e.message}"
      end

      def validate_configuration!
        unless token.present?
          raise ThreadAgent::NotionError, "Missing Notion API token"
        end
      end
    end
  end
end
