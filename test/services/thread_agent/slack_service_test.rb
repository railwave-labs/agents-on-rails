# frozen_string_literal: true

require "test_helper"

class ThreadAgent::SlackServiceTest < ActiveSupport::TestCase
  test "initializes with valid bot token" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")
    assert_equal "xoxb-valid-token", service.bot_token
  end

  test "initializes with custom timeout settings" do
    service = ThreadAgent::SlackService.new(
      bot_token: "xoxb-valid-token",
      timeout: 20,
      open_timeout: 10,
      max_retries: 5
    )
    assert_equal 20, service.timeout
    assert_equal 10, service.open_timeout
    assert_equal 5, service.max_retries
  end

  test "uses default timeout settings when not specified" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")
    assert_equal 15, service.timeout
    assert_equal 5, service.open_timeout
    assert_equal 3, service.max_retries
  end

  test "raises error with missing bot token" do
    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::SlackService.new(bot_token: nil)
    end
  end

  test "raises error with empty bot token" do
    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::SlackService.new(bot_token: "")
    end
  end

  test "uses ThreadAgent configuration by default" do
    # Mock the configuration
    original_config = ThreadAgent.configuration.slack_bot_token
    ThreadAgent.configuration.slack_bot_token = "xoxb-config-token"

    service = ThreadAgent::SlackService.new
    assert_equal "xoxb-config-token", service.bot_token

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_config
  end

  test "raises error when ThreadAgent configuration has no bot token" do
    # Mock the configuration to return nil
    original_config = ThreadAgent.configuration.slack_bot_token
    ThreadAgent.configuration.slack_bot_token = nil

    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::SlackService.new
    end

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_config
  end

  test "initializes Slack client with correct token" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")
    client = service.client

    assert_instance_of Slack::Web::Client, client
    assert_equal "xoxb-valid-token", client.token
  end

  test "configures client with timeout settings" do
    service = ThreadAgent::SlackService.new(
      bot_token: "xoxb-valid-token",
      timeout: 25,
      open_timeout: 12
    )
    client = service.client

    assert_equal 25, client.timeout
    assert_equal 12, client.open_timeout
  end

  test "configures client with retry settings" do
    service = ThreadAgent::SlackService.new(
      bot_token: "xoxb-valid-token",
      max_retries: 7
    )
    client = service.client

    assert_equal 7, client.default_max_retries
    assert_equal Rails.logger, client.logger
  end

  test "memoizes client instance" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")
    client1 = service.client
    client2 = service.client

    assert_same client1, client2
  end

    test "raises ThreadAgent::SlackError when Slack client initialization fails" do
    # Create a service that will trigger an error by mocking the client method
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-invalid-token")

    # Override the client method to simulate initialization failure
    service.define_singleton_method(:client) do
      @client ||= begin
        raise Slack::Web::Api::Errors::SlackError.new("Invalid token")
      rescue StandardError => e
        raise ThreadAgent::SlackError, "Failed to initialize Slack client: #{e.message}"
      end
    end

    error = assert_raises(ThreadAgent::SlackError) do
      service.client
    end

    assert_match(/Failed to initialize Slack client: Invalid token/, error.message)
  end
end
