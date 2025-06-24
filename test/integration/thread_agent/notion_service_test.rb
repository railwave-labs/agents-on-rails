# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class NotionServiceTest < ActionDispatch::IntegrationTest
    def setup
      # Set up environment variables for testing
      ENV["THREAD_AGENT_NOTION_TOKEN"] = "test-notion-token"

      # Reset ThreadAgent configuration
      ThreadAgent.reset_configuration!

      # Create test data
      @workspace = create(:notion_workspace,
        slack_team_id: "T123456",
        access_token: "test-notion-token"
      )
      @database = create(:notion_database,
        notion_workspace: @workspace,
        notion_database_id: "test-db-123",
        name: "Meeting Notes"
      )

      # Set up realistic API responses
      @search_databases_response = {
        "object" => "list",
        "results" => [
          {
            "object" => "database",
            "id" => "test-db-123",
            "title" => [
              {
                "type" => "text",
                "text" => { "content" => "Meeting Notes" }
              }
            ],
            "properties" => {
              "title" => { "id" => "title", "type" => "title" },
              "status" => { "id" => "status", "type" => "select" }
            }
          }
        ],
        "has_more" => false,
        "next_cursor" => nil
      }

      @retrieve_database_response = {
        "object" => "database",
        "id" => "test-db-123",
        "title" => [
          {
            "type" => "text",
            "text" => { "content" => "Meeting Notes" }
          }
        ],
        "properties" => {
          "title" => { "id" => "title", "type" => "title" },
          "status" => { "id" => "status", "type" => "select" }
        }
      }

      @create_page_response = {
        "object" => "page",
        "id" => "test-page-456",
        "url" => "https://notion.so/test-page-456",
        "parent" => {
          "type" => "database_id",
          "database_id" => "test-db-123"
        },
        "properties" => {
          "title" => {
            "id" => "title",
            "type" => "title",
            "title" => [
              {
                "type" => "text",
                "text" => { "content" => "Test Page" }
              }
            ]
          }
        }
      }

      # Set up WebMock for external API calls
      WebMock.reset!
    end

    def teardown
      # Clean up environment variables
      ENV.delete("THREAD_AGENT_NOTION_TOKEN")

      # Reset WebMock
      WebMock.reset!
    end

    test "successfully orchestrates full NotionService workflow" do
      # Test the complete workflow: list databases -> get database -> create page

      # Stub search databases endpoint
      search_stub = stub_request(:post, "https://api.notion.com/v1/search")
        .with(
          headers: {
            "Authorization" => "Bearer test-notion-token",
            "Content-Type" => "application/json",
            "Notion-Version" => "2022-02-22"
          },
          body: {
            filter: { property: "object", value: "database" },
            start_cursor: nil
          }.to_json
        )
        .to_return(
          status: 200,
          body: @search_databases_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Stub retrieve database endpoint
      retrieve_stub = stub_request(:get, "https://api.notion.com/v1/databases/test-db-123")
        .with(
          headers: {
            "Authorization" => "Bearer test-notion-token",
            "Notion-Version" => "2022-02-22"
          }
        )
        .to_return(
          status: 200,
          body: @retrieve_database_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Stub create page endpoint
      create_stub = stub_request(:post, "https://api.notion.com/v1/pages")
        .with(
          headers: {
            "Authorization" => "Bearer test-notion-token",
            "Content-Type" => "application/json",
            "Notion-Version" => "2022-02-22"
          }
        )
        .to_return(
          status: 200,
          body: @create_page_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Initialize service
      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")

      # Test workflow steps

      # 1. List databases
      list_result = service.list_databases
      assert list_result.success?, "List databases should succeed"
      assert list_result.data.is_a?(Array), "Should return array of databases"
      assert_equal 1, list_result.data.length

      # 2. Get specific database
      get_result = service.get_database("test-db-123")
      assert get_result.success?, "Get database should succeed"
      assert_equal "test-db-123", get_result.data[:id]
      assert_equal "Meeting Notes", get_result.data[:title]

      # 3. Create page
      page_result = service.create_page(
        database_id: "test-db-123",
        properties: { "title" => "Test Page" },
        content: [ "This is a test page" ]
      )
      assert page_result.success?, "Create page should succeed"
      assert_equal "test-page-456", page_result.data[:id]
      assert_includes page_result.data[:url], "notion.so"

      # Verify all API calls were made
      assert_requested search_stub, times: 1
      assert_requested retrieve_stub, times: 1
      assert_requested create_stub, times: 1
    end

    test "properly handles Notion service retry behavior" do
      # Test retry logic for rate limiting and server errors
      retry_count = 0
      search_stub = stub_request(:post, "https://api.notion.com/v1/search")
        .to_return do |request|
          retry_count += 1
          if retry_count <= 2
            # Simulate rate limiting then server error
            status = retry_count == 1 ? 429 : 500
            { status: status, body: { error: "Too many requests" }.to_json }
          else
            {
              status: 200,
              body: @search_databases_response.to_json,
              headers: { "Content-Type" => "application/json" }
            }
          end
        end

      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")

      # Should succeed after retries
      result = service.list_databases
      assert result.success?, "Should succeed after retries"

      # Verify retry behavior worked correctly
      assert_equal 3, retry_count, "Should have retried twice before succeeding"
      assert_requested search_stub, times: 3
    end

    test "raises appropriate errors when Notion service fails persistently" do
      # Test error handling for persistent failures
      stub_request(:post, "https://api.notion.com/v1/search")
        .to_return(status: 401, body: { error: "Unauthorized" }.to_json)

      service = ThreadAgent::Notion::Service.new(token: "invalid-token")

      # Should return failure result (not raise exception)
      result = service.list_databases
      assert_not result.success?, "Should fail with unauthorized error"
      assert_includes result.error, "Operation failed after 3 retries"
    end

    test "validates input parameters before making Notion requests" do
      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")

      # Test get_database with missing ID
      result = service.get_database("")
      assert_not result.success?, "Should fail with missing database_id"
      assert_includes result.error, "Missing database_id"

      # Test create_page with missing database_id
      result = service.create_page(database_id: "", properties: {})
      assert_not result.success?, "Should fail with missing database_id"

      # Verify no API requests were made for invalid data
      assert_not_requested :post, "https://api.notion.com/v1/search"
      assert_not_requested :get, %r{https://api.notion.com/v1/databases/}
      assert_not_requested :post, "https://api.notion.com/v1/pages"
    end

    test "handles different page property types correctly" do
      # Test various property types that Notion supports
      create_stub = stub_request(:post, "https://api.notion.com/v1/pages")
        .to_return(
          status: 200,
          body: @create_page_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")

      # Test with various property types
      properties = {
        "title" => "Meeting Notes",
        "status" => "In Progress",
        "tags" => [ "important", "meeting" ],
        "date" => "2024-01-15"
      }

      result = service.create_page(
        database_id: "test-db-123",
        properties: properties,
        content: [ "Content block 1", "Content block 2" ]
      )

      assert result.success?, "Should handle various property types"

      # Verify request structure
      assert_requested :post, "https://api.notion.com/v1/pages" do |req|
        body = JSON.parse(req.body)

        # Verify payload structure
        assert_equal "test-db-123", body.dig("parent", "database_id")
        assert body["properties"].is_a?(Hash)
        assert body["children"].is_a?(Array)
        assert body["children"].length > 0

        true
      end
    end

    test "handles large content blocks without exceeding API limits" do
      # Test handling of large content arrays
      create_stub = stub_request(:post, "https://api.notion.com/v1/pages")
        .to_return(
          status: 200,
          body: @create_page_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")

      # Create large content array
      large_content = Array.new(50) { |i| "Content block #{i + 1} with some text" }

      result = service.create_page(
        database_id: "test-db-123",
        properties: { "title" => "Large Content Page" },
        content: large_content
      )

      assert result.success?, "Should handle large content arrays"

      # Verify all content was included
      assert_requested :post, "https://api.notion.com/v1/pages" do |req|
        body = JSON.parse(req.body)

        # Should have many children blocks
        assert body["children"].length > 0
        # Each content item should result in a block
        assert_operator body["children"].length, :<=, large_content.length

        true
      end
    end

    test "handles pagination correctly when listing databases" do
      # Test pagination handling for databases list
      page1_response = {
        "object" => "list",
        "results" => [
          {
            "object" => "database",
            "id" => "db-1",
            "title" => [ { "type" => "text", "text" => { "content" => "Database 1" } } ],
            "properties" => {}
          }
        ],
        "has_more" => true,
        "next_cursor" => "cursor-123"
      }

      page2_response = {
        "object" => "list",
        "results" => [
          {
            "object" => "database",
            "id" => "db-2",
            "title" => [ { "type" => "text", "text" => { "content" => "Database 2" } } ],
            "properties" => {}
          }
        ],
        "has_more" => false,
        "next_cursor" => nil
      }

      # Stub first page request
      page1_stub = stub_request(:post, "https://api.notion.com/v1/search")
        .with(
          body: {
            filter: { property: "object", value: "database" },
            start_cursor: nil
          }.to_json
        )
        .to_return(
          status: 200,
          body: page1_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      # Stub second page request
      page2_stub = stub_request(:post, "https://api.notion.com/v1/search")
        .with(
          body: {
            filter: { property: "object", value: "database" },
            start_cursor: "cursor-123"
          }.to_json
        )
        .to_return(
          status: 200,
          body: page2_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")

      result = service.list_databases
      assert result.success?, "Should handle pagination correctly"
      assert_equal 2, result.data.length, "Should return all databases across pages"

      # Verify both requests were made
      assert_requested page1_stub, times: 1
      assert_requested page2_stub, times: 1
    end

    test "uses correct API version and headers for all requests" do
      # Test that all requests include proper headers
      search_stub = stub_request(:post, "https://api.notion.com/v1/search")
      retrieve_stub = stub_request(:get, "https://api.notion.com/v1/databases/test-db-123")
      create_stub = stub_request(:post, "https://api.notion.com/v1/pages")

      # Set up successful responses
      search_stub.to_return(
        status: 200,
        body: @search_databases_response.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      retrieve_stub.to_return(
        status: 200,
        body: @search_databases_response.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      create_stub.to_return(
        status: 200,
        body: @search_databases_response.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")

      # Make various API calls
      service.list_databases
      service.get_database("test-db-123")
      service.create_page(database_id: "test-db-123", properties: {})

      # Verify all requests had correct headers
      assert_requested :post, "https://api.notion.com/v1/search" do |req|
        assert_equal "Bearer test-notion-token", req.headers["Authorization"]
        assert_equal "application/json", req.headers["Content-Type"]
        assert_equal "2022-02-22", req.headers["Notion-Version"]
        true
      end

      assert_requested :post, "https://api.notion.com/v1/pages" do |req|
        assert_equal "Bearer test-notion-token", req.headers["Authorization"]
        assert_equal "application/json", req.headers["Content-Type"]
        assert_equal "2022-02-22", req.headers["Notion-Version"]
        true
      end

      assert_requested :get, "https://api.notion.com/v1/databases/test-db-123" do |req|
        assert_equal "Bearer test-notion-token", req.headers["Authorization"]
        assert_equal "2022-02-22", req.headers["Notion-Version"]
        true
      end
    end

    # Initial test - will expand this file progressively
    test "basic service initialization" do
      service = ThreadAgent::Notion::Service.new(token: "test-notion-token")
      assert_not_nil service
      assert_equal "test-notion-token", service.token
    end
  end
end
