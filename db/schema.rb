# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_06_20_132202) do
  create_table "thread_agent_notion_workspaces", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "notion_workspace_id", limit: 255, null: false
    t.text "access_token", null: false
    t.string "slack_team_id", limit: 255, null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notion_workspace_id"], name: "index_thread_agent_notion_workspaces_on_notion_workspace_id", unique: true
    t.index ["slack_team_id"], name: "index_thread_agent_notion_workspaces_on_slack_team_id", unique: true
    t.index ["status"], name: "index_thread_agent_notion_workspaces_on_status"
  end

  create_table "thread_agent_templates", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.text "description", limit: 500
    t.text "content", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_thread_agent_templates_on_name", unique: true
    t.index ["status"], name: "index_thread_agent_templates_on_status"
  end

  create_table "thread_agent_workflow_runs", force: :cascade do |t|
    t.string "workflow_name", null: false
    t.string "status", default: "pending", null: false
    t.text "input_data"
    t.text "output_data"
    t.text "error_message"
    t.json "steps", default: []
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slack_message_id"
    t.string "slack_channel_id"
    t.index ["slack_channel_id", "slack_message_id"], name: "idx_on_slack_channel_id_slack_message_id_e2571b1df9"
    t.index ["started_at"], name: "index_thread_agent_workflow_runs_on_started_at"
    t.index ["status"], name: "index_thread_agent_workflow_runs_on_status"
    t.index ["workflow_name", "status"], name: "index_thread_agent_workflow_runs_on_workflow_name_and_status"
  end
end
