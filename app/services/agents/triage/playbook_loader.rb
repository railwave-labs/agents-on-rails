# frozen_string_literal: true

module Agents
  module Triage
    class PlaybookLoader
      PLAYBOOK_PATH = Rails.root.join("playbooks", "triage.md").freeze

      def self.load
        @content ||= read_playbook
      end

      def self.reload!
        @content = nil
      end

      def self.read_playbook
        unless File.exist?(PLAYBOOK_PATH)
          raise ConfigurationError.new(
            "Triage playbook not found at #{PLAYBOOK_PATH}. " \
            "Create playbooks/triage.md to define the triage rubric and output schema."
          )
        end

        File.read(PLAYBOOK_PATH)
      end
      private_class_method :read_playbook
    end
  end
end
