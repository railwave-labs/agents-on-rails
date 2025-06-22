# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ThreadAgent::Slack::ServiceTest < ActiveSupport::TestCase
  test "initializes with valid bot token" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")
    assert_equal "xoxb-valid-token", service.bot_token
  end

  test "initializes with custom timeout settings" do
    service = ThreadAgent::Slack::Service.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret",
      timeout: 20,
      open_timeout: 10,
      max_retries: 5
    )
    assert_equal 20, service.timeout
    assert_equal 10, service.open_timeout
    assert_equal 5, service.max_retries
  end

  test "uses default timeout settings when not specified" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")
    assert_equal 15, service.timeout
    assert_equal 5, service.open_timeout
    assert_equal 3, service.max_retries
  end

  test "raises error with missing bot token" do
    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::Slack::Service.new(bot_token: nil, signing_secret: "test-secret")
    end
  end

  test "raises error with empty bot token" do
    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::Slack::Service.new(bot_token: "", signing_secret: "test-secret")
    end
  end

  test "uses ThreadAgent configuration by default" do
    # Mock the configuration
    original_bot_token = ThreadAgent.configuration.slack_bot_token
    original_signing_secret = ThreadAgent.configuration.slack_signing_secret
    ThreadAgent.configuration.slack_bot_token = "xoxb-config-token"
    ThreadAgent.configuration.slack_signing_secret = "config-secret"

    service = ThreadAgent::Slack::Service.new
    assert_equal "xoxb-config-token", service.bot_token

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_bot_token
    ThreadAgent.configuration.slack_signing_secret = original_signing_secret
  end

  test "raises error when ThreadAgent configuration has no bot token" do
    # Mock the configuration to return nil
    original_bot_token = ThreadAgent.configuration.slack_bot_token
    original_signing_secret = ThreadAgent.configuration.slack_signing_secret
    ThreadAgent.configuration.slack_bot_token = nil
    ThreadAgent.configuration.slack_signing_secret = "config-secret"

    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::Slack::Service.new
    end

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_bot_token
    ThreadAgent.configuration.slack_signing_secret = original_signing_secret
  end

  test "initializes Slack client with correct token" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")
    client = service.client

    assert_instance_of Slack::Web::Client, client
    assert_equal "xoxb-valid-token", client.token
  end

  test "configures client with timeout settings" do
    service = ThreadAgent::Slack::Service.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret",
      timeout: 25,
      open_timeout: 12
    )
    client = service.client

    assert_equal 25, client.timeout
    assert_equal 12, client.open_timeout
  end

  test "configures client with retry settings" do
    service = ThreadAgent::Slack::Service.new(
      bot_token: "xoxb-valid-token",
      signing_secret: "test-secret",
      max_retries: 7
    )
    client = service.client

    assert_equal 7, client.default_max_retries
    assert_equal Rails.logger, client.logger
  end

  test "memoizes client instance" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")
    client1 = service.client
    client2 = service.client

    assert_same client1, client2
  end

  test "raises ThreadAgent::SlackError when Slack client initialization fails" do
    # Create a service that will trigger an error by mocking the client method
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-invalid-token", signing_secret: "test-secret")

    # Override the slack_client's client method to simulate initialization failure
    service.slack_client.define_singleton_method(:client) do
      @client ||= begin
        raise ::Slack::Web::Api::Errors::SlackError.new("Invalid token")
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
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")

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

    # Mock client to be called via the thread_fetcher's retry_handler
    slack_client = mock("slack_client")
    slack_client.expects(:conversations_history).with(
      channel: "C12345678",
      latest: "1605139215.000700",
      limit: 1,
      inclusive: true
    ).returns(history_response).once # Called once, wrapped by retry handler

    slack_client.expects(:conversations_replies).with(
      channel: "C12345678",
      ts: "1605139215.000700"
    ).returns(replies_response).once # Called once, wrapped by retry handler

    # Mock the thread_fetcher's slack_client.client to return our mocked client
    service.thread_fetcher.slack_client.stubs(:client).returns(slack_client)

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.success?
    assert_equal "C12345678", result.data[:channel_id]
    assert_equal "1605139215.000700", result.data[:thread_ts]
    assert_equal "Parent message", result.data[:parent_message][:text]
    assert_equal 1, result.data[:replies].length
    assert_equal "Reply message", result.data[:replies][0][:text]
  end

  test "fetch_thread raises error with missing channel_id" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")

    result = service.fetch_thread(nil, "1605139215.000700")

    assert_not result.success?
    assert_match(/Missing channel_id/, result.error)
  end

  test "fetch_thread raises error with missing thread_ts" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")

    result = service.fetch_thread("C12345678", nil)

    assert_not result.success?
    assert_match(/Missing thread_ts/, result.error)
  end

  test "fetch_thread handles parent message not found" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")

    # Mock empty response
    history_response = mock("history_response")
    history_response.stubs(:messages).returns([])

    # Mock client
    slack_client = mock("slack_client")
    slack_client.expects(:conversations_history).with(
      channel: "C12345678",
      latest: "1605139215.000700",
      limit: 1,
      inclusive: true
    ).returns(history_response)

    # Mock the thread_fetcher's slack_client.client to return our mocked client
    service.thread_fetcher.slack_client.stubs(:client).returns(slack_client)

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.failure?
    assert_match(/Parent message not found/, result.error)
  end

  test "fetch_thread handles rate limiting error" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")

    # Create rate limit error with mock response_metadata
    rate_limit_error = ::Slack::Web::Api::Errors::RateLimited.new("Rate limited")
    rate_limit_error.stubs(:response_metadata).returns({ "retry_after" => 30 })

    # Mock the retry handler to simulate exhausted retries
    service.thread_fetcher.retry_handler.expects(:with_retries).raises(ThreadAgent::SlackError.new("Rate limit exceeded after 3 retries: Rate limited"))

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.failure?
    assert_match(/Rate limit exceeded after 3 retries/, result.error)
  end

  test "fetch_thread handles general Slack API error" do
    service = ThreadAgent::Slack::Service.new(bot_token: "xoxb-valid-token", signing_secret: "test-secret")

    slack_error = ::Slack::Web::Api::Errors::SlackError.new("Channel not found")
    slack_error.stubs(:response_metadata).returns({ "status_code" => 404 })

    # Mock the retry handler to simulate API error that doesn't get retried (4xx)
    service.thread_fetcher.retry_handler.expects(:with_retries).raises(ThreadAgent::SlackError.new("Slack API client error (404): Channel not found"))

    result = service.fetch_thread("C12345678", "1605139215.000700")

    assert result.failure?
    assert_match(/Slack API client error.*Channel not found/, result.error)
  end

  def setup
    @config = OpenStruct.new(
      slack_bot_token: "xoxb-valid-token",
      slack_signing_secret: "signing-secret"
    )
    @service = ThreadAgent::Slack::Service.new(
      bot_token: @config.slack_bot_token,
      signing_secret: @config.slack_signing_secret
    )
  end

  test "initializes with configuration values" do
    assert_equal "xoxb-valid-token", @service.bot_token
    assert_equal "signing-secret", @service.signing_secret
  end

  test "raises error when bot token is missing" do
    assert_raises ThreadAgent::SlackError do
      ThreadAgent::Slack::Service.new(bot_token: nil, signing_secret: "secret")
    end
  end

  test "raises error when signing secret is missing" do
    assert_raises ThreadAgent::SlackError do
      ThreadAgent::Slack::Service.new(bot_token: "token", signing_secret: nil)
    end
  end

  class ValidateWebhookTest < ThreadAgent::Slack::ServiceTest
    def setup
      super
      @valid_timestamp = Time.now.to_i.to_s
      @valid_payload = { "type" => "event_callback", "event" => { "type" => "message" } }
      @raw_payload = @valid_payload.to_json
    end

    def generate_valid_signature(timestamp, raw_body)
      basestring = "v0:#{timestamp}:#{raw_body}"
      "v0=" + OpenSSL::HMAC.hexdigest("SHA256", "signing-secret", basestring)
    end

    def valid_headers(timestamp = @valid_timestamp, raw_body = @raw_payload)
      {
        "X-Slack-Request-Timestamp" => timestamp,
        "X-Slack-Signature" => generate_valid_signature(timestamp, raw_body)
      }
    end

    test "returns success with valid signature and JSON payload" do
      headers = valid_headers
      result = @service.validate_webhook(@raw_payload, headers)

      assert result.success?
      assert_equal @valid_payload, result.data
    end

    test "returns success with valid signature and Hash payload" do
      headers = valid_headers(@valid_timestamp, @valid_payload.to_json)
      result = @service.validate_webhook(@valid_payload, headers)

      assert result.success?
      assert_equal @valid_payload, result.data
    end

    test "returns failure for invalid signature" do
      invalid_headers = {
        "X-Slack-Request-Timestamp" => @valid_timestamp,
        "X-Slack-Signature" => "v0=invalid-signature"
      }

      result = @service.validate_webhook(@raw_payload, invalid_headers)

      assert result.failure?
      assert_match(/Invalid Slack signature/, result.error)
    end

    test "returns failure for expired timestamp" do
      expired_timestamp = (Time.now.to_i - 400).to_s # 400 seconds old (> 5 minutes)
      expired_headers = valid_headers(expired_timestamp, @raw_payload)

      result = @service.validate_webhook(@raw_payload, expired_headers)

      assert result.failure?
      assert_match(/Invalid Slack signature/, result.error)
    end

    test "returns failure for missing timestamp header" do
      headers = {
        "X-Slack-Signature" => generate_valid_signature(@valid_timestamp, @raw_payload)
      }

      result = @service.validate_webhook(@raw_payload, headers)

      assert result.failure?
      assert_match(/Invalid Slack signature/, result.error)
    end

    test "returns failure for missing signature header" do
      headers = {
        "X-Slack-Request-Timestamp" => @valid_timestamp
      }

      result = @service.validate_webhook(@raw_payload, headers)

      assert result.failure?
      assert_match(/Invalid Slack signature/, result.error)
    end

    test "returns failure when payload is missing" do
      result = @service.validate_webhook(nil, valid_headers)

      assert result.failure?
      assert_match(/Missing payload/, result.error)
    end

    test "returns failure when headers are missing" do
      result = @service.validate_webhook(@valid_payload, nil)

      assert result.failure?
      assert_match(/Missing headers/, result.error)
    end

    test "returns failure for invalid JSON payload" do
      invalid_json = "{ invalid json }"
      headers = valid_headers(@valid_timestamp, invalid_json)

      result = @service.validate_webhook(invalid_json, headers)

      assert result.failure?
      assert_match(/Invalid JSON payload/, result.error)
    end
  end

  class PayloadStructureValidationTest < ThreadAgent::Slack::ServiceTest
    def setup
      super
      @valid_timestamp = Time.now.to_i.to_s
    end

    def generate_valid_signature(timestamp, raw_body)
      basestring = "v0:#{timestamp}:#{raw_body}"
      "v0=" + OpenSSL::HMAC.hexdigest("SHA256", "signing-secret", basestring)
    end

    def headers_for_payload(payload)
      raw_body = payload.to_json
      {
        "X-Slack-Request-Timestamp" => @valid_timestamp,
        "X-Slack-Signature" => generate_valid_signature(@valid_timestamp, raw_body)
      }
    end

    test "validates url_verification payload structure" do
      valid_payload = { "type" => "url_verification", "challenge" => "test-challenge" }
      headers = headers_for_payload(valid_payload)

      result = @service.validate_webhook(valid_payload.to_json, headers)

      assert result.success?
      assert_equal valid_payload, result.data
    end

    test "rejects url_verification payload without challenge" do
      invalid_payload = { "type" => "url_verification" }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end

    test "validates event_callback payload structure" do
      valid_payload = {
        "type" => "event_callback",
        "event" => { "type" => "message", "text" => "Hello" }
      }
      headers = headers_for_payload(valid_payload)

      result = @service.validate_webhook(valid_payload.to_json, headers)

      assert result.success?
      assert_equal valid_payload, result.data
    end

    test "rejects event_callback payload without event" do
      invalid_payload = { "type" => "event_callback" }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end

    test "rejects event_callback payload without event type" do
      invalid_payload = { "type" => "event_callback", "event" => {} }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end

    test "validates block_actions payload structure" do
      valid_payload = {
        "type" => "block_actions",
        "actions" => [ { "action_id" => "test", "value" => "test" } ]
      }
      headers = headers_for_payload(valid_payload)

      result = @service.validate_webhook(valid_payload.to_json, headers)

      assert result.success?
      assert_equal valid_payload, result.data
    end

    test "rejects block_actions payload without actions" do
      invalid_payload = { "type" => "block_actions" }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end

    test "rejects block_actions payload with non-array actions" do
      invalid_payload = { "type" => "block_actions", "actions" => "not-an-array" }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end

    test "validates view_submission payload structure" do
      valid_payload = {
        "type" => "view_submission",
        "view" => { "id" => "view-id", "state" => {} }
      }
      headers = headers_for_payload(valid_payload)

      result = @service.validate_webhook(valid_payload.to_json, headers)

      assert result.success?
      assert_equal valid_payload, result.data
    end

    test "rejects view_submission payload without view" do
      invalid_payload = { "type" => "view_submission" }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end

    test "rejects view_submission payload without view id" do
      invalid_payload = { "type" => "view_submission", "view" => {} }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end

    test "rejects completely invalid payload structure" do
      invalid_payload = { "invalid" => "structure" }
      headers = headers_for_payload(invalid_payload)

      result = @service.validate_webhook(invalid_payload.to_json, headers)

      assert result.failure?
      assert_match(/Invalid payload structure/, result.error)
    end
  end

  class ModalCreationTest < ThreadAgent::Slack::ServiceTest
    def setup
      super
      @trigger_id = "12345.98765.abcd2358fdea"
      @workspaces = [
        { id: 1, name: "Engineering Workspace" },
        { id: 2, name: "Marketing Workspace" }
      ]
      @templates = [
        { id: 1, name: "Bug Report Template" },
        { id: 2, name: "Feature Request Template" }
      ]
    end


    test "successfully creates modal with workspaces and templates" do
      # Mock the Slack client response
      slack_response = { "ok" => true, "view" => { "id" => "V123456789" } }

      # Mock the client to expect views_open call
      mock_client = mock("slack_client")
      mock_client.expects(:views_open).with do |args|
        assert_equal @trigger_id, args[:trigger_id]
        assert_equal "modal", args[:view][:type]
        assert_equal "thread_capture_modal", args[:view][:callback_id]
        assert_equal "Capture Thread", args[:view][:title][:text]

        # Verify blocks structure
        blocks = args[:view][:blocks]
        assert blocks.length >= 3

        # Check for section block
        section_block = blocks.find { |b| b[:type] == "section" }
        assert_not_nil section_block
        assert_includes section_block[:text][:text], "workspace and template"

        # Check for workspace selector
        workspace_block = blocks.find { |b| b[:block_id] == "workspace_block" }
        assert_not_nil workspace_block
        assert_equal "input", workspace_block[:type]
        assert_equal "static_select", workspace_block[:element][:type]
        assert_equal 2, workspace_block[:element][:options].length
        assert_equal "Engineering Workspace", workspace_block[:element][:options][0][:text][:text]
        assert_equal "1", workspace_block[:element][:options][0][:value]

        # Check for template selector
        template_block = blocks.find { |b| b[:block_id] == "template_block" }
        assert_not_nil template_block
        assert_equal "input", template_block[:type]
        assert_equal "static_select", template_block[:element][:type]
        assert_equal 2, template_block[:element][:options].length
        assert_equal "Bug Report Template", template_block[:element][:options][0][:text][:text]
        assert_equal "1", template_block[:element][:options][0][:value]

        true
      end.returns(slack_response)

      # Mock the shortcut_handler's slack_client.client to return our mocked client
      @service.shortcut_handler.slack_client.stubs(:client).returns(mock_client)

      result = @service.create_modal(@trigger_id, @workspaces, @templates)

      assert result.success?
      assert_equal slack_response, result.data
    end

    test "successfully creates modal with only workspaces (no templates)" do
      # Mock the Slack client response
      slack_response = { "ok" => true, "view" => { "id" => "V123456789" } }

      # Mock the client to expect views_open call
      mock_client = mock("slack_client")
      mock_client.expects(:views_open).with do |args|
        # Verify blocks structure - should not include template selector
        blocks = args[:view][:blocks]

        # Should have section, divider, and workspace selector only (no template selector)
        assert_equal 3, blocks.length

        # Should have workspace selector but no template selector
        workspace_block = blocks.find { |b| b[:block_id] == "workspace_block" }
        assert_not_nil workspace_block

        template_block = blocks.find { |b| b[:block_id] == "template_block" }
        assert_nil template_block

        true
      end.returns(slack_response)

      # Mock the shortcut_handler's slack_client.client to return our mocked client
      @service.shortcut_handler.slack_client.stubs(:client).returns(mock_client)

      result = @service.create_modal(@trigger_id, @workspaces, [])

      assert result.success?
      assert_equal slack_response, result.data
    end

    test "handles workspaces with string keys instead of symbol keys" do
      string_key_workspaces = [
        { "id" => 1, "name" => "Engineering Workspace" },
        { "id" => 2, "name" => "Marketing Workspace" }
      ]

      # Mock the Slack client response
      slack_response = { "ok" => true, "view" => { "id" => "V123456789" } }

      # Mock the client to expect views_open call
      mock_client = mock("slack_client")
      mock_client.expects(:views_open).with do |args|
        # Check that string keys are handled properly
        workspace_block = args[:view][:blocks].find { |b| b[:block_id] == "workspace_block" }
        assert_equal "Engineering Workspace", workspace_block[:element][:options][0][:text][:text]
        assert_equal "1", workspace_block[:element][:options][0][:value]

        true
      end.returns(slack_response)

      # Mock the shortcut_handler's slack_client.client to return our mocked client
      @service.shortcut_handler.slack_client.stubs(:client).returns(mock_client)

      result = @service.create_modal(@trigger_id, string_key_workspaces, [])

      assert result.success?
    end

    test "returns failure when trigger_id is missing" do
      result = @service.create_modal(nil, @workspaces, @templates)

      assert result.failure?
      assert_match(/Missing trigger_id/, result.error)
    end

    test "returns failure when trigger_id is blank" do
      result = @service.create_modal("", @workspaces, @templates)

      assert result.failure?
      assert_match(/Missing trigger_id/, result.error)
    end

    test "returns failure when workspaces are missing" do
      result = @service.create_modal(@trigger_id, nil, @templates)

      assert result.failure?
      assert_match(/No workspaces available/, result.error)
    end

    test "returns failure when workspaces are empty" do
      result = @service.create_modal(@trigger_id, [], @templates)

      assert result.failure?
      assert_match(/No workspaces available/, result.error)
    end

    test "handles Slack API errors gracefully" do
      slack_error = ::Slack::Web::Api::Errors::SlackError.new("Invalid trigger")
      slack_error.stubs(:response_metadata).returns({ "status_code" => 400 })

      # Mock the shortcut_handler's retry handler to simulate API error that doesn't get retried (4xx)
      @service.shortcut_handler.retry_handler.expects(:with_retries).raises(ThreadAgent::SlackError.new("Slack API client error (400): Invalid trigger"))

      result = @service.create_modal(@trigger_id, @workspaces, @templates)

      assert result.failure?
      assert_match(/Slack API client error.*Invalid trigger/, result.error)
    end

    test "handles general exceptions gracefully" do
      general_error = StandardError.new("Unexpected error")

      # Mock the shortcut_handler's retry handler to simulate a general error
      @service.shortcut_handler.retry_handler.expects(:with_retries).raises(general_error)

      result = @service.create_modal(@trigger_id, @workspaces, @templates)

      assert result.failure?
      assert_match(/Unexpected error: Unexpected error/, result.error)
    end
  end

  class RetryLogicTest < ThreadAgent::Slack::ServiceTest
    def setup
      super
    end

    test "with_retries handles rate limiting with retry-after header" do
      rate_limit_error = ::Slack::Web::Api::Errors::RateLimited.new("Rate limited")
      rate_limit_error.stubs(:response_metadata).returns({ "retry_after" => 0.1 })

      call_count = 0
      test_block = -> {
        call_count += 1
        raise rate_limit_error if call_count <= 2
        "success"
      }

      @service.retry_handler.expects(:sleep).with(0.1).twice

      result = @service.send(:with_retries, max_retries: 3, initial_delay: 0.1) { test_block.call }
      assert_equal "success", result
      assert_equal 3, call_count
    end

    test "with_retries raises ThreadAgent::SlackError after max rate limit retries" do
      rate_limit_error = ::Slack::Web::Api::Errors::RateLimited.new("Rate limited")
      rate_limit_error.stubs(:response_metadata).returns({ "retry_after" => 0.1 })

      call_count = 0
      test_block = -> {
        call_count += 1
        raise rate_limit_error
      }

      @service.retry_handler.expects(:sleep).with(0.1).twice

      assert_raises(ThreadAgent::SlackError, /Rate limit exceeded after 2 retries/) do
        @service.send(:with_retries, max_retries: 2, initial_delay: 0.1) { test_block.call }
      end
      assert_equal 3, call_count # Initial + 2 retries
    end

    test "with_retries handles timeout errors with exponential backoff" do
      timeout_error = ::Slack::Web::Api::Errors::TimeoutError.new("Timeout")

      call_count = 0
      test_block = -> {
        call_count += 1
        raise timeout_error if call_count <= 2
        "success"
      }

      # Initial delay: 0.1, second delay: 0.2 (doubled)
      @service.retry_handler.expects(:sleep).with(0.1).once
      @service.retry_handler.expects(:sleep).with(0.2).once

      result = @service.send(:with_retries, max_retries: 3, initial_delay: 0.1, max_delay: 1.0) { test_block.call }
      assert_equal "success", result
      assert_equal 3, call_count
    end

    test "with_retries raises ThreadAgent::SlackError after max timeout retries" do
      timeout_error = ::Slack::Web::Api::Errors::TimeoutError.new("Timeout")

      call_count = 0
      test_block = -> {
        call_count += 1
        raise timeout_error
      }

      @service.retry_handler.expects(:sleep).with(1.0).once
      @service.retry_handler.expects(:sleep).with(2.0).once

      assert_raises(ThreadAgent::SlackError, /Timeout error after 2 retries/) do
        @service.send(:with_retries, max_retries: 2, initial_delay: 1.0) { test_block.call }
      end
      assert_equal 3, call_count # Initial + 2 retries
    end

    test "with_retries retries server errors (5xx) but not client errors (4xx)" do
      server_error = ::Slack::Web::Api::Errors::SlackError.new("Server error")
      server_error.stubs(:response_metadata).returns({ "status_code" => 503 })

      client_error = ::Slack::Web::Api::Errors::SlackError.new("Client error")
      client_error.stubs(:response_metadata).returns({ "status_code" => 404 })

      # Test server error retry
      call_count = 0
      test_block = -> {
        call_count += 1
        raise server_error if call_count == 1
        "success"
      }

      @service.retry_handler.expects(:sleep).with(1.0).once

      result = @service.send(:with_retries, max_retries: 2, initial_delay: 1.0) { test_block.call }
      assert_equal "success", result
      assert_equal 2, call_count

      # Test client error no retry
      call_count = 0
      test_block = -> {
        call_count += 1
        raise client_error
      }

      @service.retry_handler.expects(:sleep).never

      assert_raises(ThreadAgent::SlackError, /Slack API client error \(404\)/) do
        @service.send(:with_retries, max_retries: 2, initial_delay: 1.0) { test_block.call }
      end
      assert_equal 1, call_count # No retries
    end

    test "with_retries handles network timeout errors" do
      network_error = Net::ReadTimeout.new("Network timeout")

      call_count = 0
      test_block = -> {
        call_count += 1
        raise network_error if call_count <= 2
        "success"
      }

      @service.retry_handler.expects(:sleep).with(0.5).once
      @service.retry_handler.expects(:sleep).with(1.0).once

      result = @service.send(:with_retries, max_retries: 3, initial_delay: 0.5) { test_block.call }
      assert_equal "success", result
      assert_equal 3, call_count
    end

    test "with_retries raises ThreadAgent::SlackError after max network timeout retries" do
      network_error = Net::ReadTimeout.new("Read timeout")

      call_count = 0
      test_block = -> {
        call_count += 1
        raise network_error
      }

      @service.retry_handler.expects(:sleep).with(1.0).once

      assert_raises(ThreadAgent::SlackError, /Network timeout after 1 retries/) do
        @service.send(:with_retries, max_retries: 1, initial_delay: 1.0) { test_block.call }
      end
      assert_equal 2, call_count # Initial + 1 retry
    end

    test "with_retries respects max_delay for exponential backoff" do
      timeout_error = ::Slack::Web::Api::Errors::TimeoutError.new("Timeout")

      call_count = 0
      test_block = -> {
        call_count += 1
        raise timeout_error if call_count <= 3
        "success"
      }

      # Initial: 2.0, second: 4.0, third: 5.0 (capped by max_delay)
      @service.retry_handler.expects(:sleep).with(2.0).once
      @service.retry_handler.expects(:sleep).with(4.0).once
      @service.retry_handler.expects(:sleep).with(5.0).once

      result = @service.send(:with_retries, max_retries: 4, initial_delay: 2.0, max_delay: 5.0) { test_block.call }
      assert_equal "success", result
      assert_equal 4, call_count
    end
  end

  class FetchThreadRetryTest < ThreadAgent::Slack::ServiceTest
    def setup
      super
      @channel_id = "C12345678"
      @thread_ts = "1605139215.000700"
    end

    test "fetch_thread uses with_retries for API calls" do
      # Mock the thread_fetcher to verify with_retries is being used
      mock_fetcher = mock("thread_fetcher")
      @service.stubs(:thread_fetcher).returns(mock_fetcher)

      # Expect fetch_thread to be called and return a successful result
      expected_result = ThreadAgent::Result.success({
        channel_id: @channel_id,
        thread_ts: @thread_ts
      })
      mock_fetcher.expects(:fetch_thread).with(@channel_id, @thread_ts).returns(expected_result)

      result = @service.fetch_thread(@channel_id, @thread_ts)

      assert result.success?
      assert_equal @channel_id, result.data[:channel_id]
      assert_equal @thread_ts, result.data[:thread_ts]
    end

    test "fetch_thread handles ThreadAgent::SlackError from with_retries" do
      # Mock the thread_fetcher to return an error
      mock_fetcher = mock("thread_fetcher")
      @service.stubs(:thread_fetcher).returns(mock_fetcher)

      error_result = ThreadAgent::Result.failure("Slack API error after 0 retries: invalid_auth")
      mock_fetcher.expects(:fetch_thread).with(@channel_id, @thread_ts).returns(error_result)

      result = @service.fetch_thread(@channel_id, @thread_ts)

      assert result.failure?
      assert_equal "Slack API error after 0 retries: invalid_auth", result.error
    end
  end

  class CreateModalRetryTest < ThreadAgent::Slack::ServiceTest
    def setup
      super
      @trigger_id = "12345.98765.abcd2358fdea"
      @workspaces = [ { id: 1, name: "Engineering Workspace" } ]
    end

    test "create_modal uses with_retries for API calls" do
      # Mock the shortcut_handler to verify with_retries is being used
      mock_handler = mock("shortcut_handler")
      @service.stubs(:shortcut_handler).returns(mock_handler)

      slack_response = { "ok" => true, "view" => { "id" => "V123456789" } }
      expected_result = ThreadAgent::Result.success(slack_response)
      mock_handler.expects(:create_modal).with(@trigger_id, @workspaces, []).returns(expected_result)

      result = @service.create_modal(@trigger_id, @workspaces, [])

      assert result.success?
      assert_equal slack_response, result.data
    end

    test "create_modal handles ThreadAgent::SlackError from with_retries" do
      # Mock the shortcut_handler to return an error
      mock_handler = mock("shortcut_handler")
      @service.stubs(:shortcut_handler).returns(mock_handler)

      error_result = ThreadAgent::Result.failure("Slack API error after 0 retries: invalid_auth")
      mock_handler.expects(:create_modal).with(@trigger_id, @workspaces, []).returns(error_result)

      result = @service.create_modal(@trigger_id, @workspaces, [])

      assert result.failure?
      assert_equal "Slack API error after 0 retries: invalid_auth", result.error
    end
  end

  class HandleModalSubmissionTest < ThreadAgent::Slack::ServiceTest
    def setup
      super
    end

    test "handle_modal_submission processes valid payload successfully" do
      payload = {
        "type" => "view_submission",
        "user" => {
          "id" => "U123456",
          "name" => "testuser"
        },
        "view" => {
          "id" => "V123456",
          "state" => {
            "values" => {
              "workspace_select" => {
                "selected_workspace" => {
                  "selected_option" => {
                    "value" => "workspace_123"
                  }
                }
              },
              "template_select" => {
                "selected_template" => {
                  "selected_option" => {
                    "value" => "template_456"
                  }
                }
              }
            }
          }
        }
      }

      result = @service.handle_modal_submission(payload)

      assert result.success?
      assert_equal "Modal submission processed successfully", result.data
    end

    test "handle_modal_submission rejects invalid payload type" do
      payload = {
        "type" => "shortcut",
        "callback_id" => "thread_capture"
      }

      result = @service.handle_modal_submission(payload)

      assert result.failure?
      assert_equal "Invalid payload type", result.error
    end

    test "handle_modal_submission handles missing view data" do
      payload = {
        "type" => "view_submission",
        "user" => {
          "id" => "U123456"
        }
      }

      result = @service.handle_modal_submission(payload)

      assert result.failure?
      assert_equal "Missing modal submission data", result.error
    end

    test "handle_modal_submission handles empty state values" do
      payload = {
        "type" => "view_submission",
        "user" => {
          "id" => "U123456"
        },
        "view" => {
          "state" => {
            "values" => {}
          }
        }
      }

      result = @service.handle_modal_submission(payload)

      assert result.failure?
      assert_equal "Missing modal submission data", result.error
    end

    test "handle_modal_submission handles payload with minimal valid data" do
      payload = {
        "type" => "view_submission",
        "user" => {
          "id" => "U123456"
        },
        "view" => {
          "state" => {
            "values" => {
              "some_field" => {
                "some_action" => {
                  "value" => "some_value"
                }
              }
            }
          }
        }
      }

      result = @service.handle_modal_submission(payload)

      assert result.success?
      assert_equal "Modal submission processed successfully", result.data
    end

    test "handle_modal_submission handles exceptions gracefully" do
      payload = {
        "type" => "view_submission",
        "user" => {
          "id" => "U123456"
        },
        "view" => {
          "state" => {
            "values" => {
              "test" => "value"
            }
          }
        }
      }

      # Mock JSON.parse to raise an exception to simulate processing error
      Rails.logger.expects(:error).with(regexp_matches(/Error processing modal submission/))

      # Override dig method to raise error
      payload.define_singleton_method(:dig) do |*args|
        raise StandardError, "Simulated processing error" if args == [ "view", "state", "values" ]
        super(*args)
      end

      result = @service.handle_modal_submission(payload)

      assert result.failure?
      assert_match(/Failed to process modal submission: Simulated processing error/, result.error)
    end
  end
end
