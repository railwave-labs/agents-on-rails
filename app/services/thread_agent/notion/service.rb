# frozen_string_literal: true

module ThreadAgent
  module Notion
    class Service
      attr_reader :notion_client, :retry_handler, :database_service, :page_service

      def initialize(token: nil, timeout: nil, max_retries: 3)
        @notion_client = Client.new(token: token, timeout: timeout)
        @retry_handler = RetryHandler.new(max_attempts: max_retries)
        @database_service = DatabaseService.new(@notion_client, @retry_handler)
        @page_service = PageService.new(@notion_client, @retry_handler)
      end

      # Delegate configuration attributes to notion_client
      def token
        notion_client.token
      end

      def timeout
        notion_client.timeout
      end

      def max_retries
        retry_handler.max_attempts
      end

      # Delegate client access to notion_client
      def client
        notion_client
      end

      # Delegate retry logic to retry_handler
      def retry_with(&block)
        retry_handler.retry_with(&block)
      end

      # Delegate database operations to database_service
      def list_databases(workspace_id: nil)
        database_service.list_databases(workspace_id: workspace_id)
      end

      def get_database(database_id)
        database_service.get_database(database_id)
      end

  # Delegate page operations to page_service
  def create_page(database_id:, properties: {}, content: [])
    page_service.create_page(database_id: database_id, properties: properties, content: content)
  end

  # Create a page using thread data and AI content with intelligent building
  def create_page_from_workflow(thread_data:, workflow_run:, openai_data:)
    unless workflow_run.template&.notion_database
      error = ThreadAgent::ConfigurationError.new(
        "No Notion database configured for template",
        context: {
          component: "workflow_page_creation",
          workflow_run_id: workflow_run.id,
          template_present: !workflow_run.template.nil?,
          template_id: workflow_run.template&.id
        }
      )
      return ThreadAgent::ErrorHandler.to_result(error, service: "notion")
    end

    database_id = workflow_run.template.notion_database.notion_database_id

    begin
      # Build page data using the page builder
      page_builder = PageBuilder.new(thread_data, workflow_run, openai_data)
      properties = page_builder.build_properties
      content = page_builder.build_content

      # Create page using the service
      create_page(database_id: database_id, properties: properties, content: content)
    rescue ThreadAgent::Error => e
      # Already a standardized error, just convert to result
      ThreadAgent::ErrorHandler.to_result(e, service: "notion")
    rescue StandardError => e
      ThreadAgent::ErrorHandler.to_result(
        e,
        context: {
          component: "workflow_page_creation",
          workflow_run_id: workflow_run.id,
          database_id: database_id,
          template_id: workflow_run.template&.id
        },
        service: "notion"
      )
    end
  end

      private

      # Delegate data transformation methods to DataTransformer
      def extract_title_from_notion_response(title_array)
        DataTransformer.extract_title_from_notion_response(title_array)
      end

      def extract_properties_from_response(properties_hash)
        DataTransformer.extract_properties_from_response(properties_hash)
      end

      def transform_database_from_api(api_response, workspace_id = nil)
        DataTransformer.transform_database_from_api(api_response, workspace_id)
      end
    end
  end
end
