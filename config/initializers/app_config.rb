# frozen_string_literal: true

Rails.application.config.to_prepare do
  config = AppConfig.instance

  config.slack_client_id = ENV.fetch('THREAD_AGENT_SLACK_CLIENT_ID', nil)
  config.slack_client_secret = ENV.fetch('THREAD_AGENT_SLACK_CLIENT_SECRET', nil)
  config.slack_signing_secret = ENV.fetch('THREAD_AGENT_SLACK_SIGNING_SECRET', nil)
  config.slack_bot_token = ENV.fetch('THREAD_AGENT_SLACK_BOT_TOKEN', nil)

  config.openai_api_key = ENV.fetch('THREAD_AGENT_OPENAI_API_KEY', nil)
  config.openai_model = ENV.fetch('THREAD_AGENT_OPENAI_MODEL', 'gpt-4o-mini')

  config.notion_client_id = ENV.fetch('THREAD_AGENT_NOTION_CLIENT_ID', nil)
  config.notion_client_secret = ENV.fetch('THREAD_AGENT_NOTION_CLIENT_SECRET', nil)
  config.notion_token = ENV.fetch('THREAD_AGENT_NOTION_TOKEN', nil)

  config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
  config.anthropic_model   = ENV.fetch('ANTHROPIC_MODEL', 'claude-sonnet-4-5')

  config.default_timeout = ENV.fetch('THREAD_AGENT_DEFAULT_TIMEOUT', '30').to_i
  config.max_retries = ENV.fetch('THREAD_AGENT_MAX_RETRIES', '3').to_i

  if Rails.env.development?
    Rails.logger.info 'AppConfig status:'
    Rails.logger.info "  - Slack configured: #{config.slack_configured?}"
    Rails.logger.info "  - OpenAI configured: #{config.openai_configured?}"
    Rails.logger.info "  - Notion configured: #{config.notion_configured?}"
    Rails.logger.info "  - Anthropic configured: #{config.anthropic_configured?}"
    Rails.logger.info "  - Fully configured: #{config.fully_configured?}"
  end
end
