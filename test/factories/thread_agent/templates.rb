# frozen_string_literal: true

FactoryBot.define do
  factory :template, class: "ThreadAgent::Template" do
    association :notion_database, factory: :notion_database
    sequence(:name) { |n| "Test Template #{n}" }
    content { "Hello {{name}}, welcome to our system!" }
    status { "active" }
    description { "A test template for unit testing" }

    trait :inactive do
      status { "inactive" }
    end

    trait :minimal do
      name { "Minimal Template" }
      content { "Basic content" }
      description { nil }
    end

    trait :with_unicode_content do
      name { "Unicode Template" }
      content { "Hello 🌟 {{name}}, welcome to our système! 中文 العربية" }
    end

    trait :with_formatting do
      content { "Hello {{name}},\n\nWelcome to our system!\n\nBest regards,\nThe Team" }
    end

    trait :invalid_name_too_short do
      name { "ab" }
    end

    trait :invalid_name_too_long do
      name { "a" * 101 }
    end

    trait :invalid_description_too_long do
      description { "a" * 501 }
    end
  end
end
