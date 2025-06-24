# Notion Service

Rails service for creating Notion pages from Slack thread data.

## Usage

```ruby
# Initialize service
service = ThreadAgent::Notion::Service.new(
  token: ENV['THREAD_AGENT_NOTION_TOKEN']
)

# List databases
result = service.list_databases
if result.success?
  databases = result.data # Array of database info
end

# Get specific database
result = service.get_database('database-id-123')
if result.success?
  database = result.data # Database details
end

# Create page
result = service.create_page(
  database_id: 'database-id-123',
  properties: { 'Title' => 'Page Title' },
  content: ['Some content', 'More content']
)
if result.success?
  page_url = result.data[:url]
end
```

## Return Values

All methods return `ThreadAgent::Result` objects:
- `result.success?` - Boolean success status
- `result.data` - Response data on success
- `result.error` - Error message on failure

## Error Codes

- `"Missing token"` - No Notion token provided
- `"Missing database_id"` - Required database ID not provided
- `"operation failed after X retries"` - Retry limit exceeded
- `"Unauthorized"` - Invalid token or permissions
- `"Not found"` - Database/resource doesn't exist

## Environment Variables

Required:
- `THREAD_AGENT_NOTION_TOKEN` - Notion API token

Optional:
- `THREAD_AGENT_DEFAULT_TIMEOUT` - Request timeout (default: 30s)
- `THREAD_AGENT_MAX_RETRIES` - Retry attempts (default: 3) 