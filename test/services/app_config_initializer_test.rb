# frozen_string_literal: true

require 'test_helper'

class AppConfigInitializerTest < ActiveSupport::TestCase
  setup do
    @original_env = {
      'THREAD_AGENT_DEFAULT_TIMEOUT'     => ENV['THREAD_AGENT_DEFAULT_TIMEOUT'],
      'THREAD_AGENT_MAX_RETRIES'         => ENV['THREAD_AGENT_MAX_RETRIES'],
      'THREAD_AGENT_OPENAI_MODEL'        => ENV['THREAD_AGENT_OPENAI_MODEL'],
      'THREAD_AGENT_OPENAI_API_KEY'      => ENV['THREAD_AGENT_OPENAI_API_KEY'],
      'THREAD_AGENT_SLACK_CLIENT_ID'     => ENV['THREAD_AGENT_SLACK_CLIENT_ID'],
      'THREAD_AGENT_SLACK_CLIENT_SECRET' => ENV['THREAD_AGENT_SLACK_CLIENT_SECRET'],
      'THREAD_AGENT_SLACK_SIGNING_SECRET' => ENV['THREAD_AGENT_SLACK_SIGNING_SECRET'],
      'THREAD_AGENT_SLACK_BOT_TOKEN'     => ENV['THREAD_AGENT_SLACK_BOT_TOKEN'],
      'THREAD_AGENT_NOTION_CLIENT_ID'    => ENV['THREAD_AGENT_NOTION_CLIENT_ID'],
      'THREAD_AGENT_NOTION_CLIENT_SECRET' => ENV['THREAD_AGENT_NOTION_CLIENT_SECRET'],
      'THREAD_AGENT_NOTION_TOKEN'        => ENV['THREAD_AGENT_NOTION_TOKEN']
    }
  end

  teardown do
    @original_env.each do |key, value|
      value ? ENV[key] = value : ENV.delete(key)
    end
    AppConfig.reset_from_env!
  end

  test "AppConfig is loaded and accessible" do
    assert_not_nil AppConfig.instance
    assert_instance_of AppConfig, AppConfig.instance
  end

  test "AppConfig responds to configuration check methods" do
    assert_respond_to AppConfig.instance, :slack_configured?
    assert_respond_to AppConfig.instance, :openai_configured?
    assert_respond_to AppConfig.instance, :notion_configured?
    assert_respond_to AppConfig.instance, :fully_configured?
  end

  test "AppConfig reads from environment variables" do
    ENV['THREAD_AGENT_DEFAULT_TIMEOUT'] = '60'
    ENV['THREAD_AGENT_OPENAI_MODEL']    = 'gpt-4'
    AppConfig.reset_from_env!

    assert_equal 60, AppConfig.default_timeout
    assert_equal 'gpt-4', AppConfig.openai_model
  end

  test "AppConfig has correct default values when env vars unset" do
    @original_env.keys.each { |k| ENV.delete(k) }
    AppConfig.reset_from_env!

    assert_equal 30, AppConfig.default_timeout
    assert_equal 3, AppConfig.max_retries
    assert_equal 'gpt-4o-mini', AppConfig.openai_model
  end
end
