# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Slack::SlackClientTest < ActiveSupport::TestCase
  test "initializes with valid bot token and signing secret" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret"
    )

    assert_equal "xoxb-valid-token", client.bot_token
    assert_equal "test-secret", client.signing_secret
  end

  test "initializes with custom timeout settings" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret",
      timeout: 20,
      open_timeout: 10,
      max_retries: 5
    )

    assert_equal 20, client.timeout
    assert_equal 10, client.open_timeout
    assert_equal 5, client.max_retries
  end

  test "uses default timeout settings when not specified" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret"
    )

    assert_equal 15, client.timeout
    assert_equal 5, client.open_timeout
    assert_equal 3, client.max_retries
  end

  test "raises error with missing bot token" do
    # Clear configuration to ensure we're testing missing token scenario
    original_bot_token = ThreadAgent.configuration.slack_bot_token
    ThreadAgent.configuration.slack_bot_token = nil

    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::Slack::SlackClient.new(bot_token: nil, signing_secret: "test-secret")
    end

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_bot_token
  end

  test "raises error with missing signing secret" do
    # Clear configuration to ensure we're testing missing secret scenario
    original_signing_secret = ThreadAgent.configuration.slack_signing_secret
    ThreadAgent.configuration.slack_signing_secret = nil

    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::Slack::SlackClient.new(bot_token: "xoxb-valid-token", signing_secret: nil)
    end

    # Restore original config
    ThreadAgent.configuration.slack_signing_secret = original_signing_secret
  end

  test "uses ThreadAgent configuration by default" do
    # Mock the configuration
    original_bot_token = ThreadAgent.configuration.slack_bot_token
    original_signing_secret = ThreadAgent.configuration.slack_signing_secret
    ThreadAgent.configuration.slack_bot_token = "xoxb-config-token"
    ThreadAgent.configuration.slack_signing_secret = "config-secret"

    client = ThreadAgent::Slack::SlackClient.new
    assert_equal "xoxb-config-token", client.bot_token
    assert_equal "config-secret", client.signing_secret

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_bot_token
    ThreadAgent.configuration.slack_signing_secret = original_signing_secret
  end

  test "initializes Slack client with correct token" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret"
    )
    slack_client = client.client

    assert_instance_of Slack::Web::Client, slack_client
    assert_equal "xoxb-valid-token", slack_client.token
  end

  test "configures client with timeout settings" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret",
      timeout: 25,
      open_timeout: 12
    )
    slack_client = client.client

    assert_equal 25, slack_client.timeout
    assert_equal 12, slack_client.open_timeout
  end

  test "memoizes client instance" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret"
    )
    client1 = client.client
    client2 = client.client

    assert_same client1, client2
  end

  test "creates webhook validator" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret"
    )
    validator = client.webhook_validator

    assert_instance_of ThreadAgent::Slack::WebhookValidator, validator
    assert_equal "test-secret", validator.signing_secret
  end

  test "memoizes webhook validator instance" do
    client = ThreadAgent::Slack::SlackClient.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret"
    )
    validator1 = client.webhook_validator
    validator2 = client.webhook_validator

    assert_same validator1, validator2
  end
end
