# frozen_string_literal: true

FactoryBot.define do
  factory :notion_database, class: "ThreadAgent::NotionDatabase" do
    association :notion_workspace, factory: :notion_workspace
    name { "Test Database" }
    sequence(:notion_database_id) { |n| "db_#{n}" }
    status { "active" }

    trait :inactive do
      status { "inactive" }
    end
  end
end
