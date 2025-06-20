# frozen_string_literal: true

module ThreadAgent
  class NotionDatabase < ApplicationRecord
    self.table_name = "thread_agent_notion_databases"

    belongs_to :notion_workspace, class_name: "ThreadAgent::NotionWorkspace"
    has_many :templates, class_name: "ThreadAgent::Template", dependent: :destroy

    enum :status, {
      active: "active",
      inactive: "inactive"
    }

    validates :name, presence: true, length: { minimum: 1, maximum: 255 }
    validates :notion_database_id, presence: true, length: { maximum: 255 }, uniqueness: true
    validates :status, presence: true

    scope :active, -> { where(status: :active) }
    scope :by_database_id, ->(database_id) { where(notion_database_id: database_id) }

    def self.find_by_database_id(database_id)
      find_by(notion_database_id: database_id)
    end

    def self.create_database!(notion_workspace:, name:, notion_database_id:)
      create!(
        notion_workspace: notion_workspace,
        name: name,
        notion_database_id: notion_database_id,
        status: :active
      )
    end
  end
end
