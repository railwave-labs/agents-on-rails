# frozen_string_literal: true

module Notion
  class DatabaseService
    attr_reader :notion_client, :retry_handler

    def initialize(notion_client, retry_handler)
      @notion_client = notion_client
      @retry_handler = retry_handler
    end

    # List databases accessible to the Notion integration
    # Uses the /search endpoint with database filter as the dedicated list endpoint is deprecated
    # @param workspace_id [String, nil] Optional workspace filter (for future use if needed)
    # @return [Result] Result object with array of database data or error
    def list_databases(workspace_id: nil)
      begin
        databases = []
        cursor = nil

        # Paginate through all databases
        loop do
          response = retry_handler.retry_with do
            notion_client.client.search(
              filter: { property: "object", value: "database" },
              start_cursor: cursor
            )
          end

          databases.concat(response["results"])
          break unless response["has_more"]
          cursor = response["next_cursor"]
        end

        # Transform API payload into NotionDatabase compatible format
        transformed_databases = databases.map do |db|
          DataTransformer.transform_database_from_api(db, workspace_id)
        end

        Result.success(transformed_databases)
      rescue Notion::Error => e
        Result.failure(e.message)
      rescue StandardError => e
        Result.failure("Unexpected error: #{e.message}")
      end
    end

    # Get a specific database by ID with full property information
    # @param database_id [String] The Notion database ID
    # @return [Result] Result object with database data or error
    def get_database(database_id)
      return Result.failure("Missing database_id") if database_id.blank?

      begin
        response = retry_handler.retry_with do
          notion_client.client.database(database_id: database_id)
        end

        # Transform API payload into NotionDatabase compatible format
        transformed_database = DataTransformer.transform_database_from_api(response)

        Result.success(transformed_database)
      rescue Notion::Error => e
        Result.failure(e.message)
      rescue StandardError => e
        Result.failure("Unexpected error: #{e.message}")
      end
    end
  end
end
