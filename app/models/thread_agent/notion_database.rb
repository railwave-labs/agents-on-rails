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
    validates :notion_database_id, presence: true, length: { maximum: 255 }, uniqueness: { scope: :notion_workspace_id }
    validates :status, presence: true

    scope :by_database_id, ->(database_id) { where(notion_database_id: database_id) }
    scope :by_workspace, ->(workspace) { where(notion_workspace: workspace) }

    def self.create_database!(workspace:, name:, notion_database_id:)
      create!(
        notion_workspace: workspace,
        name: name,
        notion_database_id: notion_database_id,
        status: :active
      )
    end
  end
end
