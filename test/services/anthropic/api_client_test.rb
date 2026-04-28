# frozen_string_literal: true

require "test_helper"

class Anthropic::ApiClientTest < ActiveSupport::TestCase
  def setup
    AppConfig.reset_from_env!
  end

  def teardown
    AppConfig.reset_from_env!
  end

  test "initializes with explicit api_key and model" do
    client = Anthropic::ApiClient.new(
      api_key: "sk-ant-test",
      model: "claude-sonnet-4-5",
      timeout: 30
    )

    assert_equal "sk-ant-test", client.api_key
    assert_equal "claude-sonnet-4-5", client.model
    assert_equal 30, client.timeout
  end

  test "falls back to AppConfig when no parameters provided" do
    original_key   = AppConfig.instance.anthropic_api_key
    original_model = AppConfig.instance.anthropic_model

    AppConfig.instance.anthropic_api_key = "config-ant-key"
    AppConfig.instance.anthropic_model   = "claude-opus-4-5"

    client = Anthropic::ApiClient.new

    assert_equal "config-ant-key", client.api_key
    assert_equal "claude-opus-4-5", client.model
  ensure
    AppConfig.instance.anthropic_api_key = original_key
    AppConfig.instance.anthropic_model   = original_model
  end

  test "explicit parameters override AppConfig" do
    client = Anthropic::ApiClient.new(
      api_key: "override-key",
      model: "claude-haiku-4-5",
      timeout: 10
    )

    assert_equal "override-key", client.api_key
    assert_equal "claude-haiku-4-5", client.model
    assert_equal 10, client.timeout
  end

  test "raises AuthError when API key is missing" do
    original = AppConfig.instance.anthropic_api_key
    AppConfig.instance.anthropic_api_key = nil

    error = assert_raises(Anthropic::AuthError) do
      Anthropic::ApiClient.new(api_key: nil, model: "claude-sonnet-4-5")
    end

    assert_equal "Missing Anthropic API key", error.message
    assert_equal false, error.retryable?
  ensure
    AppConfig.instance.anthropic_api_key = original
  end

  test "raises ConfigurationError when model is blank" do
    error = assert_raises(::ConfigurationError) do
      Anthropic::ApiClient.new(api_key: "sk-ant-test", model: "")
    end

    assert_equal "Missing Anthropic model configuration", error.message
  end

  test "calls messages.create with correct params" do
    client_instance = Anthropic::ApiClient.new(
      api_key: "sk-ant-test",
      model: "claude-sonnet-4-5",
      timeout: 30
    )

    mock_gem_client   = mock("::Anthropic::Client")
    mock_messages     = mock("messages_resource")
    mock_message      = mock("message_response")
    ::Anthropic::Client.expects(:new).with(
      api_key: "sk-ant-test",
      timeout: 30
    ).returns(mock_gem_client)
    mock_gem_client.expects(:messages).returns(mock_messages)
    mock_messages.expects(:create).returns(mock_message)

    result = client_instance.messages_create(model: "claude-sonnet-4-5", max_tokens: 100, messages: [])
    assert_equal mock_message, result
  end

  test "memoizes underlying client across calls" do
    client_instance = Anthropic::ApiClient.new(
      api_key: "sk-ant-test",
      model: "claude-sonnet-4-5"
    )

    mock_gem_client = mock("::Anthropic::Client")
    mock_messages   = mock("messages_resource")
    mock_message    = mock("message_response")
    ::Anthropic::Client.expects(:new).once.returns(mock_gem_client)
    mock_gem_client.stubs(:messages).returns(mock_messages)
    mock_messages.stubs(:create).returns(mock_message)

    client_instance.messages_create(model: "claude-sonnet-4-5", max_tokens: 100, messages: [])
    client_instance.messages_create(model: "claude-sonnet-4-5", max_tokens: 100, messages: [])
  end

  test "wraps SDK RateLimitError in Anthropic::ApiRateLimitError" do
    client_instance = Anthropic::ApiClient.new(
      api_key: "sk-ant-test",
      model: "claude-sonnet-4-5"
    )

    mock_gem_client = mock("::Anthropic::Client")
    mock_messages   = mock("messages_resource")
    ::Anthropic::Client.stubs(:new).returns(mock_gem_client)
    mock_gem_client.stubs(:messages).returns(mock_messages)
    mock_messages.stubs(:create).raises(::Anthropic::Errors::RateLimitError.new(
      url: "https://api.anthropic.com",
      status: 429,
      headers: {},
      body: {},
      request: nil,
      response: nil
    ))

    assert_raises(Anthropic::ApiRateLimitError) do
      client_instance.messages_create(model: "claude-sonnet-4-5", max_tokens: 100, messages: [])
    end
  end

  test "wraps unexpected StandardError in ApplicationError" do
    client_instance = Anthropic::ApiClient.new(
      api_key: "sk-ant-test",
      model: "claude-sonnet-4-5"
    )

    mock_gem_client = mock("::Anthropic::Client")
    mock_messages   = mock("messages_resource")
    ::Anthropic::Client.stubs(:new).returns(mock_gem_client)
    mock_gem_client.stubs(:messages).returns(mock_messages)
    mock_messages.stubs(:create).raises(SocketError.new("Connection refused"))

    error = assert_raises(ApplicationError) do
      client_instance.messages_create(model: "claude-sonnet-4-5", max_tokens: 100, messages: [])
    end

    assert_includes error.message, "Connection refused"
  end
end
