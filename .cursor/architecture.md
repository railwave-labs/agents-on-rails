# 🧱 ThreadAgent Architecture Overview

## 1. System Overview

ThreadAgent is a Rails 8 application that processes Slack threads and creates structured documentation in Notion through automated workflows. The system operates as a webhook-driven service that bridges communication in Slack with knowledge management in Notion. Originally designed as a modular monolith to facilitate future gem extraction, ThreadAgent implements service-oriented patterns with comprehensive error handling and background job processing.

The application follows a **modular monolith** architecture style, with clear domain boundaries under the `ThreadAgent` namespace, positioning it for potential extraction as a standalone gem or microservice.

## 2. Tech Stack

- **Ruby Version**: Ruby 3.x (Rails 8.0.2)
- **Framework**: Rails 8.0.2 with modern defaults
- **Key Libraries**:
  - **Hotwire**: Turbo Rails + Stimulus for SPA-like interactions
  - **Tailwind CSS**: Utility-first styling
  - **Solid Queue**: Background job processing (Rails 8 default)
  - **Solid Cache**: Database-backed caching
  - **Solid Cable**: WebSocket connections
- **External Integrations**:
  - **Slack API**: `slack-ruby-client` for webhook handling and thread fetching
  - **OpenAI API**: `ruby-openai` (~> 8.1) for content transformation
  - **Notion API**: `notion-ruby-client` (~> 1.2) for page creation
- **Database**: SQLite3 (development/test), configurable for production PostgreSQL
- **Testing**: Minitest with Factory Bot, Mocha, WebMock, and Capybara
- **Code Quality**: Brakeman (security), RuboCop Rails Omakase (style)
- **Infrastructure**: Designed for containerized deployment (Dockerfile included)

## 3. High-Level File Structure

```
app/
├── controllers/thread_agent/    # Webhook endpoints
├── jobs/thread_agent/          # Background job processing
├── models/thread_agent/        # Domain models (WorkflowRun, Template, etc.)
├── services/thread_agent/      # Service layer with integration modules
│   ├── slack/                  # Slack-specific services
│   ├── openai/                 # OpenAI-specific services
│   ├── notion/                 # Notion-specific services
│   └── workflow_orchestrator.rb # Main workflow coordination
└── validators/                 # Custom validation logic

lib/thread_agent/               # Core library functionality
├── error_handler.rb           # Centralized error handling
├── result.rb                  # Result pattern implementation
└── thread_agent.rb            # Main module and configuration
```

**Custom Conventions**:
- All ThreadAgent functionality is namespaced for future gem extraction
- Service objects follow a consistent pattern with Result objects
- Error handling is centralized through the ErrorHandler module
- Background jobs use SafetyNetRetries concern for robust processing

## 4. Core Domains / Modules

### ThreadAgent::WorkflowRun
- **Purpose**: Tracks the complete lifecycle of thread processing workflows
- **Key Models**: `WorkflowRun` (status tracking, steps logging, I/O data)
- **Business Logic**: Status transitions, step tracking, duration calculation
- **Patterns**: Enum for status, JSON serialization for complex data
- **Dependencies**: Optional Template association, Slack metadata tracking
- **Constraints**: Validates workflow state transitions and data integrity

### ThreadAgent::Template
- **Purpose**: Defines reusable content transformation templates with Notion integration
- **Key Models**: `Template`, `NotionDatabase`, `NotionWorkspace`
- **Business Logic**: Template content processing, Notion database association
- **Patterns**: Status enum, foreign key constraints
- **Dependencies**: Links to specific Notion databases for page creation
- **Constraints**: Unique template names, active/inactive status management

### ThreadAgent::Slack Integration
- **Purpose**: Handles Slack webhook validation, thread fetching, and user interactions
- **Key Models**: Service layer only (no direct models)
- **Business Logic**: Webhook validation, thread processing, modal interactions
- **Patterns**: Service composition with dedicated handlers
- **Dependencies**: Slack API, signing secret validation
- **Constraints**: Rate limiting, authentication requirements

### ThreadAgent::OpenAI Integration
- **Purpose**: Transforms raw Slack thread content into structured documentation
- **Key Models**: Service layer only
- **Business Logic**: Message building, content transformation, response parsing
- **Patterns**: Builder pattern for message construction
- **Dependencies**: OpenAI API, model configuration
- **Constraints**: Token limits, rate limiting, timeout handling

### ThreadAgent::Notion Integration
- **Purpose**: Creates and manages Notion pages from processed content
- **Key Models**: `NotionWorkspace`, `NotionDatabase`
- **Business Logic**: Page creation, database selection, workspace management
- **Patterns**: Service delegation, retry handling
- **Dependencies**: Notion API, workspace-specific tokens
- **Constraints**: Database permissions, workspace isolation

## 5. Key Architectural Patterns

### Service Object Pattern
- **Base Implementation**: Each service module follows consistent initialization and method patterns
- **Error Handling**: All services return Result objects with success/failure states
- **Namespacing**: Services organized by integration domain (Slack, OpenAI, Notion)
- **Retry Logic**: Standardized retry handlers with exponential backoff

### Result Pattern
```ruby
# Consistent return pattern across all services
class Result
  def self.success(data = nil, metadata = {})
  def self.failure(error = nil, metadata = {})
  def success? / failure?
end
```

### Centralized Error Handling
- **ErrorHandler Module**: Standardizes all exception types into ThreadAgent errors
- **Hierarchical Errors**: Specific error types (ValidationError, ConnectionError, etc.)
- **Structured Logging**: JSON-formatted error logs with context
- **Service Integration**: Uniform error handling across all service layers

### Background Job Processing
- **SafetyNetRetries Concern**: Provides robust retry logic for transient failures
- **Workflow Orchestration**: Single job coordinates multi-service workflows
- **Step Tracking**: Each workflow step is logged for debugging and monitoring

### Modular Architecture
- **Namespace Isolation**: All ThreadAgent code is properly namespaced
- **Gem-Ready Structure**: Organized for potential extraction as standalone gem
- **Configuration Pattern**: Centralized configuration with environment variable mapping

## 6. Data Flow & Lifecycles

### Primary Workflow: Slack Thread → Notion Page

1. **Webhook Reception**:
   ```
   Slack Event → WebhookController → Validation → Job Enqueue
   ```

2. **Background Processing**:
   ```
   ProcessWorkflowJob → WorkflowOrchestrator → Service Chain
   ```

3. **Service Chain Execution**:
   ```
   Slack Service (thread fetch) → 
   OpenAI Service (content transform) → 
   Notion Service (page creation)
   ```

4. **State Management**:
   ```
   WorkflowRun: pending → running → completed/failed
   Step tracking at each service boundary
   ```

### Error Flow
```
Service Error → ErrorHandler.standardize_error → 
Structured Logging → Result.failure → 
Workflow Termination → Status Update
```

## 7. Integrations & External Systems

| System         | Purpose                         | Data Exchange                         | Configuration                  |
| -------------- | ------------------------------- | ------------------------------------- | ------------------------------ |
| **Slack API**  | Webhook events, thread fetching | Inbound webhooks, outbound API calls  | Bot token, signing secret      |
| **OpenAI API** | Content transformation          | Request/response with thread data     | API key, model selection       |
| **Notion API** | Page/database management        | Page creation with structured content | Workspace tokens, database IDs |

### Integration Patterns
- **Webhook Validation**: HMAC signature verification for Slack events
- **Retry Logic**: Exponential backoff for all external API calls  
- **Rate Limiting**: Built-in handling for API rate limits
- **Token Management**: Workspace-specific Notion tokens for multi-tenancy

## 8. Testing Strategy

### Framework & Organization
- **Minitest**: Rails default testing framework
- **Factory Bot**: Test data generation with realistic factories
- **Test Structure**:
  ```
  test/
  ├── controllers/thread_agent/     # Webhook endpoint tests
  ├── jobs/thread_agent/           # Background job tests
  ├── services/thread_agent/       # Service layer tests
  ├── models/thread_agent/         # Model validation tests
  ├── integration/                 # End-to-end workflow tests
  └── system/                      # Browser-based system tests
  ```

### Testing Patterns
- **WebMock**: External API mocking for isolated unit tests
- **Mocha**: Test doubles and stubbing for service interactions
- **Integration Tests**: Full workflow testing with real service coordination
- **System Tests**: Selenium-based browser testing for UI components

### Coverage Standards
- **Service Layer**: Comprehensive unit tests with mocked dependencies
- **Integration**: End-to-end tests covering complete workflows
- **Error Scenarios**: Explicit testing of failure modes and error handling

## 9. Deployment & Environments

### Containerization
- **Docker**: Dockerfile provided for containerized deployment
- **Multi-stage Build**: Optimized for production deployment

### Environment Configuration
- **Development**: SQLite3, local service stubs
- **Test**: In-memory/temporary databases, mocked external services
- **Production**: PostgreSQL (recommended), Redis for job queue, environment-based secrets

### Process Architecture
- **Web Process**: Rails server handling webhook requests
- **Worker Process**: Solid Queue workers for background job processing
- **Database**: Solid Cache/Queue using database backend (Rails 8 default)

### CI/CD Considerations
- **Database Migrations**: Rails 8 migration framework
- **Environment Variables**: Comprehensive environment variable configuration
- **Health Checks**: Rails health check endpoint (`/up`)

## 10. Multi-Tenancy Strategy

### Current Implementation
- **Workspace-Level Tenancy**: Notion workspaces as primary tenant boundary
- **Slack Team Isolation**: Each workspace linked to specific Slack team
- **Token Scoping**: Notion access tokens scoped to individual workspaces

### Data Isolation
```ruby
# Workspace-specific data access
NotionWorkspace.find_by(slack_team_id: team_id)
Templates.where(notion_database: workspace.databases)
```

### Planned Evolution
- **API Exposure**: RESTful API for workspace management
- **Role Management**: User permissions within workspace contexts
- **Subscription Model**: Usage-based billing and feature access

## 11. Known Constraints / Technical Debt

### Current Limitations
- **SQLite in Production**: Not recommended for concurrent access patterns
- **Synchronous Processing**: Some operations could benefit from streaming
- **Error Recovery**: Limited workflow resumption after partial failures

### Scalability Considerations
- **Database Connection Pooling**: May need optimization for high-volume usage
- **Job Queue Scaling**: Solid Queue performance under heavy load needs monitoring
- **External API Rate Limits**: May need request queuing/throttling mechanisms

### Future Refactoring Opportunities
- **Service Interface Standardization**: Further abstract common service patterns
- **Configuration Management**: Move toward more sophisticated config management
- **Monitoring Integration**: Add structured metrics and observability
- **Performance Optimization**: Database query optimization and caching strategies

---

## Development Patterns

### Adding New Integrations
1. Create service module under `app/services/thread_agent/[service_name]/`
2. Implement Client, Service, and supporting classes
3. Add error classes in `lib/thread_agent/` 
4. Include retry handling and Result pattern
5. Add comprehensive test coverage
6. Update WorkflowOrchestrator if needed

### Error Handling Best Practices
- Use `ThreadAgent::ErrorHandler.standardize_error` for external exceptions
- Return `ThreadAgent::Result` objects from all service methods
- Log errors with structured context using `ErrorHandler.log_error`
- Implement retryable error detection for transient failures

### Configuration Management
- Add new environment variables to `config/initializers/thread_agent.rb`
- Follow the `THREAD_AGENT_` prefix convention
- Include configuration validation in the initializer
- Document new variables in environment documentation

---

*This architecture serves as the foundation for a scalable, maintainable Rails application that bridges communication tools with knowledge management systems through automated AI-powered workflows.* 