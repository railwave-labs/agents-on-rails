# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Openai::ServiceTest < ActiveSupport::TestCase
  def setup
    # Reset configuration before each test
    ThreadAgent.reset_configuration!
  end

  def teardown
    # Reset configuration after each test
    ThreadAgent.reset_configuration!
  end

  # Constructor tests
  test "initializes with valid API key and model" do
    service = ThreadAgent::Openai::Service.new(
      api_key: "test-openai-key",
      model: "gpt-4o-mini"
    )

    assert_equal "test-openai-key", service.api_key
    assert_equal "gpt-4o-mini", service.model
    assert_equal 20, service.timeout # DEFAULT_TIMEOUT
  end

  test "uses ThreadAgent configuration when no parameters provided" do
    ThreadAgent.configure do |config|
      config.openai_api_key = "config-api-key"
      config.openai_model = "gpt-4"
    end

    service = ThreadAgent::Openai::Service.new

    assert_equal "config-api-key", service.api_key
    assert_equal "gpt-4", service.model
  end

  test "parameter values override configuration values" do
    ThreadAgent.configure do |config|
      config.openai_api_key = "config-api-key"
      config.openai_model = "gpt-4"
    end

    service = ThreadAgent::Openai::Service.new(
      api_key: "override-key",
      model: "gpt-3.5-turbo"
    )

    assert_equal "override-key", service.api_key
    assert_equal "gpt-3.5-turbo", service.model
  end

  test "raises OpenaiError when API key missing" do
    error = assert_raises(ThreadAgent::OpenaiError) do
      ThreadAgent::Openai::Service.new(api_key: nil, model: "gpt-4")
    end

    assert_equal "Missing OpenAI API key", error.message
  end

  test "raises OpenaiError when model missing" do
    error = assert_raises(ThreadAgent::OpenaiError) do
      ThreadAgent::Openai::Service.new(api_key: "test-key", model: "")
    end

    assert_equal "Missing OpenAI model configuration", error.message
  end

  test "raises OpenaiError when client initialization fails" do
    OpenAI::Client.expects(:new).raises(StandardError.new("Network error"))

    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    error = assert_raises(ThreadAgent::OpenaiError) do
      service.client
    end

    assert_includes error.message, "Failed to initialize OpenAI client"
  end

  test "initializes OpenAI client with correct parameters" do
    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4",
      timeout: 30
    )

    OpenAI::Client.expects(:new).with(
      access_token: "test-key",
      request_timeout: 30
    ).returns(mock_openai_client)

    service.client
  end

  test "memoizes client after first initialization" do
    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    OpenAI::Client.expects(:new).once.returns(mock_openai_client)

    # Call client twice - should only initialize once
    first_client = service.client
    second_client = service.client

    assert_same first_client, second_client
  end

  # slack_permalink tests
  test "generates correct Slack permalink" do
    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    permalink = service.slack_permalink("C123456", "1234567890.123")
    expected = "https://slack.com/app_redirect?channel=C123456&message_ts=1234567890.123"

    assert_equal expected, permalink
  end

  # transform_content tests
  test "transform_content with template uses template content as system prompt" do
    template = mock_template_with_content("Custom template instructions")
    thread_data = mock_valid_thread_data
    mock_response = mock_openai_response("Template-based summary")

    service = create_service_with_mock_client(mock_response)

    result = service.transform_content(template: template, thread_data: thread_data)
    assert_equal "Template-based summary", result
  end

  test "transform_content with custom_prompt uses custom prompt as system prompt" do
    template = mock_template_with_content("Template instructions")
    thread_data = mock_valid_thread_data
    mock_response = mock_openai_response("Custom prompt summary")

    service = create_service_with_mock_client(mock_response)

    result = service.transform_content(
      template: template,
      thread_data: thread_data,
      custom_prompt: "Custom user instructions"
    )
    assert_equal "Custom prompt summary", result
  end

  test "transform_content without template or custom_prompt uses default system prompt" do
    thread_data = mock_valid_thread_data
    mock_response = mock_openai_response("Default summary")

    service = create_service_with_mock_client(mock_response)

    result = service.transform_content(thread_data: thread_data)
    assert_equal "Default summary", result
  end

  test "transform_content includes slack permalink in user content" do
    thread_data = mock_valid_thread_data
    mock_response = mock_openai_response("Summary with link")

    service = create_service_with_mock_client(mock_response)

    result = service.transform_content(thread_data: thread_data)
    assert_equal "Summary with link", result
  end

  test "transform_content handles thread with replies" do
    thread_data = mock_thread_data_with_replies
    mock_response = mock_openai_response("Summary with replies")

    service = create_service_with_mock_client(mock_response)

    result = service.transform_content(thread_data: thread_data)
    assert_equal "Summary with replies", result
  end

  test "transform_content raises OpenaiError for invalid thread_data" do
    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    error = assert_raises(ThreadAgent::OpenaiError) do
      service.transform_content(thread_data: { invalid: "data" })
    end

    assert_equal "Invalid thread_data: must be a hash with parent_message", error.message
  end

  test "transform_content raises OpenaiError when API request fails" do
    thread_data = mock_valid_thread_data

    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    mock_client = mock_openai_client
    mock_client.expects(:chat).raises(StandardError.new("API error"))
    service.openai_client.expects(:client).returns(mock_client)

    error = assert_raises(ThreadAgent::OpenaiError) do
      service.transform_content(thread_data: thread_data)
    end

    assert_includes error.message, "OpenAI API request failed"
  end

  test "transform_content raises OpenaiError when response missing content" do
    thread_data = mock_valid_thread_data
    mock_response = { "choices" => [ { "message" => {} } ] }

    service = create_service_with_mock_client(mock_response)

    error = assert_raises(ThreadAgent::OpenaiError) do
      service.transform_content(thread_data: thread_data)
    end

    assert_equal "Invalid response from OpenAI: missing content", error.message
  end

  test "transform_content handles other errors gracefully" do
    thread_data = mock_valid_thread_data

    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )

    service.expects(:validate_transform_inputs!).raises(ArgumentError.new("Some error"))

    error = assert_raises(ThreadAgent::OpenaiError) do
      service.transform_content(thread_data: thread_data)
    end

    assert_includes error.message, "Content transformation failed"
  end

  test "transform_content makes correct API request" do
    thread_data = mock_valid_thread_data
    mock_response = mock_openai_response("API test summary")

    mock_client = mock_openai_client
    mock_client.expects(:chat) do |params|
      assert_equal "gpt-4", params[:parameters][:model]
      assert_equal 1000, params[:parameters][:max_tokens]
      assert_equal 0.7, params[:parameters][:temperature]
      assert_equal 2, params[:parameters][:messages].length
      assert_equal "system", params[:parameters][:messages][0][:role]
      assert_equal ThreadAgent::Openai::MessageBuilder::DEFAULT_SYSTEM_PROMPT, params[:parameters][:messages][0][:content]
      assert_equal "user", params[:parameters][:messages][1][:role]
      assert_instance_of String, params[:parameters][:messages][1][:content]
      true
    end.returns(mock_response)

    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )
    service.openai_client.expects(:client).returns(mock_client)

    result = service.transform_content(thread_data: thread_data)
    assert_equal "API test summary", result
  end

  private

  def create_service_with_mock_client(mock_response)
    mock_client = mock_openai_client
    mock_client.expects(:chat).returns(mock_response)

    service = ThreadAgent::Openai::Service.new(
      api_key: "test-key",
      model: "gpt-4"
    )
    service.openai_client.expects(:client).returns(mock_client)

    service
  end

  def mock_openai_client
    mock("OpenAI::Client")
  end

  def mock_template_with_content(content)
    template = mock("Template")
    template.stubs(:respond_to?).with(:content).returns(true)
    template.stubs(:content).returns(content)
    template
  end

  def mock_valid_thread_data
    {
      parent_message: {
        user: "user123",
        text: "Original message",
        ts: "1234567890.123"
      },
      channel_id: "C123456",
      thread_ts: "1234567890.123"
    }
  end

  def mock_thread_data_with_replies
    {
      parent_message: {
        user: "user123",
        text: "Original message",
        ts: "1234567890.123"
      },
      replies: [
        {
          user: "user456",
          text: "First reply",
          ts: "1234567891.123"
        },
        {
          user: "user789",
          text: "Second reply",
          ts: "1234567892.123"
        }
      ],
      channel_id: "C123456",
      thread_ts: "1234567890.123"
    }
  end

  def mock_openai_response(content)
    {
      "choices" => [
        {
          "message" => {
            "content" => content
          }
        }
      ]
    }
  end
end
