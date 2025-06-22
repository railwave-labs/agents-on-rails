# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class TemplateTest < ActiveSupport::TestCase
    # Basic creation tests
    test "should create template with valid attributes" do
      template = build(:template)
      assert template.valid?, template.errors.full_messages.join(", ")
      assert template.save
    end

    test "should create template with minimal attributes" do
      template = build(:template, :minimal)
      assert template.valid?
      assert template.save
      assert_equal "active", template.status # default status
    end

    # Validation tests
    test "should require name" do
      template = build(:template, name: nil)
      assert_not template.valid?
      assert_includes template.errors[:name], "can't be blank"
    end

    test "should require name to be at least 3 characters" do
      template = build(:template, :invalid_name_too_short)
      assert_not template.valid?
      assert_includes template.errors[:name], "is too short (minimum is 3 characters)"
    end

    test "should require name to be at most 100 characters" do
      template = build(:template, :invalid_name_too_long)
      assert_not template.valid?
      assert_includes template.errors[:name], "is too long (maximum is 100 characters)"
    end

    test "should require unique name" do
      create(:template, name: "Duplicate Template")
      duplicate = build(:template, name: "Duplicate Template")
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end

    test "should require content" do
      template = build(:template, content: nil)
      assert_not template.valid?
      assert_includes template.errors[:content], "can't be blank"
    end

    test "should validate description length" do
      template = build(:template, :invalid_description_too_long)
      assert_not template.valid?
      assert_includes template.errors[:description], "is too long (maximum is 500 characters)"
    end

    # Content handling tests
    test "should allow unicode in content" do
      template = build(:template, :with_unicode_content)
      assert template.valid?
      assert template.save
    end

    test "should preserve formatting in content" do
      template = build(:template, :with_formatting)
      assert template.valid?
      assert template.save
      assert template.content.include?("\n")
    end

    # Status tests
    test "should validate status inclusion" do
      assert_raises(ArgumentError) do
        build(:template, status: "invalid_status")
      end
    end

    test "should have correct enums" do
      expected_statuses = %w[active inactive]
      assert_equal expected_statuses, ThreadAgent::Template.statuses.keys
    end

    # Scope tests
    test "should have correct scopes" do
      active_template = create(:template, status: "active")
      inactive_template = create(:template, :inactive)

      assert_includes ThreadAgent::Template.active, active_template
      assert_not_includes ThreadAgent::Template.active, inactive_template

      assert_includes ThreadAgent::Template.inactive, inactive_template
      assert_not_includes ThreadAgent::Template.inactive, active_template
    end

    # Instance method tests
    test "active? should work correctly" do
      active_template = create(:template, status: "active")
      inactive_template = create(:template, :inactive)

      assert active_template.active?
      assert_not inactive_template.active?
    end

    test "inactive? should work correctly" do
      active_template = create(:template, status: "active")
      inactive_template = create(:template, :inactive)

      assert_not active_template.inactive?
      assert inactive_template.inactive?
    end

    test "should set correct table name" do
      assert_equal "thread_agent_templates", ThreadAgent::Template.table_name
    end
  end
end
