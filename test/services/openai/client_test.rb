# frozen_string_literal: true

require "test_helper"

class Openai::ClientTest < ActiveSupport::TestCase
  def setup
    # Reset configuration before each test
    AppConfig.reset_from_env!
  end

  def teardown
    # Reset configuration after each test
    AppConfig.reset_from_env!
  end

  test "initializes with valid API key and model" do
    client = Openai::Client.new(
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      timeout: 30
    )

    assert_equal "test-api-key", client.api_key
    assert_equal "gpt-4o-mini", client.model
    assert_equal 30, client.timeout
  end

  test "uses AppConfig when no parameters provided" do
    original_key   = AppConfig.instance.openai_api_key
    original_model = AppConfig.instance.openai_model
    AppConfig.instance.openai_api_key = "config-api-key"
    AppConfig.instance.openai_model   = "gpt-4"

    client = Openai::Client.new

    assert_equal "config-api-key", client.api_key
    assert_equal "gpt-4", client.model
  ensure
    AppConfig.instance.openai_api_key = original_key
    AppConfig.instance.openai_model   = original_model
  end

  test "parameter values override configuration values" do
    client = Openai::Client.new(
      api_key: "override-key",
      model: "gpt-3.5-turbo",
      timeout: 25
    )

    assert_equal "override-key", client.api_key
    assert_equal "gpt-3.5-turbo", client.model
    assert_equal 25, client.timeout
  end

  test "raises OpenaiAuthError when API key missing" do
    original = AppConfig.instance.openai_api_key
    AppConfig.instance.openai_api_key = nil

    error = assert_raises(Openai::AuthError) do
      Openai::Client.new(api_key: nil, model: "gpt-4")
    end

    assert_equal "Missing OpenAI API key", error.message
  ensure
    AppConfig.instance.openai_api_key = original
  end

  test "raises ConfigurationError when model missing" do
    error = assert_raises(ConfigurationError) do
      Openai::Client.new(api_key: "test-key", model: "")
    end

    assert_equal "Missing OpenAI model configuration", error.message
  end

  test "initializes OpenAI client with correct parameters" do
    client_instance = Openai::Client.new(
      api_key: "test-key",
      model: "gpt-4",
      timeout: 30
    )

    OpenAI::Client.expects(:new).with(
      access_token: "test-key",
      request_timeout: 30
    ).returns(mock("OpenAI::Client"))

    client_instance.client
  end

  test "raises Error when client initialization fails" do
    OpenAI::Client.expects(:new).raises(StandardError.new("Network error"))

    client_instance = Openai::Client.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    error = assert_raises(ApplicationError) do
      client_instance.client
    end

    assert_includes error.message, "Unexpected error: Network error"
  end

  test "memoizes client after first initialization" do
    client_instance = Openai::Client.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    mock_client = mock("OpenAI::Client")
    OpenAI::Client.expects(:new).once.returns(mock_client)

    # Call client twice - should only initialize once
    first_client = client_instance.client
    second_client = client_instance.client

    assert_same first_client, second_client
  end
end
