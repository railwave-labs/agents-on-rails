# 🏗️ Thread Agent - Architecture Overview

## 1. System Overview

Thread Agent is a **modular monolithic** Rails application that serves as a Slack-to-Notion integration platform. The system captures Slack message threads, processes them using AI (OpenAI), and transforms them into structured Notion documents. The application is architected as a **gem-extraction ready** system, with all functionality cleanly namespaced under the `ThreadAgent` module to enable future extraction as a standalone gem.

The application follows an **event-driven architecture** for webhook processing and uses **background job processing** for AI-powered transformations. It implements a comprehensive workflow orchestration system that tracks each step of the thread-to-notion transformation process.

**Architecture Style**: Modular Monolith with Gem-Ready Organization
**Domain**: Single-domain focused on workflow orchestration and external service integration
**Processing Model**: Synchronous webhook handling + Asynchronous AI processing

## 2. Tech Stack

- **Ruby**: 3.x+ (using modern syntax like pattern matching, endless methods)
- **Rails**: 8.0+ (latest Active Record features, Solid Queue)
- **Database**: SQLite (development), PostgreSQL (production)
- **Background Jobs**: Solid Queue (Rails 8 native job processing)
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **Testing**: Minitest with Factory Bot patterns

### Key Dependencies
- **External APIs**: `ruby-openai`, `notion-ruby-client`, Custom Slack client
- **HTTP Client**: Faraday (for external service communications)
- **Configuration**: Environment-based with override patterns
- **Authentication**: HTTP Basic Auth (admin interface)

### External Services
- **Slack API**: Bot tokens, webhook events, modal interactions
- **OpenAI API**: GPT-4o-mini for content transformation
- **Notion API**: Workspace and database management, page creation

## 3. High-Level File Structure

```
app/
├── controllers/
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

lib/
└── thread_agent/         # Core module and shared utilities
    └── result.rb         # Result pattern implementation

config/
├── initializers/
│   └── thread_agent.rb   # Module configuration
└── routes.rb             # Scoped routing under /thread_agent

test/
├── controllers/thread_agent/  # Controller tests
├── jobs/thread_agent/         # Job tests
├── models/thread_agent/       # Model tests
├── services/thread_agent/     # Service tests
└── lib/thread_agent/          # Library tests
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
- **Content Transformation**: AI-powered thread analysis
- **Template Processing**: Customizable prompt engineering
- **Error Handling**: Robust API failure management
- **Model Configuration**: Flexible model selection (GPT-4o-mini default)

### Notion Integration
- **Workspace Management**: Multi-workspace support
- **Database Operations**: Dynamic database selection
- **Page Creation**: Structured content generation
- **Access Control**: Token-based authentication

## 8. Testing Strategy

### Framework & Organization
- **Framework**: Minitest with Rails 8 conventions
- **Structure**: Mirror app/ structure under test/
- **Factories**: Custom factory patterns for ThreadAgent models
- **Mocking**: Service-level mocking for external APIs

### Test Patterns
- **Unit Tests**: Service objects, models, and utilities
- **Integration Tests**: End-to-end workflow validation
- **System Tests**: Slack webhook to Notion page creation
- **Mock Strategy**: External API calls mocked at service layer

### Coverage Standards
- **Service Objects**: Complete coverage including error paths
- **Models**: Validation and relationship testing
- **Jobs**: Background processing and retry logic
- **Controllers**: Webhook handling and error responses

## 9. Deployment & Environments

### Configuration Management
- **Environment Variables**: API keys and sensitive configuration
- **ThreadAgent.configure**: Block-based configuration pattern
- **Defaults**: Sensible defaults with environment overrides
- **Validation**: Configuration completeness checking

### Background Processing
- **Solid Queue**: Rails 8 native job processing
- **SafetyNetRetries**: Multi-level retry strategies
- **Queue Management**: Priority-based job processing
- **Monitoring**: Job status tracking and error reporting

## 10. Gem-Ready Architecture Strategy

### Namespace Organization
All components are organized under the `ThreadAgent` module for clean extraction:

```ruby
# Configuration pattern ready for gem extraction
module ThreadAgent
  class Configuration
    # Environment-based defaults with override capability
  end
  
  def self.configure
    yield(configuration)
  end
end
```

### Route Scoping
```ruby
# All routes under /thread_agent namespace
Rails.application.routes.draw do
  scope path: '/thread_agent', module: 'thread_agent' do
    # Routes ready for engine mounting
  end
end
```

### Database Strategy
- **Table Prefixes**: All tables prefixed with `thread_agent_`
- **Namespace Models**: All models under `ThreadAgent` module
- **Clean Migration**: Extraction-ready database structure

### Service Architecture
- **Result Objects**: Consistent return patterns across services
- **Configuration Injection**: Easy testing and future gem configuration
- **External Dependencies**: Isolated to ThreadAgent namespace

## 11. Known Constraints / Technical Debt

### Current Limitations
- **Single-Tenant**: No multi-tenancy isolation (Slack team scoping only)
- **File Attachments**: Not yet supported in thread processing
- **Real-time Notifications**: Limited to Slack modal responses
- **AI Model Configuration**: Basic model selection, no advanced tuning

### Future Extraction Considerations
- **Engine Migration**: Service layer ready for Rails engine extraction
- **Configuration Evolution**: ThreadAgent.configure pattern scales well
- **Database Migration**: Table prefixes enable clean separation
- **Route Organization**: Namespace scoping supports engine mounting

### Testing Debt
- **API Mocking**: Could benefit from more sophisticated VCR patterns
- **Integration Coverage**: End-to-end testing could be expanded
- **Performance Testing**: No load testing for background job processing

### Scalability Considerations
- **Background Job Scaling**: Single queue may need partitioning
- **Database Growth**: WorkflowRun table could grow large over time
- **API Rate Limiting**: External service rate limits not yet handled
- **Error Recovery**: Manual intervention needed for some failure scenarios

---

## 🎯 Key Design Decisions

1. **Gem-Ready Architecture**: All code namespaced for future extraction
2. **Service Layer Composition**: Modular services over monolithic controllers
3. **Result Pattern**: Consistent error handling across all operations
4. **Background Processing**: Async workflows with comprehensive retry logic
5. **Configuration Flexibility**: Environment defaults with programmatic overrides
6. **Clean Database Design**: Prefixed tables and namespaced models
7. **Integration Abstractions**: Service clients isolate external dependencies

This architecture supports the current Slack-to-Notion workflow while maintaining flexibility for future enhancements and potential gem extraction. 