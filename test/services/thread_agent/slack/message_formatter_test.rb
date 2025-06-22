# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ThreadAgent::Slack::MessageFormatterTest < ActiveSupport::TestCase
  def setup
    @parent_message = OpenStruct.new(
      channel: "C12345678",
      user: "U12345",
      text: "Parent message",
      ts: "1605139215.000700",
      attachments: [ { "text" => "attachment" } ],
      files: [ { "name" => "file.txt" } ]
    )

    @reply1 = OpenStruct.new(
      user: "U67890",
      text: "Reply message 1",
      ts: "1605139216.000800",
      attachments: [],
      files: []
    )

    @reply2 = OpenStruct.new(
      user: "U11111",
      text: "Reply message 2",
      ts: "1605139217.000900",
      attachments: nil,
      files: nil
    )

    @replies = [ @parent_message, @reply1, @reply2 ]
  end

  test "format_message formats a message object correctly" do
    result = ThreadAgent::Slack::MessageFormatter.format_message(@parent_message)

    expected = {
      user: "U12345",
      text: "Parent message",
      ts: "1605139215.000700",
      attachments: [ { "text" => "attachment" } ],
      files: [ { "name" => "file.txt" } ]
    }

    assert_equal expected, result
  end

  test "format_message handles nil attachments and files" do
    result = ThreadAgent::Slack::MessageFormatter.format_message(@reply2)

    expected = {
      user: "U11111",
      text: "Reply message 2",
      ts: "1605139217.000900",
      attachments: [],
      files: []
    }

    assert_equal expected, result
  end

  test "format_message handles missing attachments and files methods" do
    message_without_methods = OpenStruct.new(
      user: "U99999",
      text: "Basic message",
      ts: "1605139218.001000"
    )

    result = ThreadAgent::Slack::MessageFormatter.format_message(message_without_methods)

    expected = {
      user: "U99999",
      text: "Basic message",
      ts: "1605139218.001000",
      attachments: [],
      files: []
    }

    assert_equal expected, result
  end

  test "format_thread_data formats thread data correctly" do
    result = ThreadAgent::Slack::MessageFormatter.format_thread_data(@parent_message, @replies)

    assert_equal "C12345678", result[:channel_id]
    assert_equal "1605139215.000700", result[:thread_ts]

    # Check parent message
    expected_parent = {
      user: "U12345",
      text: "Parent message",
      ts: "1605139215.000700",
      attachments: [ { "text" => "attachment" } ],
      files: [ { "name" => "file.txt" } ]
    }
    assert_equal expected_parent, result[:parent_message]

    # Check replies (should exclude the first message which is the parent)
    assert_equal 2, result[:replies].length

    expected_reply1 = {
      user: "U67890",
      text: "Reply message 1",
      ts: "1605139216.000800",
      attachments: [],
      files: []
    }
    assert_equal expected_reply1, result[:replies][0]

    expected_reply2 = {
      user: "U11111",
      text: "Reply message 2",
      ts: "1605139217.000900",
      attachments: [],
      files: []
    }
    assert_equal expected_reply2, result[:replies][1]
  end

  test "format_thread_data excludes parent from replies array" do
    # Test with only parent message in replies
    parent_only = [ @parent_message ]
    result = ThreadAgent::Slack::MessageFormatter.format_thread_data(@parent_message, parent_only)

    assert_equal [], result[:replies]
  end

  test "format_thread_data handles empty replies array" do
    result = ThreadAgent::Slack::MessageFormatter.format_thread_data(@parent_message, [])

    assert_equal "C12345678", result[:channel_id]
    assert_equal "1605139215.000700", result[:thread_ts]
    assert_instance_of Hash, result[:parent_message]
    assert_equal [], result[:replies]
  end
end
