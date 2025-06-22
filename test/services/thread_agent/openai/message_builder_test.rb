# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Openai::MessageBuilderTest < ActiveSupport::TestCase
  # slack_permalink tests
  test "generates correct Slack permalink" do
    permalink = ThreadAgent::Openai::MessageBuilder.slack_permalink("C123456", "1234567890.123")
    expected = "https://slack.com/app_redirect?channel=C123456&message_ts=1234567890.123"

    assert_equal expected, permalink
  end

  # build_messages tests
  test "build_messages with template uses template content as system prompt" do
    template = mock_template_with_content("Custom template instructions")
    thread_data = mock_valid_thread_data

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(
      template: template,
      thread_data: thread_data
    )

    assert_equal 2, messages.length
    assert_equal "system", messages[0][:role]
    assert_equal "Custom template instructions", messages[0][:content]
    assert_equal "user", messages[1][:role]
    assert_instance_of String, messages[1][:content]
  end

  test "build_messages with custom_prompt uses custom prompt as system prompt" do
    template = mock_template_with_content("Template instructions")
    thread_data = mock_valid_thread_data

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(
      template: template,
      thread_data: thread_data,
      custom_prompt: "Custom user instructions"
    )

    assert_equal 2, messages.length
    assert_equal "system", messages[0][:role]
    assert_equal "Custom user instructions", messages[0][:content]
    assert_equal "user", messages[1][:role]
  end

  test "build_messages without template or custom_prompt uses default system prompt" do
    thread_data = mock_valid_thread_data

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(thread_data: thread_data)

    assert_equal 2, messages.length
    assert_equal "system", messages[0][:role]
    assert_equal ThreadAgent::Openai::MessageBuilder::DEFAULT_SYSTEM_PROMPT, messages[0][:content]
    assert_equal "user", messages[1][:role]
  end

  test "build_messages includes slack permalink in user content" do
    thread_data = mock_valid_thread_data

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(thread_data: thread_data)

    user_content = messages[1][:content]
    expected_permalink = "https://slack.com/app_redirect?channel=C123456&message_ts=1234567890.123"

    assert_includes user_content, "**Thread Link:** #{expected_permalink}"
  end

  test "build_messages handles thread with replies" do
    thread_data = mock_thread_data_with_replies

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(thread_data: thread_data)

    user_content = messages[1][:content]

    assert_includes user_content, "**Thread Replies:**"
    assert_includes user_content, "1. User: user456"
    assert_includes user_content, "   Message: First reply"
    assert_includes user_content, "2. User: user789"
    assert_includes user_content, "   Message: Second reply"
  end

  test "build_messages includes metadata in user content" do
    thread_data = mock_valid_thread_data

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(thread_data: thread_data)

    user_content = messages[1][:content]

    assert_includes user_content, "**Thread Metadata:**"
    assert_includes user_content, "Channel ID: C123456"
    assert_includes user_content, "Thread Timestamp: 1234567890.123"
  end

  test "build_messages includes parent message details" do
    thread_data = mock_valid_thread_data

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(thread_data: thread_data)

    user_content = messages[1][:content]

    assert_includes user_content, "**Original Message:**"
    assert_includes user_content, "User: user123"
    assert_includes user_content, "Message: Original message"
    assert_includes user_content, "Timestamp: 1234567890.123"
  end

  test "build_messages handles thread data without replies" do
    thread_data = mock_valid_thread_data

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(thread_data: thread_data)

    user_content = messages[1][:content]

    assert_not_includes user_content, "**Thread Replies:**"
  end

  test "build_messages handles thread data without channel_id or thread_ts" do
    thread_data = {
      parent_message: {
        user: "user123",
        text: "Original message",
        ts: "1234567890.123"
      }
    }

    messages = ThreadAgent::Openai::MessageBuilder.build_messages(thread_data: thread_data)

    user_content = messages[1][:content]

    assert_not_includes user_content, "**Thread Link:**"
    assert_includes user_content, "**Original Message:**"
  end

  private

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
end
