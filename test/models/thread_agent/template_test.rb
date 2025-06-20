# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class TemplateTest < ActiveSupport::TestCase
    def setup
      @valid_attributes = {
        name: "Test Template",
        content: "Hello {{name}}, welcome to our system!",
        status: "active",
        description: "A test template for unit testing"
      }
    end

    # Basic creation tests
    test "should create template with valid attributes" do
      template = Template.new(@valid_attributes)
      assert template.valid?, template.errors.full_messages.join(", ")
      assert template.save
    end

    test "should create template with minimal attributes" do
      template = Template.new(
        name: "Minimal Template",
        content: "Basic content"
      )
      assert template.valid?
      assert template.save
      assert_equal "active", template.status # default status
    end

    # Validation tests
    test "should require name" do
      template = Template.new(@valid_attributes.except(:name))
      assert_not template.valid?
      assert_includes template.errors[:name], "can't be blank"
    end

    test "should require content" do
      template = Template.new(@valid_attributes.except(:content))
      assert_not template.valid?
      assert_includes template.errors[:content], "can't be blank"
    end

    test "should require status" do
      template = Template.new(@valid_attributes.except(:status))
      # Rails sets default status, so this should be valid
      assert template.valid?
      assert_equal "active", template.status
    end

    test "should validate name length" do
      # Too short
      template = Template.new(@valid_attributes.merge(name: "ab"))
      assert_not template.valid?
      assert_includes template.errors[:name], "is too short (minimum is 3 characters)"

      # Too long
      long_name = "a" * 101
      template = Template.new(@valid_attributes.merge(name: long_name))
      assert_not template.valid?
      assert_includes template.errors[:name], "is too long (maximum is 100 characters)"
    end

    test "should validate name uniqueness" do
      Template.create!(@valid_attributes)

      duplicate = Template.new(@valid_attributes)
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end

    test "should validate description length" do
      long_description = "a" * 501
      template = Template.new(@valid_attributes.merge(description: long_description))
      assert_not template.valid?
      assert_includes template.errors[:description], "is too long (maximum is 500 characters)"
    end

    test "should validate status inclusion" do
      assert_raises(ArgumentError) do
        Template.new(@valid_attributes.merge(status: "invalid"))
      end
    end

    # Enum tests
    test "should handle status enum correctly" do
      template = Template.create!(@valid_attributes)

      assert template.active?
      assert_not template.inactive?

      template.inactive!
      assert template.inactive?
      assert_not template.active?
    end





    # Edge case tests
    test "should allow blank description" do
      template = Template.new(@valid_attributes.merge(description: nil))
      assert template.valid?

      template = Template.new(@valid_attributes.merge(description: ""))
      assert template.valid?
    end

    test "should preserve content formatting" do
      content_with_formatting = "Hello {{name}},\n\nWelcome to our system!\n\nBest regards,\nThe Team"
      template = Template.create!(@valid_attributes.merge(content: content_with_formatting))

      assert_equal content_with_formatting, template.content
    end

    test "should handle unicode characters in content" do
      unicode_content = "Hello 🌟 {{name}}, welcome to our système! 中文 العربية"
      template = Template.create!(@valid_attributes.merge(
        name: "Unicode Template",
        content: unicode_content
      ))

      assert_equal unicode_content, template.content
    end
  end
end
