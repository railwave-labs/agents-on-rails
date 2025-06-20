# frozen_string_literal: true

module ThreadAgent
  class NotionDatabase < ApplicationRecord
    self.table_name = "thread_agent_notion_databases"

    # Associations
    belongs_to :notion_workspace, class_name: "ThreadAgent::NotionWorkspace"
    has_many :templates, class_name: "ThreadAgent::Template", dependent: :destroy

    # Enums for status tracking
    enum :status, {
      active: "active",
      inactive: "inactive"
    }

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :notion_database_id, presence: true, length: { maximum: 255 },
              uniqueness: { scope: :notion_workspace_id }
    validates :status, presence: true

    # Scopes for common queries
    scope :by_database_id, ->(database_id) { where(notion_database_id: database_id) }
    scope :by_workspace, ->(workspace) { where(notion_workspace: workspace) }

    # Class methods
    def self.find_by_database_id(database_id)
      find_by(notion_database_id: database_id)
    end

    def self.create_database!(workspace:, notion_database_id:, name:)
      create!(
        notion_workspace: workspace,
        notion_database_id: notion_database_id,
        name: name,
        status: :active
      )
    end
  end
end
