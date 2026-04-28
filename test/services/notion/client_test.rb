# frozen_string_literal: true

require "test_helper"

class Notion::ApiClientTest < ActiveSupport::TestCase
  def setup
    # Reset configuration before each test
    AppConfig.reset_from_env!
  end

  def teardown
    # Reset configuration after each test
    AppConfig.reset_from_env!
  end

  test "initializes with valid token and timeout" do
    client = Notion::ApiClient.new(
      token: "test-token",
      timeout: 30
    )

    assert_equal "test-token", client.token
    assert_equal 30, client.timeout
  end

  test "uses AppConfig when no parameters provided" do
    original = AppConfig.instance.notion_token
    AppConfig.instance.notion_token = "config-token"

    client = Notion::ApiClient.new

    assert_equal "config-token", client.token
    assert_equal AppConfig.default_timeout, client.timeout
  ensure
    AppConfig.instance.notion_token = original
  end

  test "parameter values override configuration values" do
    AppConfig.instance do |config|
      config.notion_token = "config-token"
    end

    client = Notion::ApiClient.new(
      token: "override-token",
      timeout: 25
    )

    assert_equal "override-token", client.token
    assert_equal 25, client.timeout
  end

  test "raises NotionError when token missing and no AppConfig token" do
    original = AppConfig.instance.notion_token
    AppConfig.instance.notion_token = nil

    error = assert_raises(Notion::Error) do
      Notion::ApiClient.new(token: nil)
    end

    assert_equal "Missing Notion API token", error.message
  ensure
    AppConfig.instance.notion_token = original
  end

  test "raises NotionError when token empty and no AppConfig token" do
    original = AppConfig.instance.notion_token
    AppConfig.instance.notion_token = nil

    error = assert_raises(Notion::Error) do
      Notion::ApiClient.new(token: "")
    end

    assert_equal "Missing Notion API token", error.message
  ensure
    AppConfig.instance.notion_token = original
  end

  test "initializes Notion client with correct parameters" do
    client_instance = Notion::ApiClient.new(
      token: "test-token",
      timeout: 30
    )

    mock_gem_client = mock("gem_notion_client")
    ::Notion::Client.expects(:new).with(
      token: "test-token",
      timeout: 30
    ).returns(mock_gem_client)

    assert_same mock_gem_client, client_instance.client
  end

  test "raises Error when client initialization fails" do
    ::Notion::Client.expects(:new).raises(StandardError.new("Network error"))

    client_instance = Notion::ApiClient.new(
      token: "test-token"
    )

    error = assert_raises(ApplicationError) do
      client_instance.client
    end

    assert_includes error.message, "Unexpected error: Network error"
  end

  test "memoizes client after first initialization" do
    client_instance = Notion::ApiClient.new(
      token: "test-token"
    )

    mock_gem_client = mock("gem_notion_client")
    ::Notion::Client.expects(:new).once.returns(mock_gem_client)

    first_client  = client_instance.client
    second_client = client_instance.client

    assert_same first_client, second_client
  end
end
