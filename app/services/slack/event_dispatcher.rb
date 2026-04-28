# frozen_string_literal: true

module Slack
  class EventDispatcher
    def self.dispatch(payload)
      event = payload["event"] || {}
      return Result.success(:ignored) unless event["type"] == "message"
      return Result.success(:ignored) if event["bot_id"].present? || event["subtype"] == "bot_message"

      channel_id = event["channel"]
      return Result.success(:ignored) unless triage_channels.include?(channel_id)

      Agents::Triage::AnalyzeJob.perform_later(slack_event_payload: payload)
      Result.success(:enqueued_triage)
    end

    def self.triage_channels
      (ENV.fetch("TRIAGE_ALERT_SLACK_CHANNEL_IDS", "")).split(",").map(&:strip).reject(&:empty?)
    end
  end
end
