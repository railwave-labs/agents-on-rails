# frozen_string_literal: true

module ThreadAgent
  module Notion
    class PageService
      attr_reader :notion_client, :retry_handler

      def initialize(notion_client, retry_handler)
        @notion_client = notion_client
        @retry_handler = retry_handler
      end

      # Create a new page in a Notion database with properties and content
      # @param database_id [String] The database ID where the page will be created
      # @param properties [Hash] Key-value pairs for page properties
      # @param content [Array<String, Hash>] Content blocks for the page body
      # @return [ThreadAgent::Result] Result object with created page data or error
      def create_page(database_id:, properties: {}, content: [])
        return ThreadAgent::Result.failure("Missing database_id") if database_id.blank?

        begin
          payload = PayloadBuilder.build_page_payload(database_id, properties, content)

          page_data = retry_handler.retry_with do
            notion_client.client.create_page(payload)
          end

          # Transform response to include useful data
          result_data = DataTransformer.transform_page_response(page_data)
          ThreadAgent::Result.success(result_data)
        rescue ThreadAgent::NotionError => e
          Rails.logger.error "PageService create_page failed: #{e.message}"
          ThreadAgent::Result.failure(e.message)
        rescue StandardError => e
          Rails.logger.error "PageService create_page unexpected error: #{e.message}"
          ThreadAgent::Result.failure("Unexpected error: #{e.message}")
        end
      end
    end
  end
end
