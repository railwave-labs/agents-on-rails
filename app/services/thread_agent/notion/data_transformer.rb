# frozen_string_literal: true

module ThreadAgent
  module Notion
    class DataTransformer
      # Transform Notion API database response into format compatible with NotionDatabase model
      # @param api_response [Hash] Raw API response from Notion
      # @param workspace_id [String, nil] Optional workspace ID to associate
      # @return [Hash] Transformed database data
      def self.transform_database_from_api(api_response, workspace_id = nil)
        {
          notion_database_id: api_response["id"],
          name: extract_title_from_notion_response(api_response["title"]),
          properties: extract_properties_from_response(api_response["properties"]),
          json_data: api_response,
          workspace_id: workspace_id
        }
      end

      # Transform page creation response to useful format
      # @param page_data [Hash] Response from Notion API
      # @return [Hash] Transformed page data
      def self.transform_page_response(page_data)
        {
          id: page_data["id"],
          url: page_data["url"],
          title: extract_page_title(page_data),
          created_time: page_data["created_time"],
          properties: page_data["properties"]
        }
      end

      # Extract plain text from Notion title array
      # @param title_array [Array] Notion title array with rich text objects
      # @return [String] Plain text title
      def self.extract_title_from_notion_response(title_array)
        return "Untitled" if title_array.blank?

        title_array.map do |title_obj|
          title_obj["plain_text"] || title_obj["text"]&.dig("content") || ""
        end.join.strip.presence || "Untitled"
      end

      # Extract and simplify properties hash for storage
      # @param properties_hash [Hash] Notion properties hash
      # @return [Hash] Simplified properties with names and types
      def self.extract_properties_from_response(properties_hash)
        return {} if properties_hash.blank?

        properties_hash.transform_values do |property|
          {
            type: property["type"],
            id: property["id"]
          }
        end
      end

      # Extract page title from properties
      # @param page_data [Hash] Page data from API
      # @return [String] Page title
      def self.extract_page_title(page_data)
        return "Untitled" unless page_data["properties"]

        # Find the title property (first title-type property)
        title_property = page_data["properties"].find { |_, prop| prop["type"] == "title" }
        return "Untitled" unless title_property

        title_value = title_property[1]["title"]
        return "Untitled" unless title_value&.any?

        title_value.map { |t| t["text"]["content"] }.join
      rescue
        "Untitled"
      end
    end
  end
end
