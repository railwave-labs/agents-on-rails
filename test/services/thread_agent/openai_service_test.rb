# frozen_string_literal: true

require "test_helper"

class ThreadAgent::OpenaiServiceTest < ActiveSupport::TestCase
  def setup
    # Reset configuration before each test
    ThreadAgent.reset_configuration!
  end

  def teardown
    # Reset configuration after each test
    ThreadAgent.reset_configuration!
  end

  test "initializes with valid API key" do
    service = ThreadAgent::OpenaiService.new(
      configuration: mock_valid_configuration
    )

    assert_equal "test-openai-key", service.config.openai_api_key
  end

  test "initializes with custom client" do
    mock_client = mock_openai_client
    service = ThreadAgent::OpenaiService.new(
      configuration: mock_valid_configuration,
      client: mock_client
    )

    assert_same mock_client, service.client
  end

  test "uses ThreadAgent configuration by default" do
    ThreadAgent.configure do |config|
      config.openai_api_key = "configured-key"
    end

    service = ThreadAgent::OpenaiService.new
    assert_equal "configured-key", service.config.openai_api_key
  end

  test "raises error with missing API key" do
    config = mock_configuration(openai_api_key: nil)

    error = assert_raises(ThreadAgent::OpenaiError) do
      ThreadAgent::OpenaiService.new(configuration: config)
    end

    assert_equal "Missing OpenAI API key", error.message
  end

  test "raises error with empty API key" do
    config = mock_configuration(openai_api_key: "")

    error = assert_raises(ThreadAgent::OpenaiError) do
      ThreadAgent::OpenaiService.new(configuration: config)
    end

    assert_equal "Missing OpenAI API key", error.message
  end

  test "memoizes client instance" do
    service = ThreadAgent::OpenaiService.new(
      configuration: mock_valid_configuration
    )

    client1 = service.client
    client2 = service.client

    assert_same client1, client2
  end

  test "raises OpenaiError when client initialization fails" do
    config = mock_valid_configuration

    # Mock OpenAI::Client.new to raise an error
    OpenAI::Client.stubs(:new).raises(StandardError.new("Network error"))

    error = assert_raises(ThreadAgent::OpenaiError) do
      ThreadAgent::OpenaiService.new(configuration: config)
    end

    assert_match(/Failed to initialize OpenAI client: Network error/, error.message)
  end

  test "transform_content raises NotImplementedError" do
    service = ThreadAgent::OpenaiService.new(
      configuration: mock_valid_configuration
    )

    error = assert_raises(NotImplementedError) do
      service.transform_content("test content")
    end

    assert_equal "Content transformation not yet implemented", error.message
  end

  test "initializes OpenAI client with correct parameters" do
    config = mock_valid_configuration

    # Mock the OpenAI::Client to verify initialization parameters
    expected_params = {
      access_token: "test-openai-key",
      request_timeout: 20
    }

    OpenAI::Client.expects(:new).with(expected_params).returns(mock_openai_client)

    ThreadAgent::OpenaiService.new(configuration: config)
  end

  private

  def mock_valid_configuration
    mock_configuration(openai_api_key: "test-openai-key")
  end

  def mock_configuration(openai_api_key:)
    config = mock
    config.stubs(:openai_api_key).returns(openai_api_key)
    config
  end

  def mock_openai_client
    mock
  end
end
