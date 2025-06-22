# frozen_string_literal: true

module ThreadAgent
  class OpenaiService
    DEFAULT_TIMEOUT = 20

    attr_reader :config, :client

    def initialize(configuration: ThreadAgent.configuration, client: nil)
      @config = configuration
      validate_configuration!
      @client = client || initialize_client
    end

    # Public API – will be expanded in future tasks
    def transform_content(*)
      raise NotImplementedError, "Content transformation not yet implemented"
    end

    private

    def validate_configuration!
      unless config.openai_api_key.present?
        raise ThreadAgent::OpenaiError, "Missing OpenAI API key"
      end
    end

    def initialize_client
      OpenAI::Client.new(
        access_token: config.openai_api_key,
        request_timeout: DEFAULT_TIMEOUT
      )
    rescue StandardError => e
      raise ThreadAgent::OpenaiError, "Failed to initialize OpenAI client: #{e.message}"
    end
  end
end
