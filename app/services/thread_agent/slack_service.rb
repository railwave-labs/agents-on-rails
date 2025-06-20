# frozen_string_literal: true

module ThreadAgent
  class SlackService
    attr_reader :bot_token

    def initialize(bot_token: nil)
      @bot_token = bot_token || ThreadAgent.configuration.slack_bot_token
      validate_configuration!
    end

    private

    def validate_configuration!
      unless bot_token.present?
        raise ThreadAgent::SlackError, "Missing Slack bot token"
      end
    end
  end
end
