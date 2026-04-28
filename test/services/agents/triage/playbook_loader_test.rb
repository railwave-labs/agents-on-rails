# frozen_string_literal: true

require "test_helper"

class Agents::Triage::PlaybookLoaderTest < ActiveSupport::TestCase
  def setup
    Agents::Triage::PlaybookLoader.reload!
  end

  test "loads playbook content from file" do
    content = Agents::Triage::PlaybookLoader.load
    assert content.is_a?(String)
    assert content.length > 0
  end

  test "playbook content includes severity definitions" do
    content = Agents::Triage::PlaybookLoader.load
    assert_includes content, "critical"
    assert_includes content, "high"
    assert_includes content, "medium"
    assert_includes content, "low"
    assert_includes content, "info"
  end

  test "playbook content includes output format instruction" do
    content = Agents::Triage::PlaybookLoader.load
    assert_includes content, "severity"
    assert_includes content, "hypothesis"
    assert_includes content, "confidence"
  end

  test "memoizes content on subsequent calls" do
    first  = Agents::Triage::PlaybookLoader.load
    second = Agents::Triage::PlaybookLoader.load
    assert_same first, second
  end

  test "reload! clears memoized content" do
    first = Agents::Triage::PlaybookLoader.load
    Agents::Triage::PlaybookLoader.reload!
    second = Agents::Triage::PlaybookLoader.load
    assert_equal first, second
  end

  test "raises ConfigurationError when playbook file is missing" do
    File.stubs(:exist?).returns(false)
    Agents::Triage::PlaybookLoader.reload!
    assert_raises(ConfigurationError) { Agents::Triage::PlaybookLoader.load }
  ensure
    File.unstub(:exist?)
    Agents::Triage::PlaybookLoader.reload!
  end
end
