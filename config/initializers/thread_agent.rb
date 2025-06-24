# frozen_string_literal: true

Rails.application.config.to_prepare do
  ThreadAgent.configure do |config|
    config.slack_client_id = ENV.fetch("THREAD_AGENT_SLACK_CLIENT_ID", nil)
    config.slack_client_secret = ENV.fetch("THREAD_AGENT_SLACK_CLIENT_SECRET", nil)
    config.slack_signing_secret = ENV.fetch("THREAD_AGENT_SLACK_SIGNING_SECRET", nil)
    config.slack_bot_token = ENV.fetch("THREAD_AGENT_SLACK_BOT_TOKEN", nil)

    config.openai_api_key = ENV.fetch("THREAD_AGENT_OPENAI_API_KEY", nil)
    config.openai_model = ENV.fetch("THREAD_AGENT_OPENAI_MODEL", "gpt-4o-mini")

    config.notion_client_id = ENV.fetch("THREAD_AGENT_NOTION_CLIENT_ID", nil)
    config.notion_client_secret = ENV.fetch("THREAD_AGENT_NOTION_CLIENT_SECRET", nil)
    config.notion_token = ENV.fetch("THREAD_AGENT_NOTION_TOKEN", nil)

    config.default_timeout = ENV.fetch("THREAD_AGENT_DEFAULT_TIMEOUT", "30").to_i
    config.max_retries = ENV.fetch("THREAD_AGENT_MAX_RETRIES", "3").to_i
  end
  if Rails.env.development?
    Rails.logger.info "ThreadAgent Configuration Status:"
    Rails.logger.info "  - Slack configured: #{ThreadAgent.configuration.slack_configured?}"
    Rails.logger.info "  - OpenAI configured: #{ThreadAgent.configuration.openai_configured?}"
    Rails.logger.info "  - Notion configured: #{ThreadAgent.configuration.notion_configured?}"
    Rails.logger.info "  - Fully configured: #{ThreadAgent.configuration.fully_configured?}"
  end
end
