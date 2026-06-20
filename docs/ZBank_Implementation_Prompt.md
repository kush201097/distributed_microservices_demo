# Z Bank — Comprehensive Microservices Implementation Prompt

---

## Context

You are implementing **Z Bank**, a credit card management system built using a **distributed microservices architecture** in Java (Spring Boot). The primary goal is to demonstrate both **synchronous (REST)** and **asynchronous (event-driven)** inter-service communication.

---

## Overall Architecture

Seven standalone Spring Boot microservices, each with its own database, communicating via REST (sync) and a message broker (async):

| # | Service | Port | Responsibility |
|---|---------|------|----------------|
| 1 | API Gateway | 8080 | Route all requests, validate user JWT, forward user context |
| 2 | Auth Service | 8081 | Issue and validate user JWTs and service-to-service JWTs |
| 3 | Card Application Service | 8082 | Accept and submit new credit card applications |
| 4 | Credit Rating Service | 8083 | Calculate or look up credit scores |
| 5 | Card Activation Service | 8084 | Approve/reject application, assign card type and limit |
| 6 | Card Management Service | 8085 | Handle first-time login and PIN change |
| 7 | Notification Service | 8086 | Deliver email/SMS/push notifications on card activation |

**Message Broker:** RabbitMQ (or Kafka — choose one and be consistent)
**Databases:** Each service uses its own Microsoft SQL Server database. No shared DB.
**Language:** Java 17+, Spring Boot 3.x
**Build tool:** Maven (multi-module project)

**Authentication model:**
- **User authentication:** External clients authenticate with email/password. Auth Service issues a user JWT used by API Gateway and protected user-facing APIs.
- **Machine-to-machine (M2M) authentication:** Internal services authenticate with client credentials. Auth Service issues short-lived service JWTs used for synchronous internal REST calls.
- **Broker authentication:** RabbitMQ credentials protect broker access. Event payloads must also include producer metadata for traceability, but RabbitMQ username/password is the transport-level authentication mechanism.

---

## Project Structure

```
zbank/
├── pom.xml                          (parent POM)
├── api-gateway/
├── auth-service/
├── card-application-service/
├── credit-rating-service/
├── card-activation-service/
├── card-management-service/
├── notification-service/
└── common/                          (shared DTOs, events, exceptions)
```

---

## Service 1 — API Gateway (Port 8080)

**Technology:** Spring Cloud Gateway

**Responsibilities:**
- Route all inbound HTTP requests to the correct downstream service
- Validate user JWTs by calling Auth Service before forwarding any protected external route
- Forward the original `Authorization: Bearer <user-token>` header and authenticated user context headers to downstream services
- Return `401 Unauthorized` if token is missing or invalid
- No business logic

**Routes:**
```
POST  /api/v1/applications        → card-application-service:8082
GET   /api/v1/credit-score        → credit-rating-service:8083
POST  /api/v1/cards/pin           → card-management-service:8085
POST  /api/v1/auth/login          → auth-service:8081   (no auth check)
POST  /api/v1/auth/register       → auth-service:8081   (no auth check)
```

**Filter chain:**
1. Extract `Authorization` header
2. For protected routes, call `GET auth-service:8081/api/v1/auth/validate-user` with the token
3. If `200 OK` → forward request downstream
4. If `401` → return 401 immediately, do not forward

---

## Service 2 — Auth Service (Port 8081)

On successful Gateway validation, the Gateway forwards the original bearer token plus `X-User-Id`, `X-User-Email`, and `X-User-Role` headers. API Gateway does not issue service tokens; service-to-service tokens are requested directly from Auth Service by internal services using client credentials.

**Technology:** Spring Security, JJWT library

**Database:** `auth_db`
**Tables:**
- `users (id, username, email, password_hash, role, created_at)`
- `service_clients (id, client_id, service_name, client_secret_hash, scopes, enabled, created_at)`

**Endpoints:**

```
POST /api/v1/auth/register
  Request:  { username, email, password }
  Response: { userId, username, email }
  Validation: email format, password min 8 chars, username non-empty

POST /api/v1/auth/login
  Request:  { email, password }
  Response: { token, expiresIn }
  Logic: verify password hash → issue signed JWT (expiry: 24h)

GET  /api/v1/auth/validate-user
  Header:   Authorization: Bearer <token>
  Response: 200 OK { userId, email, role, audience } | 401 Unauthorized
  Logic: verify signature + expiry + token type USER + audience zbank-api; return claims if valid

POST /api/v1/auth/service-token
  Request:  { clientId, clientSecret, scope, audience }
  Response: { token, tokenType: "Bearer", expiresIn }
  Logic: verify service client credentials + requested scope + allowed audience -> issue signed service JWT (expiry: 15m)

GET  /api/v1/auth/validate-service
  Header:   Authorization: Bearer <service-token>
  Query:    audience={expectedAudience}
  Response: 200 OK { clientId, serviceName, scopes, audience } | 401 Unauthorized
  Logic: verify signature + expiry + token type SERVICE + expected audience; return service claims if valid
```

**User JWT Claims:** `{ sub: userId, email, role, tokenType: "USER", aud: "zbank-api", iat, exp }`

**Service JWT Claims:** `{ sub: clientId, serviceName, scopes, tokenType: "SERVICE", aud: "<target-service>", iat, exp }`

**Audience rules:**
- User tokens must always use `aud = zbank-api`.
- Service tokens must use the receiving service name as the audience, for example `aud = credit-rating-service`.
- Auth Service must only issue service tokens for audiences allowed for that service client.
- Receivers must reject tokens whose `aud` does not exactly match their own service name.
- Audience mismatch -> `403 Forbidden`.

**Implementation note:** Do not infer audience from the caller. For service tokens, the caller must explicitly request the target audience, and Auth Service must verify that the requested audience is allowed for the authenticated service client before issuing the JWT.

**M2M Validations:**
- Disabled service client -> `401 Unauthorized`
- Invalid service credentials -> `401 Unauthorized`
- Requested scope not assigned to service client -> `403 Forbidden`
- Requested audience not assigned to service client -> `403 Forbidden`

**Seed service clients for local development:**
- `card-application-service`: scopes `credit-score:read`, audiences `credit-rating-service`
- `card-activation-service`: scopes `card-activated:publish`, audiences `zbank-broker`
- `card-management-service`: scopes `card-activated:consume`, audiences `zbank-broker`
- `notification-service`: scopes `card-activated:consume`, audiences `zbank-broker`

**Validations:**
- Duplicate email → `409 Conflict`
- Wrong password → `401 Unauthorized`
- Expired/invalid token → `401 Unauthorized`

---

## Service 3 — Card Application Service (Port 8082)

**Technology:** Spring Web, Spring Data JPA, RestTemplate / OpenFeign

**Database:** `app_db`
**Table:** `applications (id, customer_id, full_name, dob, address, employer, job_title, annual_salary, doc_type, doc_number, credit_score, status, created_at)`

**Endpoint:**

```
POST /api/v1/applications
  Header:   Authorization: Bearer <token>
  Request: {
    fullName, dateOfBirth, address,
    employerName, jobTitle, annualSalary,
    documentType, documentNumber
  }
  Response: 202 Accepted { applicationId, status: "PENDING", message: "Your application is under review" }
```

**Internal flow:**
1. Validate all mandatory fields and formats (see Validations section)
2. Extract `customerId` from JWT (via Auth Service validate call through Gateway)
3. Request an M2M service token from Auth Service using the `card-application-service` client credentials, scope `credit-score:read`, and audience `credit-rating-service`
4. Make a **synchronous REST call** to Credit Rating Service with `Authorization: Bearer <service-token>`:
   `GET credit-rating-service:8083/api/v1/credit-score?documentNumber={docNumber}&annualSalary={salary}&existingCards={count}`
5. Store application record with returned credit score and status `PENDING`
6. Publish async event `ApplicationSubmitted` to the message broker:
   ```json
   {
     "eventType": "APPLICATION_SUBMITTED",
     "producerService": "card-application-service",
     "correlationId": "request-correlation-id",
     "eventTimestamp": "2026-06-20T10:00:00Z",
     "applicationId": "uuid",
     "customerId": "uuid",
     "creditScore": 500,
     "documentNumber": "XYZ123",
     "customerEmail": "email",
     "customerName": "name"
   }
   ```
7. Return `202 Accepted`

**Validations:**
- `fullName`: mandatory, non-empty
- `dateOfBirth`: mandatory, valid date, customer must be 18+
- `annualSalary`: mandatory, must be > 0
- `documentType`: mandatory, enum `[PASSPORT, DRIVING_LICENSE, NATIONAL_ID]`
- `documentNumber`: mandatory, non-empty, alphanumeric
- `employerName`, `jobTitle`: mandatory, non-empty

---

## Service 4 — Credit Rating Service (Port 8083)

**Technology:** Spring Web, Spring Data JPA

**Database:** `credit_db`
**Table:** `credit_scores (id, document_number, score, source, created_at, updated_at)`

**Endpoint:**

```
GET /api/v1/credit-score?documentNumber=&annualSalary=&existingCards=
  Header:   Authorization: Bearer <service-token>
  Response: { documentNumber, score, source }
```

**M2M authorization:**
- Validate the service token by calling `GET auth-service:8081/api/v1/auth/validate-service?audience=credit-rating-service`
- Require `tokenType = SERVICE`
- Require scope `credit-score:read`
- Require `aud = credit-rating-service`
- Return `401 Unauthorized` for missing/invalid/expired service token
- Return `403 Forbidden` when the service token is valid but does not include the required scope or expected audience

**Scoring logic (implement as a functional-style pipeline using Java Streams / Optional):**

```
IF existing credit score found for documentNumber:
    RETURN that score (source = "EXISTING")
ELSE calculate:
    IF existingCards >= 2  → score = 300
    ELSE IF annualSalary > 200000 → score = 500
    ELSE IF annualSalary >= 50000 → score = 150
    ELSE                           → score = 50
    SAVE new score to credit_db (source = "CALCULATED")
    RETURN calculated score
```

**Validations:**
- `documentNumber`: mandatory
- `annualSalary`: must be a positive number
- `existingCards`: must be >= 0

**After calculation**, update the customer's credit score record in `credit_db` (acceptance criteria: "update the customer credit score").

---

## Service 5 — Card Activation Service (Port 8084)

**Technology:** Spring AMQP / Spring Kafka (async consumer), Spring Data JPA

**Database:** `activation_db`
**Table:** `card_activations (id, application_id, customer_id, document_number, credit_score, card_type, credit_limit, card_number, first_time_pin, status, created_at)`

**Trigger:** Consumes `ApplicationSubmitted` event from message broker

**Allocation rules:**

```
credit_score == 500 → card_type = PLATINUM, limit = 40000
credit_score == 300 → card_type = GOLD,     limit = 20000
credit_score == 150 → card_type = VISA,     limit = 10000
credit_score == 50  → status = DOCUMENTS_REQUIRED (request additional docs)
```

**On approval (score >= 150):**
1. Generate a unique 16-digit card number
2. Generate a random 4-digit first-time PIN
3. Save record with `status = ACTIVATED`
4. Publish async event `CardActivated` to the broker:
   ```json
   {
     "eventType": "CARD_ACTIVATED",
     "producerService": "card-activation-service",
     "correlationId": "request-correlation-id",
     "eventTimestamp": "2026-06-20T10:00:00Z",
     "applicationId": "uuid",
     "customerId": "uuid",
     "customerEmail": "email",
     "customerName": "name",
     "cardNumber": "4000123456789010",
     "firstTimePin": "7432",
     "cardType": "PLATINUM",
     "creditLimit": 40000
   }
   ```

**On rejection (score == 50):**
- Save with `status = DOCUMENTS_REQUIRED`
- Do NOT publish `CardActivated` event (out of scope per requirements)

**Out of scope:** The physical delivery of the card and PIN info to the customer — that is handled by Notification Service.

---

## Service 6 — Card Management Service (Port 8085)

**Technology:** Spring Web, Spring Data JPA, Spring AMQP / Kafka (async consumer)

**Database:** `cardmgmt_db`
**Tables:**
- `cards (id, customer_id, card_number, document_number, pin_hash, status, created_at)`
- `pin_audit (id, card_id, event, timestamp)` — audit entries

**Trigger 1 — Async consumer:** Consumes `CardActivated` event, creates a card record with `status = PENDING_PIN_SETUP`

**Trigger 2 — REST endpoint:**

```
POST /api/v1/cards/pin
  Header:   Authorization: Bearer <token>
  Request: {
    cardNumber,
    firstTimePin,
    documentId,
    newPin,
    confirmPin
  }
  Response: 200 OK { message: "PIN updated successfully. Card is now active." }
```

**PIN change logic:**
1. Look up card by `cardNumber`
2. Verify `documentId` matches the card's stored `documentNumber`
3. Verify `firstTimePin` matches the stored first-time PIN hash
4. Verify `newPin == confirmPin`
5. Verify `newPin` is exactly 4 digits
6. Update `pin_hash` with bcrypt hash of `newPin`
7. Set `status = ACTIVE`
8. Write audit entry: `PIN GENERATED` with timestamp

**Validations:**
- `cardNumber`: mandatory, 16-digit numeric string
- `firstTimePin`: mandatory, 4-digit numeric string
- `documentId`: mandatory
- `newPin` / `confirmPin`: mandatory, must match, exactly 4 digits
- Wrong first-time PIN → `400 Bad Request`
- Card not found → `404 Not Found`
- Card already active (PIN already set) → `409 Conflict`

---

## Service 7 — Notification Service (Port 8086)

**Technology:** Spring AMQP / Kafka (async consumer), Spring Mail (for email simulation)

**Database:** `notif_db`
**Table:** `notifications (id, customer_id, card_number, channel, status, sent_at, message)`

**Trigger:** Consumes `CardActivated` event from message broker

**On receiving event:**
1. Log notification intent
2. Send Email notification (use JavaMailSender or a mock logger for dev):
   ```
   Subject: Your Z Bank credit card is ready!
   Body: Dear {customerName}, your {cardType} card ending in {last4digits}
         has been activated with a credit limit of ${creditLimit}.
         Your first-time PIN is {firstTimePin}. Please login to change it.
   ```
3. Send SMS notification (mock/log for dev):
   ```
   Your Z Bank {cardType} card is activated. Limit: ${creditLimit}. Login to set your PIN.
   ```
4. Send Push notification (mock/log for dev):
   ```
   Card activated! Your {cardType} card is ready to use.
   ```
5. Save each notification attempt to `notif_db` with `status = SENT` or `FAILED`

**Note:** For this learning implementation, email/SMS/push can be simulated with `log.info(...)` statements — the architecture pattern is the learning goal, not actual delivery.

---

## Message Broker Configuration

**Use RabbitMQ** (easier to set up locally):

```
Exchange:  zbank.exchange (type: topic)

Routing Keys:
  zbank.application.submitted  → consumed by: Card Activation Service
  zbank.card.activated         → consumed by: Card Management Service, Notification Service

Queues:
  card-activation-queue        → binds to: zbank.application.submitted
  card-management-queue        → binds to: zbank.card.activated
  notification-queue           → binds to: zbank.card.activated
```

Both `card-management-queue` and `notification-queue` must bind to the same routing key so both services receive the same `CardActivated` event independently (fan-out pattern).

**Broker authentication and event identity:**
- RabbitMQ username/password protects broker connections for publishers and consumers.
- Each service must use its own configurable broker username/password in production.
- Event payloads must include `producerService`, `correlationId`, and `eventTimestamp` for auditability and cross-service tracing.
- Consumers must validate the expected `eventType` and ignore or dead-letter malformed events.

---

## Cross-Cutting Requirements (from Validations & Review slide)

### 0. Authentication & Authorization
- External client requests use user JWTs issued by Auth Service.
- API Gateway validates user JWTs with `GET /api/v1/auth/validate-user` before forwarding protected routes.
- Internal synchronous REST calls use service JWTs issued by `POST /api/v1/auth/service-token`.
- Internal REST receivers validate service JWTs with `GET /api/v1/auth/validate-service` and enforce required scopes.
- User JWTs must include `aud = zbank-api`.
- Service JWTs must include `aud = <target-service>`.
- Receivers must reject JWTs when the `aud` claim does not match the expected audience.
- User JWTs must not be accepted as service JWTs, and service JWTs must not be accepted as user JWTs.
- Service client secrets must be stored hashed with BCrypt, never as plaintext.
- Service tokens must be short-lived, defaulting to 15 minutes.
- RabbitMQ username/password protects event transport; event payload metadata provides producer identity and traceability.

### 1. Mandatory & Format Validations
Use Bean Validation (`@Valid`, `@NotBlank`, `@NotNull`, `@Pattern`, `@Min`, `@Email`) on all request DTOs. Return `400 Bad Request` with a structured error body on validation failure:
```json
{
  "timestamp": "2025-01-01T10:00:00",
  "status": 400,
  "error": "Validation Failed",
  "errors": [
    { "field": "annualSalary", "message": "must be greater than 0" }
  ]
}
```

### 2. Business Validations
Each service must validate business rules beyond field format:
- Age >= 18 (Card Application)
- Card must exist before PIN change (Card Management)
- Duplicate applications for the same `documentNumber` (Card Application — return `409 Conflict`)
- Score boundary values strictly matched (Credit Rating)

### 3. Functional Programming Style (JDK 8+)
- Use `Optional<T>` for all nullable lookups — never return `null`
- Use `Stream` and lambdas for collection processing and scoring logic
- Use method references where possible
- Credit rating scoring logic must be implemented as a functional chain (no if-else ladders)

Example:
```java
private int calculateScore(double salary, int existingCards) {
    return Stream.<Supplier<Optional<Integer>>>of(
        () -> existingCards >= 2 ? Optional.of(300) : Optional.empty(),
        () -> salary > 200000    ? Optional.of(500) : Optional.empty(),
        () -> salary >= 50000    ? Optional.of(150) : Optional.empty(),
        () -> Optional.of(50)
    )
    .map(Supplier::get)
    .filter(Optional::isPresent)
    .map(Optional::get)
    .findFirst()
    .orElse(50);
}
```

### 4. Unit Tests
Write JUnit 5 + Mockito tests for:
- All service layer methods (mock repositories)
- Credit score calculation covering all 4 branches
- PIN change validation — all happy paths and failure paths
- Notification event consumer

Use `@SpringBootTest` for integration tests on at least one full flow per service.

### 5. Error Handling
Implement a global `@RestControllerAdvice` in each service:
```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(MethodArgumentNotValidException.class) // 400
    @ExceptionHandler(ResourceNotFoundException.class)       // 404
    @ExceptionHandler(DuplicateResourceException.class)      // 409
    @ExceptionHandler(BusinessValidationException.class)     // 422
    @ExceptionHandler(Exception.class)                       // 500
}
```
Never expose stack traces in API responses.

---

## Events Reference

### ApplicationSubmitted (published by Card Application Service)
```json
{
  "eventType": "APPLICATION_SUBMITTED",
  "producerService": "card-application-service",
  "correlationId": "request-correlation-id",
  "eventTimestamp": "2026-06-20T10:00:00Z",
  "applicationId": "550e8400-e29b-41d4-a716-446655440000",
  "customerId": "user-uuid",
  "customerEmail": "john@example.com",
  "customerName": "John Doe",
  "creditScore": 500,
  "documentNumber": "PASS123456"
}
```

### CardActivated (published by Card Activation Service)
```json
{
  "eventType": "CARD_ACTIVATED",
  "producerService": "card-activation-service",
  "correlationId": "request-correlation-id",
  "eventTimestamp": "2026-06-20T10:00:00Z",
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

---

## Complete User Journey (End-to-End Flow)

```
1. POST /api/v1/auth/register           → Auth Service issues userId
2. POST /api/v1/auth/login              → Auth Service issues JWT
3. POST /api/v1/applications            → Card Application collects data
   ↓ sync REST call
   GET  /api/v1/credit-score            → Credit Rating returns score (e.g. 500)
   ↓ save application, publish async event
   [ApplicationSubmitted → broker]
4.                                      → Card Activation Service consumes event
   Assigns PLATINUM / 40000 limit
   Generates card number + first-time PIN
   Saves activation record
   [CardActivated → broker]             (fan-out to 2 consumers)
5a.                                     → Card Management Service consumes CardActivated
   Creates card record with PENDING_PIN_SETUP status
5b.                                     → Notification Service consumes CardActivated
   Sends Email + SMS + Push to customer
6. POST /api/v1/cards/pin               → Card Management validates + sets PIN
   Returns 200 OK — Card is now ACTIVE
```

---

## System Authentication Journey

```
1. User registers through API Gateway -> Auth Service stores user with BCrypt password hash.
2. User logs in through API Gateway -> Auth Service returns a USER JWT valid for 24 hours with aud=zbank-api.
3. User calls a protected route with Authorization: Bearer <user-token>.
4. API Gateway calls Auth Service /api/v1/auth/validate-user.
5. Auth Service validates tokenType USER, aud=zbank-api, signature, and expiry, then returns user claims.
6. API Gateway forwards the request to the target service with the original user token plus X-User-* context headers.
7. Card Application needs Credit Rating, so it calls Auth Service /api/v1/auth/service-token using card-application-service client credentials, scope credit-score:read, and audience credit-rating-service.
8. Auth Service validates the service client secret, scope, and allowed audience, then returns a short-lived SERVICE JWT with aud=credit-rating-service.
9. Card Application calls Credit Rating with Authorization: Bearer <service-token>.
10. Credit Rating calls Auth Service /api/v1/auth/validate-service?audience=credit-rating-service, requires tokenType SERVICE, aud=credit-rating-service, and scope credit-score:read, then returns the credit score.
11. Async events are sent through RabbitMQ using broker credentials; event metadata carries producerService, correlationId, and eventTimestamp.
```

---

## Docker Compose (for local dev)

Provide a `docker-compose.yml` at the project root:
```yaml
services:
  rabbitmq:
    image: rabbitmq:3-management
    ports: ["5672:5672", "15672:15672"]

  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: "ZBank@12345"
      MSSQL_PID: "Developer"
    ports: ["1433:1433"]
```

Each service's `application.yml` should use Microsoft SQL Server connection settings. Local development should target the Docker Compose SQL Server instance, and production settings should point to the appropriate managed or hosted SQL Server instance.

---

## Deliverables Checklist

- [ ] Parent `pom.xml` with all 7 modules declared
- [ ] `common` module with shared event POJOs, DTOs, and custom exceptions
- [ ] All 7 Spring Boot services, each runnable independently on their assigned port
- [ ] RabbitMQ configuration class in each consuming service
- [ ] Global exception handler in every service
- [ ] Unit tests for all service-layer classes
- [ ] `docker-compose.yml` for RabbitMQ and Microsoft SQL Server
- [ ] `README.md` with startup instructions and sample cURL commands for the full end-to-end flow
