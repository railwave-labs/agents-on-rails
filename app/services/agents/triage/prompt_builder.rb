# frozen_string_literal: true

module Agents
  module Triage
    class PromptBuilder
      OUTPUT_SCHEMA_INSTRUCTION = <<~INSTRUCTION.strip
        When you have gathered enough context, your final reply MUST be a single JSON object with this exact shape, and nothing else:

        ```json
        {
          "severity": "info" | "low" | "medium" | "high" | "critical",
          "hypothesis": "<one paragraph describing root cause and evidence>",
          "suggested_next_step": "<one short imperative sentence>",
          "context_links": ["<url>", ...],
          "confidence": <0.0..1.0>
        }
        ```

        Do not include any text before or after the JSON object.
      INSTRUCTION

      TOOL_USE_GUIDANCE = <<~GUIDANCE.strip
        Use the Sentry MCP and GitHub MCP servers to investigate before drawing conclusions.
        Do not speculate without checking the available tools first.
      GUIDANCE

      def self.build(agent_run:)
        event = extract_event(agent_run)
        new(event: event).build
      end

      def initialize(event:)
        @event = event
      end

      def build
        {
          system: system_prompt,
          messages: [ { role: "user", content: user_prompt } ]
        }
      end

      private

      def system_prompt
        playbook = PlaybookLoader.load
        [playbook, OUTPUT_SCHEMA_INSTRUCTION, TOOL_USE_GUIDANCE].join("\n\n---\n\n")
      end

      def user_prompt
        channel  = @event["channel"].to_s
        ts       = @event["ts"].to_s
        text     = @event["text"].to_s
        permalink = slack_permalink(channel, ts)

        <<~PROMPT.strip
          A new alert has appeared in the Slack alerts channel.

          Channel: #{channel}
          Timestamp: #{ts}
          Permalink: #{permalink}

          Message:
          #{text}

          Please investigate using the available MCP tools and produce a triage assessment.
        PROMPT
      end

      def slack_permalink(channel, ts)
        return "(no permalink — channel or ts missing)" if channel.blank? || ts.blank?

        safe_ts = ts.tr(".", "-")
        "https://slack.com/archives/#{channel}/p#{safe_ts}"
      end

      def self.extract_event(agent_run)
        input = agent_run.input_data || {}
        input.dig("slack_event", "event") || input["event"] || {}
      end
    end
  end
end
