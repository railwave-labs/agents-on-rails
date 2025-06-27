# frozen_string_literal: true

module ThreadAgent
  module Notion
    class ContentProcessor
      def self.process_ai_content(ai_content)
        content_blocks = []
        paragraphs = ai_content.split(/\n\s*\n/)

        paragraphs.each do |paragraph|
          next if paragraph.strip.empty?

          # Handle different content types with better structure
          if paragraph.strip.start_with?("•", "-", "*")
            process_bullet_list(paragraph, content_blocks)
          elsif paragraph.strip.match(/^\d+\./)
            process_numbered_list(paragraph, content_blocks)
          elsif paragraph.strip.start_with?("#")
            process_header(paragraph, content_blocks)
          else
            # Regular paragraph
            content_blocks << paragraph.strip
          end
        end

        content_blocks
      end

      private

      def self.process_bullet_list(paragraph, content_blocks)
        lines = paragraph.split("\n")
        lines.each do |line|
          next if line.strip.empty?
          clean_line = line.gsub(/^[\s•\-\*]+/, "").strip
          content_blocks << {
            type: "bulleted_list_item",
            content: clean_line
          }
        end
      end

      def self.process_numbered_list(paragraph, content_blocks)
        lines = paragraph.split("\n")
        lines.each do |line|
          next if line.strip.empty?
          clean_line = line.gsub(/^\s*\d+\.\s*/, "").strip
          content_blocks << {
            type: "numbered_list_item",
            content: clean_line
          }
        end
      end

      def self.process_header(paragraph, content_blocks)
        header_level = paragraph.match(/^#+/).to_s.length
        header_text = paragraph.gsub(/^#+\s*/, "").strip

        block_type = case header_level
        when 1 then "heading_1"
        when 2 then "heading_2"
        else "heading_3"
        end

        content_blocks << {
          type: block_type,
          content: header_text
        }
      end
    end
  end
end
