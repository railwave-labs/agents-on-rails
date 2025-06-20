# frozen_string_literal: true

module ThreadAgent
  class Template < ApplicationRecord
    self.table_name = "thread_agent_templates"

    belongs_to :notion_database, optional: true

    enum :status, {
      active: "active",
      inactive: "inactive"
    }

    validates :name, presence: true, length: { minimum: 3, maximum: 100 }, uniqueness: true
    validates :content, presence: true
    validates :status, presence: true
    validates :description, length: { maximum: 500 }, allow_blank: true

    scope :active, -> { where(status: :active) }
    scope :inactive, -> { where(status: :inactive) }
  end
end
