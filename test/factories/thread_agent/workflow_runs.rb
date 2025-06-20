# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_run, class: "ThreadAgent::WorkflowRun" do
    workflow_name { "test_workflow" }
    status { "pending" }

    trait :running do
      status { "running" }
      started_at { 1.hour.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 2.hours.ago }
      finished_at { 1.hour.ago }
      output_data { "Success result" }
    end

    trait :failed do
      status { "failed" }
      started_at { 2.hours.ago }
      finished_at { 1.hour.ago }
      error_message { "Test error" }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 2.hours.ago }
      finished_at { 1.hour.ago }
    end

    trait :with_slack_info do
      slack_channel_id { "C123456" }
      slack_message_id { "1234567890.123456" }
    end

    trait :invalid_workflow_name_too_short do
      workflow_name { "" }
    end

    trait :invalid_workflow_name_too_long do
      workflow_name { "a" * 256 }
    end

    trait :invalid_error_message_too_long do
      error_message { "a" * 2001 }
    end

    trait :invalid_slack_message_id_too_long do
      slack_message_id { "a" * 256 }
    end

    trait :invalid_slack_channel_id_too_long do
      slack_channel_id { "a" * 256 }
    end
  end
end
