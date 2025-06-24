# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Notion::ServiceTest < ActiveSupport::TestCase
  def setup
    @service = ThreadAgent::Notion::Service.new(token: "test-token")
    @database_id = "b8a5a5e2-8b3a-4f4b-9e8c-1234567890ab"
    @workspace_id = "workspace_123"
  end

  # Initialization tests
  test "initializes with default configuration" do
    service = ThreadAgent::Notion::Service.new(token: "test-token")

    assert_equal "test-token", service.client.token
    assert_equal 3, service.retry_handler.max_attempts
  end

  test "initializes with custom configuration" do
    service = ThreadAgent::Notion::Service.new(
      token: "custom-token",
      timeout: 60,
      max_retries: 5
    )

    assert_equal "custom-token", service.client.token
    assert_equal 60, service.client.timeout
    assert_equal 5, service.retry_handler.max_attempts
  end

  # list_databases tests
  test "list_databases returns success with transformed database data" do
    mock_api_response = {
      "has_more" => false,
      "next_cursor" => nil,
      "results" => [
        {
          "id" => "db_123",
          "title" => [
            { "plain_text" => "Test Database", "text" => { "content" => "Test Database" } }
          ],
          "properties" => {
            "Name" => { "type" => "title", "id" => "title" },
            "Status" => { "type" => "select", "id" => "select_1" }
          }
        },
        {
          "id" => "db_456",
          "title" => [
            { "plain_text" => "Another Database" }
          ],
          "properties" => {
            "Name" => { "type" => "title", "id" => "title" }
          }
        }
      ]
    }

    @service.client.expects(:client).returns(mock_notion_client = mock("notion_client"))
    mock_notion_client.expects(:search).with(
      filter: { property: "object", value: "database" },
      start_cursor: nil
    ).returns(mock_api_response)

    result = @service.list_databases

    assert result.success?
    databases = result.data
    assert_equal 2, databases.length

    first_db = databases.first
    assert_equal "db_123", first_db[:notion_database_id]
    assert_equal "Test Database", first_db[:name]
    assert_equal({ "Name" => { type: "title", id: "title" }, "Status" => { type: "select", id: "select_1" } }, first_db[:properties])
    assert_equal mock_api_response["results"].first, first_db[:json_data]
  end

  test "list_databases handles pagination correctly" do
    first_response = {
      "has_more" => true,
      "next_cursor" => "cursor_123",
      "results" => [
        {
          "id" => "db_page1",
          "title" => [ { "plain_text" => "Database Page 1" } ],
          "properties" => {}
        }
      ]
    }

    second_response = {
      "has_more" => false,
      "next_cursor" => nil,
      "results" => [
        {
          "id" => "db_page2",
          "title" => [ { "plain_text" => "Database Page 2" } ],
          "properties" => {}
        }
      ]
    }

    @service.client.expects(:client).returns(mock_notion_client = mock("notion_client")).twice
    mock_notion_client.expects(:search).with(
      filter: { property: "object", value: "database" },
      start_cursor: nil
    ).returns(first_response)

    mock_notion_client.expects(:search).with(
      filter: { property: "object", value: "database" },
      start_cursor: "cursor_123"
    ).returns(second_response)

    result = @service.list_databases

    assert result.success?
    databases = result.data
    assert_equal 2, databases.length
    assert_equal "db_page1", databases.first[:notion_database_id]
    assert_equal "db_page2", databases.last[:notion_database_id]
  end

  test "list_databases with workspace_id parameter" do
    mock_api_response = {
      "has_more" => false,
      "results" => [
        {
          "id" => "db_123",
          "title" => [ { "plain_text" => "Test Database" } ],
          "properties" => {}
        }
      ]
    }

    @service.client.expects(:client).returns(mock_notion_client = mock("notion_client"))
    mock_notion_client.expects(:search).returns(mock_api_response)

    result = @service.list_databases(workspace_id: @workspace_id)

    assert result.success?
    database = result.data.first
    assert_equal @workspace_id, database[:workspace_id]
  end

  test "list_databases handles NotionError" do
    @service.retry_handler.expects(:retry_with).raises(ThreadAgent::NotionError.new("API error"))

    result = @service.list_databases

    assert result.failure?
    assert_equal "API error", result.error
  end

  test "list_databases handles generic error" do
    @service.retry_handler.expects(:retry_with).raises(StandardError.new("Network error"))

    result = @service.list_databases

    assert result.failure?
    assert_equal "Unexpected error: Network error", result.error
  end

  # get_database tests
  test "get_database returns success with transformed database data" do
    mock_api_response = {
      "id" => @database_id,
      "title" => [
        { "plain_text" => "Project Tasks", "text" => { "content" => "Project Tasks" } }
      ],
      "properties" => {
        "Name" => { "type" => "title", "id" => "title" },
        "Status" => { "type" => "select", "id" => "select_1" },
        "Assignee" => { "type" => "people", "id" => "people_1" }
      }
    }

    @service.client.expects(:client).returns(mock_notion_client = mock("notion_client"))
    mock_notion_client.expects(:database).with(database_id: @database_id).returns(mock_api_response)

    result = @service.get_database(@database_id)

    assert result.success?
    database = result.data
    assert_equal @database_id, database[:notion_database_id]
    assert_equal "Project Tasks", database[:name]
    expected_properties = {
      "Name" => { type: "title", id: "title" },
      "Status" => { type: "select", id: "select_1" },
      "Assignee" => { type: "people", id: "people_1" }
    }
    assert_equal expected_properties, database[:properties]
    assert_equal mock_api_response, database[:json_data]
  end

  test "get_database returns failure when database_id is missing" do
    result = @service.get_database(nil)

    assert result.failure?
    assert_equal "Missing database_id", result.error
  end

  test "get_database returns failure when database_id is blank" do
    result = @service.get_database("")

    assert result.failure?
    assert_equal "Missing database_id", result.error
  end

  test "get_database handles NotionError" do
    @service.retry_handler.expects(:retry_with).raises(ThreadAgent::NotionError.new("API error"))

    result = @service.get_database(@database_id)

    assert result.failure?
    assert_equal "API error", result.error
  end

  test "get_database handles generic error" do
    @service.retry_handler.expects(:retry_with).raises(StandardError.new("Network error"))

    result = @service.get_database(@database_id)

    assert result.failure?
    assert_equal "Unexpected error: Network error", result.error
  end

  # Helper method tests
  test "extract_title_from_notion_response handles plain_text format" do
    title_array = [
      { "plain_text" => "Test Title", "text" => { "content" => "Test Title" } }
    ]

    result = @service.send(:extract_title_from_notion_response, title_array)
    assert_equal "Test Title", result
  end

  test "extract_title_from_notion_response handles text.content format" do
    title_array = [
      { "text" => { "content" => "Another Title" } }
    ]

    result = @service.send(:extract_title_from_notion_response, title_array)
    assert_equal "Another Title", result
  end

  test "extract_title_from_notion_response handles multiple segments" do
    title_array = [
      { "plain_text" => "Part 1" },
      { "plain_text" => " Part 2" }
    ]

    result = @service.send(:extract_title_from_notion_response, title_array)
    assert_equal "Part 1 Part 2", result
  end

  test "extract_title_from_notion_response handles empty array" do
    result = @service.send(:extract_title_from_notion_response, [])
    assert_equal "Untitled", result
  end

  test "extract_title_from_notion_response handles nil" do
    result = @service.send(:extract_title_from_notion_response, nil)
    assert_equal "Untitled", result
  end

  test "extract_title_from_notion_response handles empty strings" do
    title_array = [
      { "plain_text" => "", "text" => { "content" => "" } }
    ]

    result = @service.send(:extract_title_from_notion_response, title_array)
    assert_equal "Untitled", result
  end

  test "extract_properties_from_response transforms properties correctly" do
    properties_hash = {
      "Name" => { "type" => "title", "id" => "title_id" },
      "Status" => { "type" => "select", "id" => "select_id" },
      "Date" => { "type" => "date", "id" => "date_id" }
    }

    result = @service.send(:extract_properties_from_response, properties_hash)
    expected = {
      "Name" => { type: "title", id: "title_id" },
      "Status" => { type: "select", id: "select_id" },
      "Date" => { type: "date", id: "date_id" }
    }
    assert_equal expected, result
  end

  test "extract_properties_from_response handles empty hash" do
    result = @service.send(:extract_properties_from_response, {})
    assert_equal({}, result)
  end

  test "extract_properties_from_response handles nil" do
    result = @service.send(:extract_properties_from_response, nil)
    assert_equal({}, result)
  end

  test "transform_database_from_api creates correct structure" do
    api_response = {
      "id" => "db_123",
      "title" => [ { "plain_text" => "Test Database" } ],
      "properties" => {
        "Name" => { "type" => "title", "id" => "title_id" }
      }
    }

    result = @service.send(:transform_database_from_api, api_response, "workspace_456")

    expected = {
      id: "db_123",
      notion_database_id: "db_123",
      name: "Test Database",
      title: "Test Database",
      properties: { "Name" => { type: "title", id: "title_id" } },
      json_data: api_response,
      workspace_id: "workspace_456"
    }
    assert_equal expected, result
  end

  test "transform_database_from_api without workspace_id" do
    api_response = {
      "id" => "db_123",
      "title" => [ { "plain_text" => "Test Database" } ],
      "properties" => {}
    }

    result = @service.send(:transform_database_from_api, api_response)

    assert_equal "db_123", result[:notion_database_id]
    assert_equal "Test Database", result[:name]
    assert_nil result[:workspace_id]
    assert_equal api_response, result[:json_data]
  end

  # create_page tests
  test "create_page with basic properties and content" do
    database_id = "test-database-id"
    properties = {
      "Name" => "Test Page",
      "Status" => :in_progress,
      "Due Date" => Date.new(2024, 6, 23),
      "Completed" => true
    }
    content = [
      "This is a paragraph",
      { type: :bulleted_list, content: "First bullet" },
      { type: :heading_1, content: "Main Heading" }
    ]

    expected_payload = {
      parent: { database_id: database_id },
      properties: {
        "Name" => { "title" => [ { "text" => { "content" => "Test Page" } } ] },
        "Status" => { "select" => { "name" => "in_progress" } },
        "Due Date" => { "date" => { "start" => "2024-06-23" } },
        "Completed" => { "checkbox" => true }
      },
      children: [
        {
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => {
            "rich_text" => [ { "type" => "text", "text" => { "content" => "This is a paragraph" } } ]
          }
        },
        {
          "object" => "block",
          "type" => "bulleted_list_item",
          "bulleted_list_item" => {
            "rich_text" => [ { "type" => "text", "text" => { "content" => "First bullet" } } ]
          }
        },
        {
          "object" => "block",
          "type" => "heading_1",
          "heading_1" => {
            "rich_text" => [ { "type" => "text", "text" => { "content" => "Main Heading" } } ]
          }
        }
      ]
    }

    mock_response = {
      "id" => "page-id-123",
      "url" => "https://notion.so/page-id-123",
      "created_time" => "2024-06-23T10:00:00.000Z",
      "properties" => {
        "Name" => {
          "type" => "title",
          "title" => [ { "text" => { "content" => "Test Page" } } ]
        }
      }
    }

    @service.retry_handler.expects(:retry_with).yields.returns(mock_response)
    @service.client.client.expects(:create_page).with(expected_payload).returns(mock_response)

    result = @service.create_page(database_id: database_id, properties: properties, content: content)

    assert result.success?
    assert_equal "page-id-123", result.data[:id]
    assert_equal "https://notion.so/page-id-123", result.data[:url]
    assert_equal "Test Page", result.data[:title]
  end

  test "create_page with empty properties and content" do
    database_id = "test-database-id"

    expected_payload = {
      parent: { database_id: database_id },
      properties: {},
      children: []
    }

    mock_response = {
      "id" => "page-id-456",
      "url" => "https://notion.so/page-id-456",
      "created_time" => "2024-06-23T10:00:00.000Z",
      "properties" => {}
    }

    @service.retry_handler.expects(:retry_with).yields.returns(mock_response)
    @service.client.client.expects(:create_page).with(expected_payload).returns(mock_response)

    result = @service.create_page(database_id: database_id)

    assert result.success?
    assert_equal "page-id-456", result.data[:id]
    assert_equal "Untitled", result.data[:title]
  end

  test "create_page property mapping handles various data types" do
    database_id = "test-database-id"
    properties = {
      string_prop: "Simple string",
      symbol_prop: :active,
      date_prop: Date.new(2024, 6, 23),
      time_prop: Time.parse("2024-06-23 15:30:00 UTC"),
      boolean_prop: false,
      array_prop: [ :tag1, :tag2, "tag3" ],
      hash_prop: { "rich_text" => [ { "text" => { "content" => "Custom format" } } ] },
      number_prop: 42
    }

    expected_properties = {
      "string_prop" => { "title" => [ { "text" => { "content" => "Simple string" } } ] },
      "symbol_prop" => { "select" => { "name" => "active" } },
      "date_prop" => { "date" => { "start" => "2024-06-23" } },
      "time_prop" => { "date" => { "start" => "2024-06-23" } },
      "boolean_prop" => { "checkbox" => false },
      "array_prop" => { "multi_select" => [
        { "name" => "tag1" },
        { "name" => "tag2" },
        { "name" => "tag3" }
      ] },
      "hash_prop" => { "rich_text" => [ { "text" => { "content" => "Custom format" } } ] },
      "number_prop" => { "rich_text" => [ { "text" => { "content" => "42" } } ] }
    }

    mock_response = {
      "id" => "page-id-789",
      "url" => "https://notion.so/page-id-789",
      "created_time" => "2024-06-23T10:00:00.000Z",
      "properties" => {}
    }

    @service.retry_handler.expects(:retry_with).yields.returns(mock_response)
    @service.client.client.expects(:create_page).with do |payload|
      payload[:properties] == expected_properties
    end.returns(mock_response)

    result = @service.create_page(database_id: database_id, properties: properties)

    assert result.success?
  end

  test "create_page content blocks handle various types" do
    database_id = "test-database-id"
    content = [
      "Simple paragraph",
      { type: "bulleted_list_item", content: "Bullet point" },
      { type: "numbered_list_item", content: "Numbered item" },
      { type: "heading_1", content: "H1 Title" },
      { type: "heading_2", content: "H2 Subtitle" },
      { type: "to_do", content: "Task item", checked: true },
      { type: "unknown_type", content: "Falls back to paragraph" },
      123  # Non-string falls back to paragraph
    ]

    expected_children = [
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => { "rich_text" => [ { "type" => "text", "text" => { "content" => "Simple paragraph" } } ] }
      },
      {
        "object" => "block",
        "type" => "bulleted_list_item",
        "bulleted_list_item" => { "rich_text" => [ { "type" => "text", "text" => { "content" => "Bullet point" } } ] }
      },
      {
        "object" => "block",
        "type" => "numbered_list_item",
        "numbered_list_item" => { "rich_text" => [ { "type" => "text", "text" => { "content" => "Numbered item" } } ] }
      },
      {
        "object" => "block",
        "type" => "heading_1",
        "heading_1" => { "rich_text" => [ { "type" => "text", "text" => { "content" => "H1 Title" } } ] }
      },
      {
        "object" => "block",
        "type" => "heading_2",
        "heading_2" => { "rich_text" => [ { "type" => "text", "text" => { "content" => "H2 Subtitle" } } ] }
      },
      {
        "object" => "block",
        "type" => "to_do",
        "to_do" => {
          "rich_text" => [ { "type" => "text", "text" => { "content" => "Task item" } } ],
          "checked" => true
        }
      },
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => { "rich_text" => [ { "type" => "text", "text" => { "content" => "Falls back to paragraph" } } ] }
      },
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => { "rich_text" => [ { "type" => "text", "text" => { "content" => "123" } } ] }
      }
    ]

    mock_response = {
      "id" => "page-id-content",
      "url" => "https://notion.so/page-id-content",
      "created_time" => "2024-06-23T10:00:00.000Z",
      "properties" => {}
    }

    @service.retry_handler.expects(:retry_with).yields.returns(mock_response)
    @service.client.client.expects(:create_page).with do |payload|
      payload[:children] == expected_children
    end.returns(mock_response)

    result = @service.create_page(database_id: database_id, content: content)

    assert result.success?
  end

  test "create_page handles NotionError" do
    @service.retry_handler.expects(:retry_with).raises(ThreadAgent::NotionError.new("API error"))

    result = @service.create_page(database_id: "test-id")

    assert result.failure?
    assert_equal "API error", result.error
  end

  test "create_page handles generic error" do
    @service.retry_handler.expects(:retry_with).raises(StandardError.new("Network error"))

    result = @service.create_page(database_id: "test-id")

    assert result.failure?
    assert_equal "Unexpected error: Network error", result.error
  end

  test "create_page uses retry_handler for resilience" do
    database_id = "test-database-id"
    properties = { "Name" => "Test Page" }

    mock_response = {
      "id" => "page-id-retry",
      "url" => "https://notion.so/page-id-retry",
      "created_time" => "2024-06-23T10:00:00.000Z",
      "properties" => {
        "Name" => {
          "type" => "title",
          "title" => [ { "text" => { "content" => "Test Page" } } ]
        }
      }
    }

    # Verify retry_handler is called (it handles the retry logic internally)
    @service.retry_handler.expects(:retry_with).yields.returns(mock_response)
    @service.client.client.expects(:create_page).returns(mock_response)

    result = @service.create_page(database_id: database_id, properties: properties)

    assert result.success?
    assert_equal "page-id-retry", result.data[:id]
    assert_equal "Test Page", result.data[:title]
  end
end
