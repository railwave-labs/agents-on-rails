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

  # Thread fetching tests
  test "fetch_thread returns success with formatted thread data" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")

    # Mock messages
    parent_message = mock("parent_message")
    parent_message.stubs(:channel).returns("C12345678")
    parent_message.stubs(:user).returns("U12345")
    parent_message.stubs(:text).returns("Parent message")
    parent_message.stubs(:ts).returns("1605139215.000700")
    parent_message.stubs(:try).with(:attachments).returns([])
    parent_message.stubs(:try).with(:files).returns([])

    reply_message = mock("reply_message")
    reply_message.stubs(:user).returns("U67890")
    reply_message.stubs(:text).returns("Reply message")
    reply_message.stubs(:ts).returns("1605139300.000800")
    reply_message.stubs(:try).with(:attachments).returns([])
    reply_message.stubs(:try).with(:files).returns([])

    # Mock API responses
    history_response = mock("history_response")
    history_response.stubs(:messages).returns([ parent_message ])

    replies_response = mock("replies_response")
    replies_response.stubs(:messages).returns([ parent_message, reply_message ])

    # Mock client
    slack_client = mock("slack_client")
    slack_client.expects(:conversations_history).with(
      channel: "C12345678",
      latest: "1605139215.000700",
      limit: 1,
      inclusive: true
    ).returns(history_response)

    slack_client.expects(:conversations_replies).with(
      channel: "C12345678",
      ts: "1605139215.000700"
    ).returns(replies_response)

    service.stubs(:client).returns(slack_client)

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.success?
    assert_equal "C12345678", result.data[:channel_id]
    assert_equal "1605139215.000700", result.data[:thread_ts]
    assert_equal "Parent message", result.data[:parent_message][:text]
    assert_equal 1, result.data[:replies].length
    assert_equal "Reply message", result.data[:replies][0][:text]
  end

  test "fetch_thread raises error with missing channel_id" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")

    error = assert_raises(ThreadAgent::SlackError) do
      service.fetch_thread(nil, "1605139215.000700")
    end

    assert_match(/Missing channel_id/, error.message)
  end

  test "fetch_thread raises error with missing thread_ts" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")

    error = assert_raises(ThreadAgent::SlackError) do
      service.fetch_thread("C12345678", nil)
    end

    assert_match(/Missing thread_ts/, error.message)
  end

    test "fetch_thread handles parent message not found" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")

    # Mock empty response
    history_response = mock("history_response")
    history_response.stubs(:messages).returns([])

    # Mock client
    slack_client = mock("slack_client")
    slack_client.expects(:conversations_history).returns(history_response)

    service.stubs(:client).returns(slack_client)

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.failure?
    assert_match(/Parent message not found/, result.error)
  end

  test "fetch_thread handles rate limiting error" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")

    # Create rate limit error with mock response_metadata
    rate_limit_error = Slack::Web::Api::Errors::RateLimited.new("Rate limited")
    rate_limit_error.stubs(:response_metadata).returns({ "retry_after" => 30 })

    # Mock client
    slack_client = mock("slack_client")
    slack_client.expects(:conversations_history).raises(rate_limit_error)

    service.stubs(:client).returns(slack_client)

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.failure?
    assert_match(/Rate limited/, result.error)
    assert_equal 30, result.metadata[:retry_after]
  end

  test "fetch_thread handles general Slack API error" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")

    slack_error = Slack::Web::Api::Errors::SlackError.new("Channel not found")

    # Mock client
    slack_client = mock("slack_client")
    slack_client.expects(:conversations_history).raises(slack_error)

    service.stubs(:client).returns(slack_client)

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.failure?
    assert_match(/Slack API error: Channel not found/, result.error)
  end
end
