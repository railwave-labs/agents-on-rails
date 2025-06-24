# 🧱 Architecture Overview

## 1. System Overview

**Agents on Rails** is a Ruby on Rails application that provides automated workflow processing through AI-powered agents. The system orchestrates complex workflows by integrating Slack for user interaction, OpenAI for intelligent processing, and Notion for data management. Originally designed as a workflow automation platform, the application follows a **modular monolith** architecture pattern with the core functionality organized around the `ThreadAgent` domain.

The system processes user-initiated workflows from Slack, leverages AI to understand and execute tasks, and manages results in structured Notion databases. It's built to handle real-time webhook processing, background job execution, and multi-step workflow orchestration.

## 2. Tech Stack

### Core Framework
- **Ruby**: Latest stable version  
- **Rails**: Rails 8.0.2 with modern conventions
- **Database**: SQLite3 2.1+ with multiple database approach

### Key Gems & Libraries
- **Hotwire** (Turbo + Stimulus): Modern SPA-like interactions
- **Tailwind CSS**: Utility-first styling framework
- **Solid Suite**: Database-backed infrastructure (SolidQueue, SolidCache, SolidCable)
- **Testing**: Factory Bot, Mocha, WebMock for comprehensive testing

### External Services
- **Slack API**: Webhook processing, message formatting, modal interactions (via slack-ruby-client)
- **OpenAI API**: GPT-based intelligent workflow processing (via ruby-openai ~7.0)
- **Notion API**: Database management and content organization

### Infrastructure
- **SQLite3**: Multiple specialized databases (primary, cache, queue, cable)
- **SolidQueue**: Database-backed background job processing (no Redis needed)
- **SolidCache & SolidCable**: Database-backed caching and WebSocket functionality
- **Propshaft**: Modern Rails 8 asset pipeline

## 3. High-Level File Structure

```
app/
├── controllers/           # HTTP request handling
│   └── thread_agent/     # Domain-specific controllers
├── jobs/                 # Background job processing
│   └── thread_agent/     # Workflow processing jobs
├── models/               # Data models and business logic
│   └── thread_agent/     # Core domain models
├── services/             # Business logic and external integrations
│   └── thread_agent/     # Service objects for workflows
├── validators/           # Custom validation logic
└── views/                # Presentation layer
    └── thread_agent/     # Domain-specific views
```

### Domain Organization
- **ThreadAgent**: Primary domain handling workflow orchestration
- **Namespaced Structure**: Clean separation using Ruby modules
- **Service Layer**: Dedicated service objects for complex business logic
- **Concerns**: Shared behavior across models and controllers

## 4. Core Domains / Modules

### ThreadAgent Domain

**Purpose**: Orchestrates AI-powered workflows from Slack interactions to Notion data management.

**Key Models**:
- `WorkflowRun`: Tracks individual workflow executions with Slack context
- `Template`: Defines reusable workflow patterns and configurations
- `NotionWorkspace`: Manages Notion workspace connections and authentication
- `NotionDatabase`: Handles specific Notion database configurations

**Business Logic**:
- **Service Objects**: `ThreadAgent::OpenAI::Service`, `ThreadAgent::Slack::Service`
- **Job Processing**: `ThreadAgent::ProcessWorkflowJob` for async execution
- **Webhook Handling**: Real-time Slack event processing

**Key Patterns**:
- **Result Pattern**: Custom `ThreadAgent::Result` for consistent error handling
- **Service Composition**: Modular services for different integrations
- **Webhook Orchestration**: Event-driven architecture for external integrations

**Dependencies**:
- Slack API for user interactions and thread management
- OpenAI API for intelligent content processing
- Notion API for structured data storage

## 5. Key Architectural Patterns

### Service Object Pattern
```ruby
# Base service structure with result handling
class ThreadAgent::BaseService
  def call
    # Implementation with ThreadAgent::Result return
  end
end
```

### Retry and Error Handling
- **SafetyNetRetries**: Job concern for robust background processing
- **RetryHandler**: Service-specific retry logic with exponential backoff
- **ThreadAgent::Result**: Consistent success/failure handling across services

### Integration Patterns
- **Client Abstraction**: Dedicated client classes for external APIs
- **Message Building**: Structured message composition for AI interactions
- **Webhook Validation**: Secure webhook processing with proper authentication

### Background Processing
- **ProcessWorkflowJob**: Orchestrates multi-step workflow execution
- **Queue Management**: Separate queues for different types of processing
- **Job Reliability**: Built-in retry mechanisms and error recovery

## 6. Data Flow & Lifecycles

### Primary Workflow Lifecycle
1. **Slack Webhook Reception**: User triggers workflow from Slack thread
2. **Webhook Validation**: Security validation and request parsing
3. **WorkflowRun Creation**: Database record with Slack context
4. **Background Job Queuing**: Async processing initiation
5. **AI Processing**: OpenAI integration for content analysis
6. **Notion Integration**: Structured data storage and organization
7. **Slack Response**: User notification and result presentation

### Integration Data Flow
```
Slack Thread → Webhook → WorkflowRun → ProcessWorkflowJob → OpenAI → Notion → Slack Response
```

## 7. Integrations & External Systems

### Slack Integration
- **Webhooks**: Real-time event processing
- **Thread Management**: Context-aware conversation handling
- **Modal Interactions**: Rich user interface components
- **Message Formatting**: Structured response presentation

### OpenAI Integration
- **Message Building**: Context-aware prompt construction
- **Response Processing**: Intelligent content analysis and generation
- **Error Handling**: Robust API interaction with retry logic

### Notion Integration
- **Workspace Management**: Multi-workspace support
- **Database Operations**: Structured data creation and updates
- **Authentication**: Secure API access management

## 8. Testing Strategy

### Framework: Minitest
- **Test Organization**: Domain-specific test structure matching app organization
- **Factory Pattern**: Comprehensive test data factories
- **Integration Testing**: End-to-end workflow validation
- **Service Testing**: Isolated service object testing
- **Webhook Testing**: Secure webhook validation testing

### Testing Conventions
- **System Tests**: User workflow validation
- **Integration Tests**: Multi-service interaction testing
- **Unit Tests**: Individual component isolation
- **Mock Strategy**: External API mocking with WebMock/VCR

## 9. Deployment & Environments

### Application Architecture
- **Web Process**: HTTP request handling
- **Worker Process**: Background job processing
- **Database**: PostgreSQL with multiple schemas
- **Queue Management**: Dedicated queue processing

### Environment Structure
- **Development**: Local development with external API mocking
- **Test**: Isolated testing environment
- **Production**: Live system with full external integrations

## 10. SaaS & Multi-Tenancy Strategy

### Current Architecture
- **Single-Tenant**: Currently designed for single organization use
- **Workspace Scoping**: Notion workspace-based data isolation
- **Template System**: Reusable workflow configurations

### Future Evolution
- **Multi-Tenant Support**: Planned expansion for multiple organizations
- **API Exposure**: Potential REST/GraphQL API for external integrations
- **Role Management**: User permission and access control

## 11. Known Constraints / Technical Debt

### Current Limitations
- **Single-Tenant Architecture**: Requires evolution for SaaS scaling
- **Webhook Security**: Consider enhanced authentication mechanisms
- **Error Recovery**: Improve failed workflow recovery mechanisms
- **Performance Monitoring**: Add comprehensive application monitoring

### Technical Considerations
- **API Rate Limiting**: Implement proper rate limiting for external APIs
- **Data Validation**: Enhanced validation for external data inputs
- **Caching Strategy**: Implement caching for frequently accessed data
- **Logging Enhancement**: Structured logging for better observability

### Future Refactoring Opportunities
- **Service Extraction**: Consider microservice extraction for heavy processing
- **Database Optimization**: Query optimization and indexing strategy
- **Background Job Scaling**: Enhanced job processing architecture
- **Integration Resilience**: Improved failure handling and recovery mechanisms 