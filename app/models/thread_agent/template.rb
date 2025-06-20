# frozen_string_literal: true

module ThreadAgent
  class Template < ApplicationRecord
    self.table_name = "thread_agent_templates"

    # Simple enum for template status
    enum :status, {
      active: "active",
      inactive: "inactive"
    }

    # Validations
    validates :name, presence: true, length: { in: 3..100 }
    validates :name, uniqueness: true
    validates :content, presence: true
    validates :status, presence: true
    validates :description, length: { maximum: 500 }, allow_blank: true
  end
end
