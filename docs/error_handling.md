# Error Handling in ThreadAgent

This document describes the comprehensive error handling system implemented in ThreadAgent.

## Overview

ThreadAgent uses a standardized error handling approach with:
- Hierarchical error classes with specific error codes
- Centralized error handling through the `ErrorHandler` module
- Structured logging with JSON format
- Result pattern for service operations
- Automatic retry capabilities for retryable errors

## Error Class Hierarchy

All ThreadAgent errors inherit from `ThreadAgent::Error`, which provides:
- `code`: Unique error identifier
- `context`: Additional error context data
- `retryable?`: Whether the error can be retried
- `to_h`: Structured hash representation

### Base Error Classes

#### `ThreadAgent::Error`
Base class for all ThreadAgent errors.

#### `ThreadAgent::ConfigurationError`
Configuration and initialization errors.
- **Code**: "CONFIGURATION_ERROR"
- **Retryable**: No

### Service-Specific Errors

#### Slack Errors
- `ThreadAgent::SlackError` (Base)
- `ThreadAgent::SlackAuthError` (Authentication)
- `ThreadAgent::SlackRateLimitError` (Rate limiting)

#### OpenAI Errors
- `ThreadAgent::OpenaiError` (Base)
- `ThreadAgent::OpenaiAuthError` (Authentication)
- `ThreadAgent::OpenaiRateLimitError` (Rate limiting)

#### Notion Errors
- `ThreadAgent::NotionError` (Base)
- `ThreadAgent::NotionAuthError` (Authentication)
- `ThreadAgent::NotionRateLimitError` (Rate limiting)

### Generic Errors
- `ThreadAgent::ValidationError` (Input validation)
- `ThreadAgent::ParseError` (Data parsing)
- `ThreadAgent::TimeoutError` (Request timeout)
- `ThreadAgent::ConnectionError` (Network issues)

## ErrorHandler Module

The `ThreadAgent::ErrorHandler` module provides:

### `standardize_error(exception, context = {})`
Converts any exception into a ThreadAgent::Error.

### `to_result(operation, context = {})`
Wraps operations in error handling and returns a `ThreadAgent::Result`.

### `log_error(error, additional_context = {})`
Logs errors in structured JSON format.

## Usage Examples

### Service Pattern
```ruby
def perform_operation(params)
  ThreadAgent::ErrorHandler.to_result("operation", { params: params }) do
    actual_work(params)
  end
rescue => e
  error = ThreadAgent::ErrorHandler.standardize_error(e, { params: params })
  raise error
end
```

### Job Pattern
```ruby
def perform(params)
  result = service.perform_operation(params)
  
  if result.failure? && Rails.env.test?
    error = ThreadAgent::ErrorHandler.standardize_error(result.error, {
      operation: "job_execution"
    })
    ThreadAgent::ErrorHandler.log_error(error)
    raise error
  end
end
```

## Best Practices

1. Always provide relevant context when handling errors
2. Use `ErrorHandler.to_result` for operations that may fail
3. Check `retryable?` before implementing retry logic
4. Log errors with structured context for monitoring
5. Update tests to expect specific ThreadAgent::Error subclasses

## Error Classification Logic

The `ErrorHandler.standardize_error` method classifies errors based on:

1. **Exception Type**: Direct mapping of known exception types
2. **Error Message**: Pattern matching for service-specific errors
3. **Context**: Additional context provided during error handling

### Classification Examples

```ruby
# Network errors become ConnectionError
Net::TimeoutError -> ThreadAgent::ConnectionError

# JSON parsing errors become ParseError  
JSON::ParserError -> ThreadAgent::ParseError

# OpenAI API errors based on message content
"Invalid API key" -> ThreadAgent::OpenaiAuthError
"Rate limit exceeded" -> ThreadAgent::OpenaiRateLimitError

# Slack API errors based on message content
"invalid_auth" -> ThreadAgent::SlackAuthError
"rate_limited" -> ThreadAgent::SlackRateLimitError

# Notion API errors based on message content
"Unauthorized" -> ThreadAgent::NotionAuthError
"Too Many Requests" -> ThreadAgent::NotionRateLimitError
```

## Structured Logging Format

All errors are logged in JSON format with these fields:

```json
{
  "timestamp": "2025-01-26T10:30:00Z",
  "level": "ERROR",
  "message": "Operation failed",
  "error": {
    "class": "ThreadAgent::OpenaiAuthError",
    "message": "Invalid API key provided",
    "code": "OPENAI_AUTH_ERROR",
    "retryable": false,
    "context": {
      "operation": "chat_completion",
      "model": "gpt-4"
    }
  },
  "additional_context": {
    "step": "openai_request",
    "workflow_run_id": "123"
  }
}
```

## Retry Strategies

### Retryable Errors

These error types are automatically retryable:
- `SlackRateLimitError`
- `OpenaiRateLimitError` 
- `NotionRateLimitError`
- `TimeoutError`
- `ConnectionError`

### Retry Implementation

Use the `retryable?` method to determine if an error should be retried:

```ruby
begin
  perform_operation
rescue ThreadAgent::Error => e
  if e.retryable? && retry_count < max_retries
    sleep(retry_delay)
    retry_count += 1
    retry
  else
    raise e
  end
end
```

## Testing Error Handling

### Unit Tests

Test error handling by stubbing service calls to raise specific errors:

```ruby
def test_handles_openai_auth_error
  OpenAI::Client.any_instance.stubs(:chat).raises(
    ThreadAgent::OpenaiAuthError.new("Invalid API key")
  )
  
  result = service.process_request(data)
  
  assert result.failure?
  assert_instance_of ThreadAgent::OpenaiAuthError, result.error
  assert_equal "OPENAI_AUTH_ERROR", result.error.code
end
```

### Integration Tests

Integration tests verify end-to-end error propagation:

```ruby
def test_workflow_handles_notion_errors
  stub_notion_api_error
  
  assert_raises ThreadAgent::NotionError do
    ProcessWorkflowJob.perform_now(workflow_run.id)
  end
end
```

## Migration Guide

When updating existing code to use the new error handling:

1. **Replace manual rescue blocks** with `ErrorHandler.to_result` or `ErrorHandler.standardize_error`
2. **Update error assertions** in tests to expect `ThreadAgent::Error` subclasses
3. **Add context** to error handling calls for better debugging
4. **Use structured logging** via `ErrorHandler.log_error` instead of manual logging
5. **Check retry logic** to use the `retryable?` method

### Before/After Example

```ruby
# Before
begin
  openai_api_call
rescue StandardError => e
  Rails.logger.error("OpenAI call failed: #{e.message}")
  raise ThreadAgent::OpenaiError, e.message
end

# After  
begin
  openai_api_call
rescue => e
  error = ThreadAgent::ErrorHandler.standardize_error(e, {
    operation: "openai_chat_completion",
    model: "gpt-4"
  })
  ThreadAgent::ErrorHandler.log_error(error, {
    step: "openai_request"
  })
  raise error
end
```

This standardized approach ensures consistent error handling, better debugging capabilities, and improved system reliability across the entire ThreadAgent application. 