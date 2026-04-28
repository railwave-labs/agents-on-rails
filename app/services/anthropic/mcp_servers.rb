# frozen_string_literal: true

module Anthropic
  class McpServers
    CONFIG_PATH = Rails.root.join("config", "mcp_servers.yml").freeze

    def self.load(environment = :default)
      raw = ERB.new(File.read(CONFIG_PATH)).result
      config = YAML.safe_load(raw, permitted_classes: [], aliases: true) || {}
      servers = config[environment.to_s] || []
      servers
        .map { |s| s.transform_keys(&:to_sym) }
        .reject { |s| s[:url].blank? }
    end
  end
end
