# frozen_string_literal: true

require "test_helper"

class ThreadAgent::ProcessWorkflowJobTest < ActiveJob::TestCase
  def setup
    @valid_payload = {
      "type" => "view_submission",
      "user" => {
        "id" => "U123456",
        "name" => "testuser"
      },
      "view" => {
        "id" => "V123456",
        "state" => {
          "values" => {
            "workspace_select" => {
              "selected_workspace" => {
                "selected_option" => {
                  "value" => "workspace_123"
                }
              }
            },
            "template_select" => {
              "selected_template" => {
                "selected_option" => {
                  "value" => "template_456"
                }
              }
            }
          }
        }
      }
    }
  end

  test "job is enqueued to the default queue" do
    assert_enqueued_with(job: ThreadAgent::ProcessWorkflowJob, queue: "default") do
      ThreadAgent::ProcessWorkflowJob.perform_later(@valid_payload)
    end
  end

  test "perform processes payload successfully and logs workflow details" do
    job = ThreadAgent::ProcessWorkflowJob.new

    Rails.logger.expects(:info).with(regexp_matches(/ProcessWorkflowJob running. Payload:/)).once
    Rails.logger.expects(:info).with("Processing workflow for user: U123456").once
    Rails.logger.expects(:info).with(regexp_matches(/Modal state values:/)).once
    Rails.logger.expects(:info).with("ProcessWorkflowJob completed successfully").once

    job.perform(@valid_payload)
  end

  test "perform extracts user and view data correctly" do
    job = ThreadAgent::ProcessWorkflowJob.new

    # Capture the logged data by stubbing the logger
    logged_messages = []
    Rails.logger.stubs(:info) do |message|
      logged_messages << message
    end

    job.perform(@valid_payload)

    # Verify user extraction
    assert_includes logged_messages.join(" "), "U123456"

    # Verify state values extraction
    state_log = logged_messages.find { |msg| msg.include?("Modal state values:") }
    assert_not_nil state_log
    assert_includes state_log, "workspace_select"
    assert_includes state_log, "template_select"
  end

  test "perform handles payload with minimal data" do
    minimal_payload = {
      "type" => "view_submission",
      "user" => {
        "id" => "U999999"
      },
      "view" => {
        "state" => {
          "values" => {}
        }
      }
    }

    job = ThreadAgent::ProcessWorkflowJob.new

    Rails.logger.expects(:info).at_least_once

    # Should complete without error even with minimal data
    assert_nothing_raised do
      job.perform(minimal_payload)
    end
  end

  test "perform handles exceptions and logs errors properly" do
    job = ThreadAgent::ProcessWorkflowJob.new

    # Create a payload that will cause an error when accessing dig
    faulty_payload = @valid_payload.dup
    faulty_payload.define_singleton_method(:dig) do |*args|
      raise StandardError, "Simulated error" if args == [ "user", "id" ]
      super(*args)
    end

    Rails.logger.expects(:error).with("ProcessWorkflowJob failed: Simulated error").once
    Rails.logger.expects(:error).with(regexp_matches(/Backtrace:/)).once

    assert_raises(StandardError, "Simulated error") do
      job.perform(faulty_payload)
    end
  end

  test "perform handles payload without user id" do
    payload_without_user = {
      "type" => "view_submission",
      "view" => {
        "state" => {
          "values" => {
            "test" => "value"
          }
        }
      }
    }

    job = ThreadAgent::ProcessWorkflowJob.new

    Rails.logger.expects(:info).at_least_once

    # Should handle nil user_id gracefully
    assert_nothing_raised do
      job.perform(payload_without_user)
    end
  end

  test "perform handles payload without view data" do
    payload_without_view = {
      "type" => "view_submission",
      "user" => {
        "id" => "U123456"
      }
    }

    job = ThreadAgent::ProcessWorkflowJob.new

    Rails.logger.expects(:info).at_least_once

    # Should handle missing view data gracefully
    assert_nothing_raised do
      job.perform(payload_without_view)
    end
  end
end
