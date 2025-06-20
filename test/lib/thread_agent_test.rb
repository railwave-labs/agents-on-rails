# frozen_string_literal: true

require "test_helper"

class ThreadAgentTest < ActiveSupport::TestCase
  def setup
    ThreadAgent.reset_configuration!
  end

  def teardown
    ThreadAgent.reset_configuration!
  end

  test "module has configuration" do
    assert_not_nil ThreadAgent.configuration
    assert_instance_of ThreadAgent::Configuration, ThreadAgent.configuration
  end

  test "configure method yields configuration" do
    ThreadAgent.configure do |config|
      config.slack_client_id = "test_client_id"
      config.openai_model = "gpt-4"
    end

    assert_equal "test_client_id", ThreadAgent.configuration.slack_client_id
    assert_equal "gpt-4", ThreadAgent.configuration.openai_model
  end

  test "config method returns configuration" do
    assert_same ThreadAgent.configuration, ThreadAgent.config
  end

  test "configuration has default values" do
    config = ThreadAgent.configuration

    assert_equal "gpt-4o-mini", config.openai_model
    assert_equal 30, config.default_timeout
    assert_equal 3, config.max_retries
  end

  test "configuration reads from environment variables" do
    config = ThreadAgent.configuration

    # These should match the ENV fetch calls in Configuration#initialize
    assert_equal ENV.fetch("THREAD_AGENT_OPENAI_MODEL", "gpt-4o-mini"), config.openai_model
    assert_equal ENV.fetch("THREAD_AGENT_DEFAULT_TIMEOUT", "30").to_i, config.default_timeout
    assert_equal ENV.fetch("THREAD_AGENT_MAX_RETRIES", "3").to_i, config.max_retries
  end

  test "slack_configured? returns true when all slack config present" do
    ThreadAgent.configure do |config|
      config.slack_client_id = "client_id"
      config.slack_client_secret = "client_secret"
      config.slack_signing_secret = "signing_secret"
    end

    assert ThreadAgent.configuration.slack_configured?
  end

  test "slack_configured? returns false when slack config missing" do
    ThreadAgent.configure do |config|
      config.slack_client_id = "client_id"
      # missing client_secret and signing_secret
    end

    assert_not ThreadAgent.configuration.slack_configured?
  end

  test "openai_configured? returns true when api key present" do
    ThreadAgent.configure do |config|
      config.openai_api_key = "test_key"
    end

    assert ThreadAgent.configuration.openai_configured?
  end

  test "notion_configured? returns true when all notion config present" do
    ThreadAgent.configure do |config|
      config.notion_client_id = "client_id"
      config.notion_client_secret = "client_secret"
    end

    assert ThreadAgent.configuration.notion_configured?
  end

  test "fully_configured? returns true when all services configured" do
    ThreadAgent.configure do |config|
      config.slack_client_id = "slack_client_id"
      config.slack_client_secret = "slack_client_secret"
      config.slack_signing_secret = "slack_signing_secret"
      config.openai_api_key = "openai_api_key"
      config.notion_client_id = "notion_client_id"
      config.notion_client_secret = "notion_client_secret"
    end

    assert ThreadAgent.configuration.fully_configured?
  end

  test "exception classes are defined" do
    assert_equal ThreadAgent::Error, ThreadAgent::ConfigurationError.superclass
    assert_equal ThreadAgent::Error, ThreadAgent::SlackError.superclass
    assert_equal ThreadAgent::Error, ThreadAgent::OpenaiError.superclass
    assert_equal ThreadAgent::Error, ThreadAgent::NotionError.superclass
  end
end
