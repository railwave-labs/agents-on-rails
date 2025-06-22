# ThreadAgent Architecture Overview

## 1. System Overview

ThreadAgent is a Rails 8.0 webhook processing application that bridges Slack and Notion workspaces. The system captures Slack thread conversations through webhooks and transforms them into structured Notion pages using configurable templates. Originally built as a focused integration tool, ThreadAgent follows a **modular monolith** architecture with clear service boundaries, preparing for potential gem extraction. The application emphasizes reliability through comprehensive error handling, retry mechanisms, and the Result pattern for consistent service responses.

## 2. Tech Stack

**Framework & Runtime:**
- Ruby 3.3.5, Rails 8.0.2
- SQLite3 2.1+ (all environments, with PostgreSQL as future scaling option if needed)

**Key Dependencies:**
- `slack-ruby-client` - Slack API integration and webhook processing
- `solid_queue` - Database-backed background job processing (Rails 8 modern alternative to Sidekiq)
- `solid_cache` - Database-backed caching system
- `solid_cable` - WebSocket functionality
- `tailwindcss-rails` - Modern CSS framework
- `turbo-rails` & `stimulus-rails` - Hotwire for SPA-like interactions
- `dotenv-rails` - Environment variable management

**External Services:**
- Slack Web API (webhooks, modals, thread fetching)
- Notion API (page creation, database integration)
- OpenAI API (content processing and enhancement)

**Infrastructure:**
- Job Queue: SolidQueue (database-backed, eliminates Redis dependency)
- Asset Pipeline: Propshaft (Rails 8 modern asset handling)
- Web Server: Puma (multi-threaded)
- JavaScript: Import maps with Stimulus controllers

## 3. High-Level File Structure

```
app/
├── controllers/
│   ├── application_controller.rb
│   └── thread_agent/           # Namespaced webhook controllers
├── models/
│   ├── application_record.rb
│   └── thread_agent/           # Domain models
├── services/
│   └── thread_agent/           # Business logic layer
│       └── slack/              # Slack-specific services
├── jobs/
│   └── thread_agent/           # Background processing
├── views/
│   ├── layouts/
│   └── thread_agent/           # Webhook response views
└── validators/                 # Custom validation classes

lib/
└── thread_agent/               # Core library code
    └── result.rb               # Result pattern implementation

config/
├── initializers/
│   └── thread_agent.rb         # Module configuration
└── routes.rb                   # RESTful routing
```

**Domain Namespacing:** All ThreadAgent functionality is encapsulated within the `ThreadAgent::` namespace, enabling clean separation and future gem extraction.

## 4. Core Domains / Modules

### ThreadAgent::WorkflowRun
**Purpose:** Tracks the lifecycle of webhook-triggered workflows from Slack to Notion
**Key Models:** 
- `WorkflowRun` - Central workflow state management with status enum
**Business Logic:** Status transitions, duration tracking, error capture
**Patterns:** State machine pattern with enum statuses (`pending`, `running`, `completed`, `failed`, `cancelled`)
**Dependencies:** Slack message tracking, background job coordination
**Constraints:** JSON steps field requires careful serialization management

### ThreadAgent::NotionWorkspace
**Purpose:** Multi-tenant Notion workspace management with Slack team mapping
**Key Models:**
- `NotionWorkspace` - Workspace configuration and access tokens
- `NotionDatabase` - Database-level template targeting
**Business Logic:** OAuth token management, team-to-workspace mapping
**Patterns:** Has-many relationship with databases, status enum management
**Dependencies:** Notion API authentication, Slack team validation
**Constraints:** Access token encryption and rotation strategy needed

### ThreadAgent::Template
**Purpose:** Content transformation templates for Slack-to-Notion conversion
**Key Models:**
- `Template` - Reusable content transformation rules
**Business Logic:** Template rendering, content formatting
**Patterns:** Belongs-to NotionDatabase for targeted page creation
**Dependencies:** Notion database schema compatibility
**Constraints:** Template versioning and migration strategy pending

### ThreadAgent::Slack Services
**Purpose:** Comprehensive Slack API integration and webhook processing
**Key Components:**
- `Service` - Main orchestrator and dependency coordinator
- `WebhookRequestHandler` - Security validation and payload processing
- `SlackClient` - API communication wrapper
- `RetryHandler` - Exponential backoff and rate limit handling
**Business Logic:** HMAC validation, thread fetching, modal generation, shortcut handling
**Patterns:** Service object pattern with Result returns, delegation pattern
**Dependencies:** Slack Web API, webhook signature validation
**Constraints:** Rate limiting requires careful retry strategy management

## 5. Key Architectural Patterns

### Service Object Pattern
**Base Structure:** All services return `ThreadAgent::Result` objects for consistent error handling
```ruby
class Service
  def method_name
    # Business logic
    ThreadAgent::Result.success(data)
  rescue => e
    ThreadAgent::Result.failure(error_message)
  end
end
```

**Error Handling:** Result pattern eliminates exception-based control flow
**Namespacing:** Services organized under `ThreadAgent::Slack::` for clear boundaries

### Result Pattern Implementation
```ruby
ThreadAgent::Result.success(data, metadata)
ThreadAgent::Result.failure(error, metadata)
result.success? / result.failure?
```
**Benefits:** Predictable return values, structured error handling, metadata support

### Configuration Management
**Pattern:** Centralized configuration with environment variable defaults
```ruby
ThreadAgent.configure do |config|
  config.slack_bot_token = ENV['THREAD_AGENT_SLACK_BOT_TOKEN']
  # ... other settings
end
```

### Retry Strategy Pattern
**Implementation:** `RetryHandler` with exponential backoff for different error types
- Rate limit errors: Use Slack's `retry_after` header
- Timeout errors: Exponential backoff with max delay cap
- Server errors: Retry with backoff, client errors fail immediately

## 6. Data Flow & Lifecycles

### Primary Workflow: Slack Thread → Notion Page
```
Slack Webhook → Security Validation → Payload Processing → Background Job → Notion Integration
```

**Detailed Flow:**
1. **Webhook Reception:** POST to `/thread_agent/webhooks/slack`
2. **Security Layer:** HMAC signature validation, timestamp verification
3. **Payload Routing:** Switch on webhook type (`shortcut`, `view_submission`, etc.)
4. **Modal Interaction:** Shortcut triggers modal for workspace/template selection
5. **Job Enqueue:** Modal submission triggers `ProcessWorkflowJob`
6. **Background Processing:** Job fetches thread data and creates Notion page
7. **Status Tracking:** WorkflowRun tracks progress and captures errors

### Configuration Lifecycle
```
Environment Variables → ThreadAgent::Configuration → Service Initialization → API Clients
```

### Error Recovery Flow
```
Service Error → Result.failure → Controller Response → Client Retry (if applicable)
Background Job Error → Retry with Backoff → Final Failure → Error Logging
```

## 7. Integrations & External Systems

| System            | Purpose                                             | Data Exchange          | Authentication              |
| ----------------- | --------------------------------------------------- | ---------------------- | --------------------------- |
| **Slack Web API** | Thread fetching, modal creation, webhook validation | Bidirectional REST API | Bot tokens, signing secrets |
| **Notion API**    | Page creation, database queries                     | Outbound REST API      | OAuth workspace tokens      |
| **OpenAI API**    | Content processing (planned)                        | Outbound REST API      | API keys                    |

**Integration Patterns:**
- **Slack:** Event-driven via webhooks, synchronous API calls for responses
- **Notion:** Batch processing via background jobs, workspace-scoped operations
- **OpenAI:** Content enhancement pipeline (future implementation)

## 8. Testing Strategy

**Framework:** Minitest (Rails default)
**Organization:**
```
test/
├── controllers/thread_agent/     # Webhook endpoint testing
├── models/thread_agent/          # Model validation and relationships
├── services/thread_agent/        # Service object business logic
├── jobs/thread_agent/            # Background job processing
├── integration/                  # End-to-end workflow testing
└── factories/thread_agent/       # Test data generation
```

**Key Patterns:**
- **Mocking:** Extensive use of `mocha` for external API calls
- **Factories:** FactoryBot for consistent test data
- **Integration Tests:** Full webhook-to-database workflows
- **Service Testing:** Result pattern validation and error scenarios

**Notable Conventions:**
- Slack API responses mocked to avoid external dependencies
- Webhook signature validation tested with real HMAC generation
- Error scenarios tested for each retry strategy

## 9. Deployment & Environments

**Production Configuration:**
- **SSL/TLS:** Forced HTTPS with Strict-Transport-Security headers
- **Logging:** STDOUT with structured request ID tagging
- **Caching:** SolidCache for database-backed consistency
- **Job Processing:** SolidQueue with configurable worker processes

**Environment Structure:**
- **Development:** SQLite, memory cache, synchronous jobs
- **Test:** In-memory database, null cache, inline job processing
- **Production:** SQLite with SolidCache, background workers

**Process Architecture:**
```yaml
# config/queue.yml
workers:
  - queues: "*"
    threads: 3
    processes: 1  # Scale based on job volume
    polling_interval: 0.1
```

**Health Monitoring:** Built-in `/up` endpoint for load balancer health checks

## 10. SaaS & Multi-Tenancy Strategy

**Current Tenant Model:** Slack team ID isolation via `NotionWorkspace.slack_team_id`
**Scoping Strategy:** Row-level filtering by Slack team throughout the system
**Shared Resources:** Templates can be shared across workspaces via NotionDatabase associations
**Data Isolation:** Each Slack team maintains separate Notion workspace configurations

**Planned Evolution:**
- Enhanced onboarding flow for new Slack teams
- Template marketplace for shared configurations
- Role-based access within Slack teams
- API exposure for programmatic integration

## 11. Known Constraints / Technical Debt

**Current Limitations:**
- **Database:** SQLite-first approach with PostgreSQL migration only if scaling demands require it
- **Job Processing:** Single-process worker configuration limits throughput
- **Template System:** Basic content transformation, needs versioning and migration strategy
- **Error Monitoring:** Basic Rails logging, needs structured monitoring (Sentry, etc.)

**Technical Debt:**
- **Webhook Processing:** Limited payload validation beyond basic structure checks
- **Configuration Management:** Environment variables could benefit from Rails credentials
- **Testing:** VCR cassettes for API integration testing not yet implemented
- **Monitoring:** No structured metrics for job processing latency or error rates

**Scalability Considerations:**
- **Database Connections:** SolidQueue worker scaling tied to SQLite connection limits (PostgreSQL migration threshold to be determined by actual usage)
- **Rate Limiting:** Slack API limits require careful job scheduling
- **Token Management:** Notion access token refresh strategy needed
- **Multi-Region:** Single-region deployment limits global webhook latency

**SaaS Transition Risks:**
- **Data Privacy:** Cross-tenant data isolation verification needed
- **Billing Integration:** Usage tracking and billing system integration pending
- **Support Tooling:** Admin interface for workspace management and debugging
- **Backup Strategy:** Tenant data backup and restore procedures

---

*This architecture supports ThreadAgent's evolution from a focused integration tool to a scalable SaaS platform while maintaining clear service boundaries and preparing for future gem extraction.* 