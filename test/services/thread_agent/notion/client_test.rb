# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Notion::ClientTest < ActiveSupport::TestCase
  def setup
    # Reset configuration before each test
    ThreadAgent.reset_configuration!
  end

  def teardown
    # Reset configuration after each test
    ThreadAgent.reset_configuration!
  end

  test "initializes with valid token and timeout" do
    client = ThreadAgent::Notion::Client.new(
      token: "test-token",
      timeout: 30
    )

    assert_equal "test-token", client.token
    assert_equal 30, client.timeout
  end

  test "uses ThreadAgent configuration when no parameters provided" do
    ThreadAgent.configure do |config|
      config.notion_token = "config-token"
    end

    client = ThreadAgent::Notion::Client.new

    assert_equal "config-token", client.token
    assert_equal ThreadAgent.configuration.default_timeout, client.timeout # uses configuration default_timeout
  end

  test "parameter values override configuration values" do
    ThreadAgent.configure do |config|
      config.notion_token = "config-token"
    end

    client = ThreadAgent::Notion::Client.new(
      token: "override-token",
      timeout: 25
    )

    assert_equal "override-token", client.token
    assert_equal 25, client.timeout
  end

  test "raises NotionError when token missing" do
    error = assert_raises(ThreadAgent::NotionError) do
      ThreadAgent::Notion::Client.new(token: nil)
    end

    assert_equal "Missing Notion API token", error.message
  end

  test "raises NotionError when token empty" do
    error = assert_raises(ThreadAgent::NotionError) do
      ThreadAgent::Notion::Client.new(token: "")
    end

    assert_equal "Missing Notion API token", error.message
  end

  test "initializes Notion client with correct parameters" do
    client_instance = ThreadAgent::Notion::Client.new(
      token: "test-token",
      timeout: 30
    )

    Notion::Client.expects(:new).with(
      token: "test-token",
      timeout: 30
    ).returns(mock("Notion::Client"))

    client_instance.client
  end

  test "raises Error when client initialization fails" do
    Notion::Client.expects(:new).raises(StandardError.new("Network error"))

    client_instance = ThreadAgent::Notion::Client.new(
      token: "test-token"
    )

    error = assert_raises(ThreadAgent::Error) do
      client_instance.client
    end

    assert_includes error.message, "Unexpected error: Network error"
  end

  test "memoizes client after first initialization" do
    client_instance = ThreadAgent::Notion::Client.new(
      token: "test-token"
    )

    mock_client = mock("Notion::Client")
    Notion::Client.expects(:new).once.returns(mock_client)

    # Call client twice - should only initialize once
    first_client = client_instance.client
    second_client = client_instance.client

    assert_same first_client, second_client
  end
end
