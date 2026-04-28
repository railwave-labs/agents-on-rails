# frozen_string_literal: true

class Template < ApplicationRecord
  self.table_name = "templates"

  belongs_to :notion_database, optional: true

  enum :status, {
    active: "active",
    inactive: "inactive"
  }

  validates :name, presence: true, length: { minimum: 3, maximum: 100 }, uniqueness: true
  validates :content, presence: true
  validates :status, presence: true
  validates :description, length: { maximum: 500 }, allow_blank: true
end
