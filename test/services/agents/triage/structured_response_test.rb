# frozen_string_literal: true

require "test_helper"

class Agents::Triage::StructuredResponseTest < ActiveSupport::TestCase
  VALID_JSON = <<~JSON.strip
    {
      "severity": "high",
      "hypothesis": "Nil pointer in checkout flow due to missing guard on CartService#total",
      "suggested_next_step": "Add nil check in CartService#total and deploy hotfix",
      "context_links": ["https://sentry.io/issues/999", "https://github.com/org/repo/pull/123"],
      "confidence": 0.85
    }
  JSON

  test "parses well-formed JSON into a Payload" do
    payload = Agents::Triage::StructuredResponse.parse(VALID_JSON)
    assert_equal "high", payload.severity
    assert_includes payload.hypothesis, "Nil pointer"
    assert_equal 0.85, payload.confidence
    assert_equal 2, payload.context_links.length
  end

  test "parses JSON wrapped in a fenced code block" do
    fenced = "```json\n#{VALID_JSON}\n```"
    payload = Agents::Triage::StructuredResponse.parse(fenced)
    assert_equal "high", payload.severity
  end

  test "parses JSON embedded in surrounding prose" do
    prose = "Here is my assessment:\n#{VALID_JSON}\nLet me know if you need more info."
    payload = Agents::Triage::StructuredResponse.parse(prose)
    assert_equal "high", payload.severity
  end

  test "accepts all valid severity levels" do
    %w[info low medium high critical].each do |sev|
      json = VALID_JSON.sub('"high"', "\"#{sev}\"")
      payload = Agents::Triage::StructuredResponse.parse(json)
      assert_equal sev, payload.severity
    end
  end

  test "context_links defaults to empty array when absent" do
    json = VALID_JSON.sub(/"context_links": \[.*?\],/m, '')
    payload = Agents::Triage::StructuredResponse.parse(json)
    assert_equal [], payload.context_links
  end

  test "raises ValidationError for invalid severity" do
    json = VALID_JSON.sub('"high"', '"unknown_severity"')
    error = assert_raises(ValidationError) { Agents::Triage::StructuredResponse.parse(json) }
    assert_includes error.message, "invalid severity"
  end

  test "raises ValidationError for missing hypothesis" do
    json = VALID_JSON.sub(/"hypothesis": ".*?"/, '"hypothesis": ""')
    assert_raises(ValidationError) { Agents::Triage::StructuredResponse.parse(json) }
  end

  test "raises ValidationError for missing suggested_next_step" do
    json = VALID_JSON.sub(/"suggested_next_step": ".*?"/, '"suggested_next_step": ""')
    assert_raises(ValidationError) { Agents::Triage::StructuredResponse.parse(json) }
  end

  test "raises ValidationError for out-of-range confidence" do
    json = VALID_JSON.sub("0.85", "1.5")
    assert_raises(ValidationError) { Agents::Triage::StructuredResponse.parse(json) }
  end

  test "raises ServiceParseError for malformed JSON" do
    assert_raises(ServiceParseError) { Agents::Triage::StructuredResponse.parse("not json {{{") }
  end

  test "Payload responds to to_h with symbolized keys" do
    payload = Agents::Triage::StructuredResponse.parse(VALID_JSON)
    h = payload.to_h
    assert h.key?(:severity)
    assert h.key?(:hypothesis)
    assert h.key?(:confidence)
  end
end
