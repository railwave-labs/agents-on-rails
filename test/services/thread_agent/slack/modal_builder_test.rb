require "test_helper"
require "ostruct"

class ThreadAgent::Slack::ModalBuilderTest < ActiveSupport::TestCase
  def setup
    @workspaces = [
      { id: 1, name: "Engineering Workspace" },
      { id: 2, name: "Marketing Workspace" }
    ]

    @templates = [
      { id: 1, name: "Bug Report Template" },
      { id: 2, name: "Feature Request Template" }
    ]
  end

  class ThreadCaptureModalTest < ThreadAgent::Slack::ModalBuilderTest
    test "builds complete modal with workspaces and templates" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, @templates)

      assert_equal "modal", modal[:type]
      assert_equal "thread_capture_modal", modal[:callback_id]
      assert_equal "Capture Thread", modal[:title][:text]
      assert_equal "Capture", modal[:submit][:text]
      assert_equal "Cancel", modal[:close][:text]
      assert modal[:blocks].is_a?(Array)
      assert modal[:blocks].length >= 4 # Section, divider, workspace, template
    end

    test "builds modal with only workspaces (no templates)" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, [])

      assert_equal "modal", modal[:type]
      assert_equal "thread_capture_modal", modal[:callback_id]
      assert modal[:blocks].is_a?(Array)
      assert_equal 3, modal[:blocks].length # Section, divider, workspace only

      # Check that workspace block is present
      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      assert_not_nil workspace_block

      # Check that template block is not present
      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      assert_nil template_block
    end

    test "builds modal with nil templates" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, nil)

      assert_equal "modal", modal[:type]
      assert_equal 3, modal[:blocks].length # Section, divider, workspace only
    end

    test "handles workspaces with string keys" do
      string_key_workspaces = [
        { "id" => 1, "name" => "Engineering Workspace" },
        { "id" => 2, "name" => "Marketing Workspace" }
      ]

      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(string_key_workspaces, [])

      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      assert_not_nil workspace_block

      options = workspace_block[:element][:options]
      assert_equal 2, options.length
      assert_equal "Engineering Workspace", options[0][:text][:text]
      assert_equal "1", options[0][:value]
    end

    test "handles templates with string keys" do
      string_key_templates = [
        { "id" => 1, "name" => "Bug Report Template" },
        { "id" => 2, "name" => "Feature Request Template" }
      ]

      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, string_key_templates)

      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      assert_not_nil template_block

      options = template_block[:element][:options]
      assert_equal 2, options.length
      assert_equal "Bug Report Template", options[0][:text][:text]
      assert_equal "1", options[0][:value]
    end

    test "modal structure has correct basic elements" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, @templates)

      # Check title structure
      assert_equal "plain_text", modal[:title][:type]
      assert_equal "Capture Thread", modal[:title][:text]

      # Check submit button structure
      assert_equal "plain_text", modal[:submit][:type]
      assert_equal "Capture", modal[:submit][:text]

      # Check close button structure
      assert_equal "plain_text", modal[:close][:type]
      assert_equal "Cancel", modal[:close][:text]
    end

    test "modal blocks include correct section and divider" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, @templates)

      blocks = modal[:blocks]

      # First block should be a section with instructions
      section_block = blocks[0]
      assert_equal "section", section_block[:type]
      assert_equal "mrkdwn", section_block[:text][:type]
      assert_includes section_block[:text][:text], "Select a workspace and template"

      # Second block should be a divider
      divider_block = blocks[1]
      assert_equal "divider", divider_block[:type]
    end
  end

  class WorkspaceSelectorTest < ThreadAgent::Slack::ModalBuilderTest
    test "workspace selector has correct structure" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, [])

      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      assert_not_nil workspace_block

      assert_equal "input", workspace_block[:type]
      assert_equal "workspace_block", workspace_block[:block_id]
      assert_equal "Workspace", workspace_block[:label][:text]

      element = workspace_block[:element]
      assert_equal "static_select", element[:type]
      assert_equal "workspace_select", element[:action_id]
      assert_equal "Select a workspace", element[:placeholder][:text]
    end

    test "workspace options are correctly formatted" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, [])

      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      options = workspace_block[:element][:options]

      assert_equal 2, options.length

      # First option
      assert_equal "plain_text", options[0][:text][:type]
      assert_equal "Engineering Workspace", options[0][:text][:text]
      assert_equal "1", options[0][:value]

      # Second option
      assert_equal "plain_text", options[1][:text][:type]
      assert_equal "Marketing Workspace", options[1][:text][:text]
      assert_equal "2", options[1][:value]
    end

    test "workspace values are converted to strings" do
      workspaces_with_int_ids = [
        { id: 123, name: "Test Workspace" }
      ]

      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(workspaces_with_int_ids, [])

      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      options = workspace_block[:element][:options]

      assert_equal "123", options[0][:value]
    end
  end

  class TemplateSelectorTest < ThreadAgent::Slack::ModalBuilderTest
    test "template selector has correct structure when templates provided" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, @templates)

      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      assert_not_nil template_block

      assert_equal "input", template_block[:type]
      assert_equal "template_block", template_block[:block_id]
      assert_equal "Template", template_block[:label][:text]

      element = template_block[:element]
      assert_equal "static_select", element[:type]
      assert_equal "template_select", element[:action_id]
      assert_equal "Select a template", element[:placeholder][:text]
    end

    test "template options are correctly formatted" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, @templates)

      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      options = template_block[:element][:options]

      assert_equal 2, options.length

      # First option
      assert_equal "plain_text", options[0][:text][:type]
      assert_equal "Bug Report Template", options[0][:text][:text]
      assert_equal "1", options[0][:value]

      # Second option
      assert_equal "plain_text", options[1][:text][:type]
      assert_equal "Feature Request Template", options[1][:text][:text]
      assert_equal "2", options[1][:value]
    end

    test "template values are converted to strings" do
      templates_with_int_ids = [
        { id: 456, name: "Test Template" }
      ]

      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, templates_with_int_ids)

      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      options = template_block[:element][:options]

      assert_equal "456", options[0][:value]
    end

    test "no template selector when templates are empty" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, [])

      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      assert_nil template_block
    end

    test "no template selector when templates are nil" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, nil)

      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      assert_nil template_block
    end
  end

  class EdgeCasesTest < ThreadAgent::Slack::ModalBuilderTest
    test "handles empty workspaces array" do
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal([], @templates)

      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      assert_not_nil workspace_block

      options = workspace_block[:element][:options]
      assert_equal 0, options.length
    end

    test "handles single workspace" do
      single_workspace = [ { id: 1, name: "Only Workspace" } ]
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(single_workspace, [])

      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      options = workspace_block[:element][:options]

      assert_equal 1, options.length
      assert_equal "Only Workspace", options[0][:text][:text]
    end

    test "handles single template" do
      single_template = [ { id: 1, name: "Only Template" } ]
      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(@workspaces, single_template)

      template_block = modal[:blocks].find { |block| block[:block_id] == "template_block" }
      options = template_block[:element][:options]

      assert_equal 1, options.length
      assert_equal "Only Template", options[0][:text][:text]
    end

    test "handles mixed symbol and string keys" do
      mixed_workspaces = [
        { :id => 1, "name" => "Mixed Keys Workspace" }
      ]

      modal = ThreadAgent::Slack::ModalBuilder.build_thread_capture_modal(mixed_workspaces, [])

      workspace_block = modal[:blocks].find { |block| block[:block_id] == "workspace_block" }
      options = workspace_block[:element][:options]

      assert_equal 1, options.length
      assert_equal "Mixed Keys Workspace", options[0][:text][:text]
      assert_equal "1", options[0][:value]
    end
  end
end
