# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# ThreadAgent Configuration
# Configure ThreadAgent for integration with Slack, OpenAI, and Notion services.
# All sensitive configuration should be provided via environment variables.

Rails.application.config.to_prepare do
  # Configure ThreadAgent with environment variables
  ThreadAgent.configure do |config|
    # Slack configuration
    config.slack_client_id = ENV["THREAD_AGENT_SLACK_CLIENT_ID"]
    config.slack_client_secret = ENV["THREAD_AGENT_SLACK_CLIENT_SECRET"]
    config.slack_signing_secret = ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"]

    # OpenAI configuration
    config.openai_api_key = ENV["THREAD_AGENT_OPENAI_API_KEY"]
    config.openai_model = ENV.fetch("THREAD_AGENT_OPENAI_MODEL", "gpt-4o-mini")

    # Notion configuration
    config.notion_client_id = ENV["THREAD_AGENT_NOTION_CLIENT_ID"]
    config.notion_client_secret = ENV["THREAD_AGENT_NOTION_CLIENT_SECRET"]

    # Operational configuration
    config.default_timeout = ENV.fetch("THREAD_AGENT_DEFAULT_TIMEOUT", "30").to_i
    config.max_retries = ENV.fetch("THREAD_AGENT_MAX_RETRIES", "3").to_i
  end

  # Optional: Log configuration status in development
  if Rails.env.development?
    Rails.logger.info "ThreadAgent initialized"
    Rails.logger.info "  - Slack configured: #{ThreadAgent.configuration.slack_configured?}"
    Rails.logger.info "  - OpenAI configured: #{ThreadAgent.configuration.openai_configured?}"
    Rails.logger.info "  - Notion configured: #{ThreadAgent.configuration.notion_configured?}"
    Rails.logger.info "  - Fully configured: #{ThreadAgent.configuration.fully_configured?}"
  end
end
