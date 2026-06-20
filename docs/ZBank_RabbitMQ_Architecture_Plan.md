# ZBank RabbitMQ Architecture and Learning Plan

## Purpose

This document explains how RabbitMQ should be used in the ZBank microservices project and why each RabbitMQ component is chosen.

The goal is not only to integrate RabbitMQ, but to understand event-driven architecture deeply enough to make correct design decisions in real microservice systems.

ZBank uses RabbitMQ for asynchronous communication between services after important business events happen, such as:

- A credit card application is submitted.
- A credit card is activated.
- Other services need to react independently to those events.

## RabbitMQ in One Sentence

RabbitMQ is a message broker that receives messages from one service, routes them using rules, stores them safely in queues, and delivers them to other services when they are ready to process them.

## REST vs RabbitMQ in ZBank

ZBank uses both synchronous REST and asynchronous RabbitMQ messaging.

| Communication Type | Meaning | ZBank Example | Use When |
|---|---|---|---|
| REST | One service directly calls another and waits for the response | Card Application Service calls Credit Rating Service | The caller needs an immediate answer |
| RabbitMQ | One service publishes an event and continues without waiting for consumers | Card Application Service publishes `ApplicationSubmitted` | Other services can process later or independently |

## Why RabbitMQ Is Needed in ZBank

Without RabbitMQ, Card Application Service would need to directly call Card Activation Service, Card Management Service, and Notification Service.

That would create tight coupling:

- If Notification Service is down, application submission could fail.
- Card Application Service would need to know too much about downstream services.
- Adding a new consumer, such as Audit Service, would require changing the publisher.
- Long-running work would slow down user-facing APIs.

With RabbitMQ:

- Card Application Service only announces that an application was submitted.
- Card Activation Service reacts to that event.
- Card Management Service reacts when a card is activated.
- Notification Service reacts when a card is activated.
- Future services can subscribe without changing the original publisher.

## High-Level Message Flow

```text
User
 |
 | POST /api/v1/applications
 v
API Gateway
 |
 v
Card Application Service
 |
 | synchronous REST call
 v
Credit Rating Service
 |
 | score returned
 v
Card Application Service
 |
 | publishes ApplicationSubmitted
 v
RabbitMQ Exchange: zbank.exchange
 |
 | routing key: zbank.application.submitted
 v
card-activation-queue
 |
 v
Card Activation Service
 |
 | publishes CardActivated
 v
RabbitMQ Exchange: zbank.exchange
 |
 | routing key: zbank.card.activated
 |
 +----------------------------+
 |                            |
 v                            v
card-management-queue         notification-queue
 |                            |
 v                            v
Card Management Service       Notification Service
```

## RabbitMQ Components

### 1. Producer

A producer is a service that sends a message to RabbitMQ.

In ZBank:

| Producer | Event Published | Reason |
|---|---|---|
| Card Application Service | `ApplicationSubmitted` | An application was accepted and stored |
| Card Activation Service | `CardActivated` | A card was approved, generated, and activated |

Producer rule:

```text
A producer should publish facts about things that already happened.
```

Good event names:

- `ApplicationSubmitted`
- `CardActivated`
- `PinChanged`
- `NotificationSent`

Avoid command-like event names:

- `ActivateCardNow`
- `SendNotificationNow`
- `CreateCardImmediately`

Those are commands, not events.

### 2. Message

A message is the data sent through RabbitMQ.

ZBank messages should use JSON and represent domain events.

Example `ApplicationSubmitted`:

```json
{
  "eventType": "APPLICATION_SUBMITTED",
  "applicationId": "550e8400-e29b-41d4-a716-446655440000",
  "customerId": "user-uuid",
  "customerEmail": "john@example.com",
  "customerName": "John Doe",
  "creditScore": 500,
  "documentNumber": "PASS123456"
}
```

Example `CardActivated`:

```json
{
  "eventType": "CARD_ACTIVATED",
  "applicationId": "550e8400-e29b-41d4-a716-446655440000",
  "customerId": "user-uuid",
  "customerEmail": "john@example.com",
  "customerName": "John Doe",
  "cardNumber": "4000123456789010",
  "firstTimePin": "7432",
  "cardType": "PLATINUM",
  "creditLimit": 40000
}
```

Message design rules:

- Include enough information for consumers to act.
- Do not include unnecessary internal database details.
- Include stable IDs such as `applicationId` and `customerId`.
- Include an `eventType`.
- Consider adding `eventId`, `occurredAt`, and `version` for real production systems.

Recommended production-style event envelope:

```json
{
  "eventId": "event-uuid",
  "eventType": "CARD_ACTIVATED",
  "version": 1,
  "occurredAt": "2026-06-20T10:30:00Z",
  "payload": {
    "applicationId": "app-uuid",
    "customerId": "customer-uuid"
  }
}
```

### 3. Exchange

An exchange receives messages from producers and routes them to queues.

In ZBank:

```text
Exchange: zbank.exchange
Type: topic
```

The producer sends a message to the exchange, not directly to a queue.

The exchange decides where the message should go based on:

- Exchange type
- Routing key
- Queue bindings

### 4. Routing Key

A routing key is the address or category attached to a message.

ZBank routing keys:

```text
zbank.application.submitted
zbank.card.activated
```

Recommended format:

```text
system.domain.event
```

Examples:

```text
zbank.application.submitted
zbank.application.rejected
zbank.card.activated
zbank.card.pin.changed
zbank.notification.failed
```

### 5. Binding

A binding connects an exchange to a queue.

In simple terms:

```text
If a message with this routing key reaches this exchange, send it to this queue.
```

ZBank bindings:

```text
zbank.application.submitted -> card-activation-queue
zbank.card.activated        -> card-management-queue
zbank.card.activated        -> notification-queue
```

### 6. Queue

A queue stores messages until a consumer processes them.

ZBank queues:

```text
card-activation-queue
card-management-queue
notification-queue
```

Queue design rule:

```text
Use one queue per independent consuming service.
```

This is important because if two different services consume from the same queue, RabbitMQ distributes messages between them. Both services will not receive every message.

Correct:

```text
CardActivated -> card-management-queue
CardActivated -> notification-queue
```

Incorrect:

```text
CardActivated -> shared-card-activated-queue
```

If Card Management Service and Notification Service shared one queue, only one of them would receive each message.

### 7. Consumer

A consumer reads messages from a queue and performs work.

In ZBank:

| Consumer | Queue | Action |
|---|---|---|
| Card Activation Service | `card-activation-queue` | Approves/rejects application and generates card |
| Card Management Service | `card-management-queue` | Creates pending card record |
| Notification Service | `notification-queue` | Sends/logs email, SMS, and push notifications |

Consumer rule:

```text
Only acknowledge the message after business processing succeeds.
```

### 8. Acknowledgement

An acknowledgement, or ACK, tells RabbitMQ that the message was processed successfully.

Flow:

```text
RabbitMQ sends message to consumer.
Consumer processes message.
Consumer sends ACK.
RabbitMQ removes message from queue.
```

If processing fails before ACK, RabbitMQ can redeliver the message.

This is why consumers must be idempotent.

### 9. Dead Letter Queue

A dead-letter queue, or DLQ, stores messages that cannot be processed successfully.

Recommended ZBank DLQs:

```text
card-activation-dlq
card-management-dlq
notification-dlq
```

Use DLQ when:

- Message format is invalid.
- Required fields are missing.
- Business processing repeatedly fails.
- A consumer crashes repeatedly on the same message.

## Exchange Type Decision Matrix

| Exchange Type | Routing Behavior | Best For | Pros | Cons | ZBank Decision |
|---|---|---|---|---|---|
| Direct | Exact routing key match | Simple exact event routing | Easy to understand, predictable | No wildcard subscriptions | Could work, but less flexible |
| Topic | Pattern-based routing with `*` and `#` wildcards | Microservice domain events | Flexible, scalable, supports exact and broad subscriptions | Requires disciplined routing key naming | Recommended |
| Fanout | Sends every message to all bound queues | Broadcast events | Very simple broadcast model | No selective routing | Not suitable as main exchange |
| Headers | Routes using message headers | Complex metadata-based routing | Powerful for advanced filtering | Harder to reason about and maintain | Avoid for this project |

## Why ZBank Uses Topic Exchange

ZBank should use a topic exchange because the system uses domain events that naturally fit routing key patterns.

Current routing:

```text
zbank.application.submitted
zbank.card.activated
```

Future routing examples:

```text
zbank.application.rejected
zbank.card.blocked
zbank.card.pin.changed
zbank.notification.failed
```

With topic exchange, services can subscribe narrowly:

```text
notification-queue -> zbank.card.activated
```

Or broadly:

```text
audit-queue -> zbank.#
card-reporting-queue -> zbank.card.#
```

Topic wildcard rules:

| Wildcard | Meaning | Example |
|---|---|---|
| `*` | Matches exactly one word | `zbank.card.*` matches `zbank.card.activated` |
| `#` | Matches zero or more words | `zbank.card.#` matches `zbank.card.pin.changed` |

Examples:

```text
zbank.card.* matches zbank.card.activated
zbank.card.* does not match zbank.card.pin.changed
zbank.card.# matches zbank.card.activated
zbank.card.# matches zbank.card.pin.changed
zbank.# matches all ZBank events
```

## Queue Decision Matrix

| Queue Strategy | Meaning | Use When | ZBank Example |
|---|---|---|---|
| One queue per service | Each service has its own inbox | Multiple services need the same event independently | `card-management-queue`, `notification-queue` |
| Shared queue for same service instances | Multiple instances process messages from the same queue | Scaling one service horizontally | Three Card Activation instances consume `card-activation-queue` |
| Dead-letter queue | Failed messages go to a separate queue | Debugging and failure isolation | `notification-dlq` |
| Retry queue | Failed messages wait before being retried | Temporary failures | Retry notification after email provider failure |
| Priority queue | Higher priority messages are processed first | Some messages are urgent | Fraud alerts before normal notifications |

## Recommended ZBank RabbitMQ Topology

```text
Exchange:
  zbank.exchange
  type: topic

Queues:
  card-activation-queue
  card-management-queue
  notification-queue

Dead Letter Queues:
  card-activation-dlq
  card-management-dlq
  notification-dlq

Bindings:
  card-activation-queue:
    zbank.application.submitted

  card-management-queue:
    zbank.card.activated

  notification-queue:
    zbank.card.activated
```

## End-to-End ZBank Event Flow

### Step 1: Application Submitted by User

The user submits:

```http
POST /api/v1/applications
```

Card Application Service:

1. Validates the request.
2. Gets the customer identity from JWT.
3. Calls Credit Rating Service using REST.
4. Saves the application with status `PENDING`.
5. Publishes `ApplicationSubmitted`.
6. Returns `202 Accepted`.

### Step 2: ApplicationSubmitted Event Published

Published to:

```text
Exchange: zbank.exchange
Routing key: zbank.application.submitted
Queue: card-activation-queue
```

Card Application Service does not wait for activation to complete.

### Step 3: Card Activation Service Consumes ApplicationSubmitted

Card Activation Service:

1. Reads the event.
2. Applies allocation rules.
3. Saves activation record.
4. If score is 150 or above, publishes `CardActivated`.
5. If score is 50, saves `DOCUMENTS_REQUIRED` and does not publish `CardActivated`.

Allocation rules:

```text
500 -> PLATINUM, limit 40000
300 -> GOLD, limit 20000
150 -> VISA, limit 10000
50  -> DOCUMENTS_REQUIRED
```

### Step 4: CardActivated Event Published

Published to:

```text
Exchange: zbank.exchange
Routing key: zbank.card.activated
Queues:
  card-management-queue
  notification-queue
```

Both consumers receive their own copy.

### Step 5: Card Management Service Consumes CardActivated

Card Management Service:

1. Creates card record.
2. Stores card number.
3. Stores hashed first-time PIN.
4. Sets status to `PENDING_PIN_SETUP`.

### Step 6: Notification Service Consumes CardActivated

Notification Service:

1. Logs email notification.
2. Logs SMS notification.
3. Logs push notification.
4. Saves notification attempts.

## Reliability Requirements

### Message Durability

Queues should be durable so they survive RabbitMQ restarts.

Messages should be persistent so they are not lost if RabbitMQ restarts before delivery.

Recommended:

```text
durable exchange: true
durable queues: true
persistent messages: true
```

### Manual Acknowledgement

Consumers should use manual acknowledgement for important business events.

The consumer should ACK only after:

- Message is parsed.
- Business validation succeeds.
- Database changes are committed.
- Any required downstream event is published successfully.

### Idempotency

Consumers must tolerate duplicate messages.

RabbitMQ can redeliver messages if:

- A consumer crashes before ACK.
- Network issues occur.
- Processing times out.

ZBank idempotency rules:

| Service | Idempotency Rule |
---|---|
| Card Activation Service | Do not create duplicate activation for the same `applicationId` |
| Card Management Service | Do not create duplicate card for the same `applicationId` or `cardNumber` |
| Notification Service | Use `eventId` or `applicationId + channel` to avoid duplicate notification records |

### Retry Strategy

Recommended beginner-friendly retry approach:

1. Try processing the message.
2. If it fails due to temporary error, retry a limited number of times.
3. If it still fails, send to DLQ.

Temporary failures:

- Database temporarily unavailable.
- Email provider timeout.
- RabbitMQ connection issue.

Permanent failures:

- Invalid JSON.
- Missing required event field.
- Unknown card type.

### Dead Letter Strategy

Each main queue should have a DLQ:

```text
card-activation-queue -> card-activation-dlq
card-management-queue -> card-management-dlq
notification-queue -> notification-dlq
```

DLQs help prevent bad messages from blocking good messages.

## Transaction and Consistency Notes

RabbitMQ creates eventual consistency.

That means the system does not become fully updated everywhere at the same exact moment.

Example:

1. Application is saved as `PENDING`.
2. `ApplicationSubmitted` is published.
3. Activation happens later.
4. Card Management and Notification happen later.

For a short time, one service may know about something that another service has not processed yet.

This is normal in event-driven systems.

## Important Implementation Warning: Save and Publish Problem

There is a common distributed systems problem:

```text
What if the database save succeeds, but event publishing fails?
```

Example:

1. Card Application Service saves application as `PENDING`.
2. RabbitMQ publish fails.
3. Card Activation Service never receives `ApplicationSubmitted`.

For a learning project, direct publish after save is acceptable.

For production, use the outbox pattern:

1. Save business data and event record in the same database transaction.
2. A background publisher reads pending events from the outbox table.
3. The publisher sends events to RabbitMQ.
4. The outbox record is marked as published.

Outbox pattern is more reliable, but it adds complexity.

## ZBank Beginner Implementation Scope

For this project, implement:

- Topic exchange
- Durable queues
- JSON message converter
- One queue per consuming service
- RabbitMQ producer in Card Application Service
- RabbitMQ producer in Card Activation Service
- RabbitMQ consumer in Card Activation Service
- RabbitMQ consumer in Card Management Service
- RabbitMQ consumer in Notification Service
- Basic retry configuration
- Dead-letter queues
- Idempotency checks in consumers

Optional advanced improvements:

- Outbox pattern
- Event versioning
- Event replay
- Correlation IDs
- Distributed tracing
- RabbitMQ publisher confirms
- Retry queues with delay

## Recommended Spring Boot Components

Each RabbitMQ-enabled service should include:

```text
spring-boot-starter-amqp
```

Common configuration:

- `TopicExchange`
- `Queue`
- `Binding`
- `Jackson2JsonMessageConverter`
- `RabbitTemplate`
- `@RabbitListener`

Producer components:

- Event DTO from `common` module
- Publisher service
- `RabbitTemplate.convertAndSend(...)`

Consumer components:

- `@RabbitListener`
- Event handler service
- Idempotency validation
- Database transaction
- Error handling

## ZBank RabbitMQ Naming Standards

| Item | Naming Convention | Example |
|---|---|---|
| Exchange | `<system>.exchange` | `zbank.exchange` |
| Queue | `<service-purpose>-queue` | `card-activation-queue` |
| DLQ | `<service-purpose>-dlq` | `card-activation-dlq` |
| Routing key | `<system>.<domain>.<event>` | `zbank.card.activated` |
| Event class | Past-tense domain event | `CardActivatedEvent` |
| Publisher class | `<EventName>Publisher` or domain publisher | `ApplicationEventPublisher` |
| Consumer class | `<EventName>Listener` | `CardActivatedListener` |

## Pros and Cons of Event-Driven Architecture

### Pros

- Services are loosely coupled.
- User-facing APIs can respond faster.
- New services can subscribe to existing events.
- Systems are easier to scale independently.
- Temporary consumer downtime does not always break the producer.
- Multiple services can react to the same event independently.

### Cons

- Harder to debug than direct REST calls.
- Eventual consistency can confuse beginners.
- Duplicate message handling is required.
- Failed message handling needs careful design.
- Message schemas must be managed.
- Testing end-to-end flows requires more infrastructure.

## When to Use RabbitMQ

Use RabbitMQ when:

- Something happened and multiple services may care.
- The producer does not need an immediate response.
- Work can happen in the background.
- Consumers should be independently scalable.
- Temporary consumer downtime should not stop the producer.

Examples:

- Card activated
- Application submitted
- Notification requested
- Report generation requested
- Audit event recorded

## When Not to Use RabbitMQ

Do not use RabbitMQ when:

- The caller needs an immediate answer.
- The operation is simple and tightly coupled.
- The response is needed to continue the current request.
- Strong immediate consistency is required.

Example:

Card Application Service needs the credit score before it can save the application.

That should remain REST:

```text
Card Application Service -> Credit Rating Service
```

## ZBank Final Decision Summary

| Decision | Choice | Reason |
|---|---|---|
| Broker | RabbitMQ | Easier local setup and excellent for learning queues/exchanges |
| Exchange type | Topic | Supports exact and wildcard event routing |
| Main exchange | `zbank.exchange` | Single domain exchange for ZBank events |
| Queue model | One queue per consuming service | Ensures every independent service receives its own copy |
| Message format | JSON | Easy to debug and works well with Spring Boot |
| Event naming | Past tense | Events represent facts that already happened |
| Reliability | Durable queues, persistent messages, ACK after processing | Prevents unnecessary message loss |
| Failure handling | DLQ per queue | Keeps failed messages inspectable |
| Consistency model | Eventual consistency | Natural fit for asynchronous microservices |

## Learning Checklist

- [ ] Understand producer, exchange, routing key, binding, queue, consumer.
- [ ] Understand why producers send to exchanges instead of queues.
- [ ] Understand direct vs topic vs fanout vs headers exchanges.
- [ ] Understand why ZBank uses topic exchange.
- [ ] Understand why each independent service needs its own queue.
- [ ] Understand ACK, NACK, retries, and DLQ.
- [ ] Understand duplicate message risk and idempotency.
- [ ] Understand eventual consistency.
- [ ] Implement RabbitMQ config in Spring Boot.
- [ ] Publish `ApplicationSubmitted`.
- [ ] Consume `ApplicationSubmitted`.
- [ ] Publish `CardActivated`.
- [ ] Consume `CardActivated` in two independent services.
- [ ] Test the flow using RabbitMQ Management UI.

## RabbitMQ Management UI

When running RabbitMQ with Docker:

```yaml
rabbitmq:
  image: rabbitmq:3-management
  ports:
    - "5672:5672"
    - "15672:15672"
```

Use:

```text
AMQP port: 5672
Management UI: http://localhost:15672
Default username: guest
Default password: guest
```

In the UI, inspect:

- Exchanges
- Queues
- Bindings
- Message rates
- Ready messages
- Unacknowledged messages
- Dead-letter queues

## Final Recommended ZBank RabbitMQ Flow

```text
Card Application Service
  publishes ApplicationSubmitted
  exchange: zbank.exchange
  routing key: zbank.application.submitted

RabbitMQ
  routes to card-activation-queue

Card Activation Service
  consumes ApplicationSubmitted
  activates card if eligible
  publishes CardActivated
  exchange: zbank.exchange
  routing key: zbank.card.activated

RabbitMQ
  routes one copy to card-management-queue
  routes one copy to notification-queue

Card Management Service
  consumes CardActivated
  creates pending card record

Notification Service
  consumes CardActivated
  sends/logs Email, SMS, and Push notifications
```

This design gives ZBank a clean event-driven architecture while also teaching the most important RabbitMQ concepts used in real microservice systems.
