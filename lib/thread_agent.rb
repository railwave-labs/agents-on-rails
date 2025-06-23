# frozen_string_literal: true

require_relative "thread_agent/result"

module ThreadAgent
  # Notion API timeout in seconds
  NOTION_TIMEOUT = 30

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configuration=(config)
      @configuration = config
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def config
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end

  class Configuration
    attr_accessor :slack_client_id, :slack_client_secret, :slack_signing_secret, :slack_bot_token,
                  :openai_api_key, :openai_model,
                  :notion_client_id, :notion_client_secret, :notion_token,
                  :default_timeout, :max_retries

    def initialize
      @slack_client_id = ENV.fetch("THREAD_AGENT_SLACK_CLIENT_ID", nil)
      @slack_client_secret = ENV.fetch("THREAD_AGENT_SLACK_CLIENT_SECRET", nil)
      @slack_signing_secret = ENV.fetch("THREAD_AGENT_SLACK_SIGNING_SECRET", nil)
      @slack_bot_token = ENV.fetch("THREAD_AGENT_SLACK_BOT_TOKEN", nil)
      @openai_api_key = ENV.fetch("THREAD_AGENT_OPENAI_API_KEY", nil)
      @openai_model = ENV.fetch("THREAD_AGENT_OPENAI_MODEL", "gpt-4o-mini")
      @notion_client_id = ENV.fetch("THREAD_AGENT_NOTION_CLIENT_ID", nil)
      @notion_client_secret = ENV.fetch("THREAD_AGENT_NOTION_CLIENT_SECRET", nil)
      @notion_token = ENV.fetch("THREAD_AGENT_NOTION_TOKEN", nil)
      @default_timeout = ENV.fetch("THREAD_AGENT_DEFAULT_TIMEOUT", "30").to_i
      @max_retries = ENV.fetch("THREAD_AGENT_MAX_RETRIES", "3").to_i
    end

    def slack_configured?
      !slack_client_id.nil? && !slack_client_id.empty? &&
        !slack_client_secret.nil? && !slack_client_secret.empty? &&
        !slack_signing_secret.nil? && !slack_signing_secret.empty?
    end

    def openai_configured?
      !openai_api_key.nil? && !openai_api_key.empty?
    end

    def notion_configured?
      !notion_token.nil? && !notion_token.empty?
    end

    def fully_configured?
      slack_configured? && openai_configured? && notion_configured?
    end
  end

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class SlackError < Error; end
  class OpenaiError < Error; end
  class NotionError < Error; end
end
