# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class NotionWorkspaceTest < ActiveSupport::TestCase
    def setup
      @valid_attributes = {
        name: "Test Workspace",
        notion_workspace_id: "workspace_123",
        access_token: "secret_token_abc",
        slack_team_id: "T12345678",
        status: "active"
      }
    end

    # Validation tests
    test "should be valid with valid attributes" do
      workspace = NotionWorkspace.new(@valid_attributes)
      assert workspace.valid?
    end

    test "should require name" do
      workspace = NotionWorkspace.new(@valid_attributes.except(:name))
      assert_not workspace.valid?
      assert_includes workspace.errors[:name], "can't be blank"
    end

    test "should require name to be at least 3 characters" do
      workspace = NotionWorkspace.new(@valid_attributes.merge(name: "ab"))
      assert_not workspace.valid?
      assert_includes workspace.errors[:name], "is too short (minimum is 3 characters)"
    end

    test "should require name to be at most 100 characters" do
      long_name = "a" * 101
      workspace = NotionWorkspace.new(@valid_attributes.merge(name: long_name))
      assert_not workspace.valid?
      assert_includes workspace.errors[:name], "is too long (maximum is 100 characters)"
    end

    test "should require notion_workspace_id" do
      workspace = NotionWorkspace.new(@valid_attributes.except(:notion_workspace_id))
      assert_not workspace.valid?
      assert_includes workspace.errors[:notion_workspace_id], "can't be blank"
    end

    test "should require unique notion_workspace_id" do
      NotionWorkspace.create!(@valid_attributes)
      duplicate = NotionWorkspace.new(@valid_attributes.merge(slack_team_id: "T87654321"))
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:notion_workspace_id], "has already been taken"
    end

    test "should require access_token" do
      workspace = NotionWorkspace.new(@valid_attributes.except(:access_token))
      assert_not workspace.valid?
      assert_includes workspace.errors[:access_token], "can't be blank"
    end

    test "should require slack_team_id" do
      workspace = NotionWorkspace.new(@valid_attributes.except(:slack_team_id))
      assert_not workspace.valid?
      assert_includes workspace.errors[:slack_team_id], "can't be blank"
    end

    test "should require unique slack_team_id" do
      NotionWorkspace.create!(@valid_attributes)
      duplicate = NotionWorkspace.new(@valid_attributes.merge(notion_workspace_id: "workspace_456"))
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:slack_team_id], "has already been taken"
    end

    test "should require slack_team_id to be at most 255 characters" do
      long_team_id = "T" + ("a" * 255)  # 256 characters total, exceeds limit
      workspace = NotionWorkspace.new(@valid_attributes.merge(slack_team_id: long_team_id))
      assert_not workspace.valid?
      assert_includes workspace.errors[:slack_team_id], "is too long (maximum is 255 characters)"
    end

    test "should use default status when not provided" do
      workspace = NotionWorkspace.new(@valid_attributes.except(:status))
      assert workspace.valid?
      workspace.save!
      assert_equal "active", workspace.status
    end

    # Scope tests
    test "by_workspace_id scope should find workspace by notion_workspace_id" do
      workspace = NotionWorkspace.create!(@valid_attributes)
      result = NotionWorkspace.by_workspace_id("workspace_123")
      assert_includes result, workspace
    end

    test "by_slack_team scope should find workspace by slack_team_id" do
      workspace = NotionWorkspace.create!(@valid_attributes)
      result = NotionWorkspace.by_slack_team("T12345678")
      assert_includes result, workspace
    end

    # Class method tests
    test "find_by_workspace_id should return workspace with matching notion_workspace_id" do
      workspace = NotionWorkspace.create!(@valid_attributes)
      found = NotionWorkspace.find_by_workspace_id("workspace_123")
      assert_equal workspace, found
    end

    test "find_by_workspace_id should return nil when no match found" do
      found = NotionWorkspace.find_by_workspace_id("nonexistent")
      assert_nil found
    end

    test "find_by_slack_team should return workspace with matching slack_team_id" do
      workspace = NotionWorkspace.create!(@valid_attributes)
      found = NotionWorkspace.find_by_slack_team("T12345678")
      assert_equal workspace, found
    end

    test "find_by_slack_team should return nil when no match found" do
      found = NotionWorkspace.find_by_slack_team("nonexistent")
      assert_nil found
    end

    test "create_workspace! should create valid workspace with all required attributes" do
      workspace = NotionWorkspace.create_workspace!(
        name: "New Workspace",
        notion_workspace_id: "workspace_new",
        access_token: "token_new",
        slack_team_id: "T11111111"
      )

      assert workspace.persisted?
      assert_equal "New Workspace", workspace.name
      assert_equal "workspace_new", workspace.notion_workspace_id
      assert_equal "token_new", workspace.access_token
      assert_equal "T11111111", workspace.slack_team_id
      assert workspace.active?
    end
  end
end
