# Environment Variables

This project uses [dotenv-rails](https://github.com/bkeepers/dotenv) to manage environment variables in development and test environments.

## Setup

1. Copy the example file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your actual values:
   ```bash
   # Replace with your actual API keys and configuration
   THREAD_AGENT_SLACK_CLIENT_ID=your_actual_slack_client_id
   THREAD_AGENT_OPENAI_API_KEY=your_actual_openai_api_key
   # ... etc
   ```

## Files

- `.env.example` - Template file (committed to git) showing required variables
- `.env` - Your actual environment variables (git-ignored, never commit this)
- `.env.development` - Development-specific variables (optional)
- `.env.test` - Test-specific variables (optional)
- `.env.local` - Local overrides (git-ignored)

## ThreadAgent Configuration

The ThreadAgent module automatically reads these environment variables:

- `THREAD_AGENT_SLACK_CLIENT_ID`
- `THREAD_AGENT_SLACK_CLIENT_SECRET` 
- `THREAD_AGENT_SLACK_SIGNING_SECRET`
- `THREAD_AGENT_OPENAI_API_KEY`
- `THREAD_AGENT_OPENAI_MODEL` (defaults to 'gpt-4o-mini')
- `THREAD_AGENT_NOTION_CLIENT_ID`
- `THREAD_AGENT_NOTION_CLIENT_SECRET`
- `THREAD_AGENT_DEFAULT_TIMEOUT` (defaults to 30)
- `THREAD_AGENT_MAX_RETRIES` (defaults to 3)

## Usage

Environment variables are automatically loaded when Rails starts. No additional configuration needed.

```ruby
# These are automatically available
ENV['THREAD_AGENT_OPENAI_API_KEY']

# Or through ThreadAgent configuration
ThreadAgent.configuration.openai_api_key
```
