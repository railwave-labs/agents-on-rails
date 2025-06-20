# frozen_string_literal: true

module ThreadAgent
  class NotionWorkspace < ApplicationRecord
    self.table_name = "thread_agent_notion_workspaces"

    has_many :notion_databases, class_name: "ThreadAgent::NotionDatabase", dependent: :destroy

    enum :status, {
      active: "active",
      inactive: "inactive",
      error: "error"
    }

    validates :name, presence: true, length: { minimum: 3, maximum: 100 }
    validates :notion_workspace_id, presence: true, length: { maximum: 255 }, uniqueness: true
    validates :access_token, presence: true
    validates :slack_team_id, presence: true, length: { maximum: 255 }, uniqueness: true
    validates :status, presence: true

    scope :active, -> { where(status: :active) }
    scope :by_workspace_id, ->(workspace_id) { where(notion_workspace_id: workspace_id) }
    scope :by_slack_team, ->(team_id) { where(slack_team_id: team_id) }
    def self.find_by_workspace_id(workspace_id)
      find_by(notion_workspace_id: workspace_id)
    end

    def self.find_by_slack_team(team_id)
      find_by(slack_team_id: team_id)
    end

    def self.active_for_slack_team(team_id)
      active.find_by(slack_team_id: team_id)
    end

    def self.create_workspace!(name:, notion_workspace_id:, access_token:, slack_team_id:)
      create!(
        name: name,
        notion_workspace_id: notion_workspace_id,
        access_token: access_token,
        slack_team_id: slack_team_id,
        status: :active
      )
    end
  end
end
