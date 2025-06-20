# frozen_string_literal: true

FactoryBot.define do
  factory :notion_workspace, class: "ThreadAgent::NotionWorkspace" do
    name { "Test Workspace" }
    sequence(:notion_workspace_id) { |n| "workspace_#{n}" }
    access_token { "secret_token_abc" }
    sequence(:slack_team_id) { |n| "T#{n.to_s.rjust(8, '0')}" }
    status { "active" }

    trait :inactive do
      status { "inactive" }
    end

    trait :with_long_name do
      name { "a" * 100 }
    end

    trait :invalid_name_too_short do
      name { "ab" }
    end

    trait :invalid_name_too_long do
      name { "a" * 101 }
    end
  end
end
