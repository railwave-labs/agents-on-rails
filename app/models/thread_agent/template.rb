# frozen_string_literal: true

module ThreadAgent
  class Template < ApplicationRecord
    self.table_name = "thread_agent_templates"

    belongs_to :notion_database

    enum :status, {
      active: "active",
      inactive: "inactive"
    }

    validates :name, presence: true, length: { minimum: 3, maximum: 100 }, uniqueness: true
    validates :content, presence: true
    validates :status, presence: true
    validates :description, length: { maximum: 500 }, allow_blank: true
  end
end
