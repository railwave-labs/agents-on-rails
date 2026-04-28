# frozen_string_literal: true

module Agents
  module Triage
    class StructuredResponse
      ALLOWED_SEVERITIES = %w[info low medium high critical].freeze

      Payload = Data.define(:severity, :hypothesis, :suggested_next_step, :context_links, :confidence)

      def self.parse(text)
        json    = extract_json(text)
        parsed  = JSON.parse(json)
        validate!(parsed)
        Payload.new(
          severity:           parsed["severity"],
          hypothesis:         parsed["hypothesis"],
          suggested_next_step: parsed["suggested_next_step"],
          context_links:      Array(parsed["context_links"]),
          confidence:         parsed["confidence"].to_f
        )
      rescue JSON::ParserError => e
        raise ServiceParseError.new(
          "Failed to parse triage JSON: #{e.message}",
          context: { raw_text: text.to_s.truncate(500) }
        )
      end

      def self.extract_json(text)
        text[/```json\s*(\{.*?\})\s*```/m, 1] || text[/\{.*\}/m] || text
      end

      def self.validate!(parsed)
        raise ValidationError.new("missing or invalid severity — got #{parsed["severity"].inspect}") \
          unless ALLOWED_SEVERITIES.include?(parsed["severity"])
        raise ValidationError.new("missing hypothesis") if parsed["hypothesis"].to_s.strip.empty?
        raise ValidationError.new("missing suggested_next_step") if parsed["suggested_next_step"].to_s.strip.empty?

        confidence = parsed["confidence"].to_f
        raise ValidationError.new("invalid confidence #{confidence} — must be 0.0..1.0") \
          unless confidence.between?(0.0, 1.0)
      end
    end
  end
end
