# frozen_string_literal: true

require 'singleton'

class AppConfig
  include Singleton

  attr_accessor :slack_client_id, :slack_client_secret, :slack_signing_secret, :slack_bot_token,
                :openai_api_key, :openai_model,
                :notion_client_id, :notion_client_secret, :notion_token,
                :anthropic_api_key, :anthropic_model,
                :default_timeout, :max_retries

  def self.method_missing(name, *args, &block)
    instance.respond_to?(name) ? instance.send(name, *args, &block) : super
  end

  def self.respond_to_missing?(name, include_private = false)
    instance.respond_to?(name) || super
  end

  def slack_configured?
    !slack_signing_secret.nil? && !slack_signing_secret.empty? &&
      !slack_client_id.nil? && !slack_client_id.empty? &&
      !slack_client_secret.nil? && !slack_client_secret.empty?
  end

  def openai_configured?
    !openai_api_key.nil? && !openai_api_key.empty?
  end

  def notion_configured?
    oauth_configured = !notion_client_id.nil? && !notion_client_id.empty? &&
                       !notion_client_secret.nil? && !notion_client_secret.empty?
    token_configured = !notion_token.nil? && !notion_token.empty?

    oauth_configured || token_configured
  end

  def anthropic_configured?
    !anthropic_api_key.nil? && !anthropic_api_key.empty?
  end

  def fully_configured?
    slack_configured? && openai_configured? && notion_configured?
  end

  def self.reset_from_env!
    instance.slack_client_id     = ENV.fetch('THREAD_AGENT_SLACK_CLIENT_ID', nil)
    instance.slack_client_secret = ENV.fetch('THREAD_AGENT_SLACK_CLIENT_SECRET', nil)
    instance.slack_signing_secret = ENV.fetch('THREAD_AGENT_SLACK_SIGNING_SECRET', nil)
    instance.slack_bot_token     = ENV.fetch('THREAD_AGENT_SLACK_BOT_TOKEN', nil)
    instance.openai_api_key      = ENV.fetch('THREAD_AGENT_OPENAI_API_KEY', nil)
    instance.openai_model        = ENV.fetch('THREAD_AGENT_OPENAI_MODEL', 'gpt-4o-mini')
    instance.notion_client_id    = ENV.fetch('THREAD_AGENT_NOTION_CLIENT_ID', nil)
    instance.notion_client_secret = ENV.fetch('THREAD_AGENT_NOTION_CLIENT_SECRET', nil)
    instance.notion_token        = ENV.fetch('THREAD_AGENT_NOTION_TOKEN', nil)
    instance.anthropic_api_key   = ENV.fetch('ANTHROPIC_API_KEY', nil)
    instance.anthropic_model     = ENV.fetch('ANTHROPIC_MODEL', 'claude-sonnet-4-5')
    instance.default_timeout     = ENV.fetch('THREAD_AGENT_DEFAULT_TIMEOUT', '30').to_i
    instance.max_retries         = ENV.fetch('THREAD_AGENT_MAX_RETRIES', '3').to_i
  end
end
