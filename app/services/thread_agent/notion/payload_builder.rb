# frozen_string_literal: true

module ThreadAgent
  module Notion
    class PayloadBuilder
      # Build the complete payload for page creation
      # @param database_id [String] Target database ID
      # @param properties [Hash] Page properties
      # @param content [Array] Content blocks
      # @return [Hash] Complete payload for Notion API
      def self.build_page_payload(database_id, properties, content)
        {
          parent: { database_id: database_id },
          properties: map_properties(properties),
          children: build_children_blocks(content)
        }
      end

      # Map Ruby properties to Notion property format
      # @param properties [Hash] Input properties as Ruby primitives
      # @return [Hash] Notion-formatted properties
      def self.map_properties(properties)
        mapped = {}

        properties.each do |key, value|
          mapped[key.to_s] = case value
          when String
            # Default to title for string values, could be rich_text for other properties
            { "title" => [ { "text" => { "content" => value } } ] }
          when Symbol
            # Treat symbols as select values
            { "select" => { "name" => value.to_s } }
          when Date, Time, DateTime
            # Date property
            { "date" => { "start" => value.strftime("%Y-%m-%d") } }
          when TrueClass, FalseClass
            # Checkbox property
            { "checkbox" => value }
          when Array
            # Multi-select property
            { "multi_select" => value.map { |v| { "name" => v.to_s } } }
          when Hash
            # Allow raw Notion format if user provides it
            value
          else
            # Fallback to rich text for other types
            { "rich_text" => [ { "text" => { "content" => value.to_s } } ] }
          end
        end

        mapped
      end

      # Build children blocks from content array
      # @param content [Array<String, Hash>] Content items
      # @return [Array<Hash>] Notion block objects
      def self.build_children_blocks(content)
        return [] if content.nil? || content.empty?

        content.map do |item|
          case item
          when String
            build_paragraph_block(item)
          when Hash
            build_typed_block(item)
          else
            build_paragraph_block(item.to_s)
          end
        end.compact
      end

      # Build a paragraph block
      # @param text [String] Paragraph content
      # @return [Hash] Notion paragraph block
      def self.build_paragraph_block(text)
        {
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => {
            "rich_text" => [
              {
                "type" => "text",
                "text" => { "content" => text }
              }
            ]
          }
        }
      end

      # Build a typed block from hash specification
      # @param spec [Hash] Block specification with type and content
      # @return [Hash] Notion block object
      def self.build_typed_block(spec)
        type = spec[:type] || spec["type"] || "paragraph"
        content = spec[:content] || spec["content"] || ""

        case type.to_s
        when "bulleted_list_item", "bulleted_list"
          {
            "object" => "block",
            "type" => "bulleted_list_item",
            "bulleted_list_item" => {
              "rich_text" => [
                {
                  "type" => "text",
                  "text" => { "content" => content }
                }
              ]
            }
          }
        when "numbered_list_item", "numbered_list"
          {
            "object" => "block",
            "type" => "numbered_list_item",
            "numbered_list_item" => {
              "rich_text" => [
                {
                  "type" => "text",
                  "text" => { "content" => content }
                }
              ]
            }
          }
        when "heading_1"
          {
            "object" => "block",
            "type" => "heading_1",
            "heading_1" => {
              "rich_text" => [
                {
                  "type" => "text",
                  "text" => { "content" => content }
                }
              ]
            }
          }
        when "heading_2"
          {
            "object" => "block",
            "type" => "heading_2",
            "heading_2" => {
              "rich_text" => [
                {
                  "type" => "text",
                  "text" => { "content" => content }
                }
              ]
            }
          }
        when "to_do"
          {
            "object" => "block",
            "type" => "to_do",
            "to_do" => {
              "rich_text" => [
                {
                  "type" => "text",
                  "text" => { "content" => content }
                }
              ],
              "checked" => spec[:checked] || spec["checked"] || false
            }
          }
        else
          # Default to paragraph for unknown types
          build_paragraph_block(content)
        end
      end
    end
  end
end
