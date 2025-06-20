# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class NotionDatabaseTest < ActiveSupport::TestCase
    # Validation tests
    test "should be valid with valid attributes" do
      database = build(:notion_database)
      assert database.valid?
    end

    test "should require name" do
      database = build(:notion_database, name: nil)
      assert_not database.valid?
      assert_includes database.errors[:name], "can't be blank"
    end

    test "should require notion_database_id" do
      database = build(:notion_database, notion_database_id: nil)
      assert_not database.valid?
      assert_includes database.errors[:notion_database_id], "can't be blank"
    end

    test "should require unique notion_database_id within workspace scope" do
      workspace = create(:notion_workspace)
      create(:notion_database, notion_workspace: workspace, notion_database_id: "db_123")
      duplicate = build(:notion_database, notion_workspace: workspace, notion_database_id: "db_123")
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:notion_database_id], "has already been taken"
    end

    test "should allow same notion_database_id in different workspaces" do
      workspace1 = create(:notion_workspace)
      workspace2 = create(:notion_workspace)

      database1 = create(:notion_database, notion_workspace: workspace1, notion_database_id: "db_123")
      database2 = build(:notion_database, notion_workspace: workspace2, notion_database_id: "db_123")

      assert database2.valid?
    end

    test "should require notion_workspace" do
      database = build(:notion_database, notion_workspace: nil)
      assert_not database.valid?
      assert_includes database.errors[:notion_workspace], "must exist"
    end

    # Association tests
    test "should belong to notion_workspace" do
      workspace = create(:notion_workspace)
      database = create(:notion_database, notion_workspace: workspace)
      assert_equal workspace, database.notion_workspace
    end

    # Scope tests
    test "by_database_id scope should find database by notion_database_id" do
      database = create(:notion_database, notion_database_id: "db_123")
      result = NotionDatabase.by_database_id("db_123")
      assert_includes result, database
    end

    test "by_workspace scope should find databases by workspace" do
      workspace = create(:notion_workspace)
      database = create(:notion_database, notion_workspace: workspace)
      result = NotionDatabase.by_workspace(workspace)
      assert_includes result, database
    end

    # Class method tests
    test "create_database! should create valid database with all required attributes" do
      workspace = create(:notion_workspace)
      database = NotionDatabase.create_database!(
        workspace: workspace,
        notion_database_id: "db_new",
        name: "New Database"
      )

      assert database.persisted?
      assert_equal workspace, database.notion_workspace
      assert_equal "db_new", database.notion_database_id
      assert_equal "New Database", database.name
      assert database.active?
    end

    # Enum tests
    test "should use default status when not provided" do
      database = create(:notion_database)
      assert_equal "active", database.status
    end

    test "should allow inactive status" do
      database = create(:notion_database, :inactive)
      assert database.inactive?
    end
  end
end
