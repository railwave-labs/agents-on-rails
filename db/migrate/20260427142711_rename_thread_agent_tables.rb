# frozen_string_literal: true

class RenameThreadAgentTables < ActiveRecord::Migration[8.0]
  def change
    rename_table :thread_agent_workflow_runs,     :agent_runs
    rename_table :thread_agent_templates,         :templates
    rename_table :thread_agent_notion_workspaces, :notion_workspaces
    rename_table :thread_agent_notion_databases,  :notion_databases

    # Rename explicitly-named indexes on agent_runs
    rename_index :agent_runs, "index_thread_agent_workflow_runs_on_started_at",                 "index_agent_runs_on_started_at"
    rename_index :agent_runs, "index_thread_agent_workflow_runs_on_status",                     "index_agent_runs_on_status"
    rename_index :agent_runs, "index_thread_agent_workflow_runs_on_template_id",                "index_agent_runs_on_template_id"
    rename_index :agent_runs, "index_thread_agent_workflow_runs_on_workflow_name_and_status",   "index_agent_runs_on_workflow_name_and_status"

    # Rename explicitly-named indexes on templates
    rename_index :templates, "index_thread_agent_templates_on_name",              "index_templates_on_name"
    rename_index :templates, "index_thread_agent_templates_on_notion_database_id", "index_templates_on_notion_database_id"
    rename_index :templates, "index_thread_agent_templates_on_status",            "index_templates_on_status"

    # Rename explicitly-named indexes on notion_workspaces
    rename_index :notion_workspaces, "index_thread_agent_notion_workspaces_on_notion_workspace_id", "index_notion_workspaces_on_notion_workspace_id"
    rename_index :notion_workspaces, "index_thread_agent_notion_workspaces_on_slack_team_id",       "index_notion_workspaces_on_slack_team_id"
    rename_index :notion_workspaces, "index_thread_agent_notion_workspaces_on_status",              "index_notion_workspaces_on_status"

    # Rename explicitly-named indexes on notion_databases
    rename_index :notion_databases, "index_thread_agent_notion_databases_on_notion_workspace_id", "index_notion_databases_on_notion_workspace_id"
    rename_index :notion_databases, "index_thread_agent_notion_databases_on_status",              "index_notion_databases_on_status"

    # Auto-named hash-suffixed indexes (idx_on_*) keep their names — harmless.
  end
end
