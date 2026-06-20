# Auth Service Implementation TODO

This TODO is ordered for small, reviewable implementation steps. It follows the current ZBank prompt: Microsoft SQL Server, user JWTs, M2M service JWTs, audience checks, scope checks, and network-based validation through Auth Service.

## 1. Contract And Setup

- [ ] Confirm Auth Service endpoints from `ZBank_Implementation_Prompt.md`.
- [ ] Confirm user token audience is `zbank-api`.
- [ ] Confirm current M2M runtime path is `card-application-service -> credit-rating-service`.
- [ ] Confirm service token audience for that path is `credit-rating-service`.
- [ ] Create packages: `config`, `controller`, `dto`, `entity`, `exception`, `repository`, `security`, `service`.

## 2. Domain Model

- [ ] Create `Role` enum.
- [ ] Create `TokenType` enum.
- [ ] Create `User` entity.
- [ ] Add fields: `id`, `username`, `email`, `passwordHash`, `role`, `createdAt`.
- [ ] Add unique constraint/index for `email`.
- [ ] Create `ServiceClient` entity.
- [ ] Add fields: `id`, `clientId`, `serviceName`, `clientSecretHash`, `scopes`, `audiences`, `enabled`, `createdAt`.
- [ ] Add unique constraint/index for `clientId`.

## 3. Repositories

- [ ] Create `UserRepository`.
- [ ] Add `Optional<User> findByEmail(String email)`.
- [ ] Add `boolean existsByEmail(String email)`.
- [ ] Create `ServiceClientRepository`.
- [ ] Add `Optional<ServiceClient> findByClientId(String clientId)`.

## 4. DTOs

- [ ] Create `RegisterRequest`.
- [ ] Add validation for username, email, and password length.
- [ ] Create `LoginRequest`.
- [ ] Add validation for email and password.
- [ ] Create `ServiceTokenRequest`.
- [ ] Add validation for `clientId`, `clientSecret`, `scope`, and `audience`.
- [ ] Create `RegisterResponse`.
- [ ] Create `LoginResponse`.
- [ ] Create `ServiceTokenResponse`.
- [ ] Create `UserValidationResponse`.
- [ ] Create `ServiceValidationResponse`.
- [ ] Ensure no response exposes password hash or client secret hash.

## 5. Exceptions And Error Handling

- [ ] Create `DuplicateResourceException`.
- [ ] Create `InvalidCredentialsException`.
- [ ] Create `InvalidTokenException`.
- [ ] Create `ForbiddenException`.
- [ ] Create structured error DTOs: `ApiError`, `FieldErrorDetail`.
- [ ] Create `GlobalExceptionHandler`.
- [ ] Map validation failures to `400`.
- [ ] Map invalid credentials/tokens to `401`.
- [ ] Map forbidden scope/audience failures to `403`.
- [ ] Map duplicate email to `409`.
- [ ] Ensure stack traces are never returned in API responses.

## 6. Security Configuration

- [ ] Create `SecurityConfig`.
- [ ] Disable CSRF for stateless REST APIs.
- [ ] Set session management to stateless.
- [ ] Permit `/api/v1/auth/register`.
- [ ] Permit `/api/v1/auth/login`.
- [ ] Permit `/api/v1/auth/validate-user`.
- [ ] Permit `/api/v1/auth/service-token`.
- [ ] Permit `/api/v1/auth/validate-service`.
- [ ] Expose a `BCryptPasswordEncoder` bean.

## 7. JWT Configuration

- [ ] Create JWT properties class.
- [ ] Configure JWT secret.
- [ ] Configure user token expiry: 24 hours.
- [ ] Configure service token expiry: 15 minutes.
- [ ] Configure user audience: `zbank-api`.
- [ ] Update `auth-service/src/main/resources/application.yml`.

## 8. JWT Service

- [ ] Implement user JWT generation.
- [ ] Include claims: `sub`, `email`, `role`, `tokenType=USER`, `aud=zbank-api`, `iat`, `exp`.
- [ ] Implement service JWT generation.
- [ ] Include claims: `sub`, `serviceName`, `scopes`, `tokenType=SERVICE`, `aud=<target-service>`, `iat`, `exp`.
- [ ] Implement JWT parsing.
- [ ] Validate signature.
- [ ] Validate expiry.
- [ ] Validate token type.
- [ ] Validate audience.
- [ ] Return typed validation results without returning `null`.

## 9. Auth Service Logic

- [ ] Implement `register`.
- [ ] Reject duplicate email.
- [ ] Hash user password with BCrypt.
- [ ] Save user with default role.
- [ ] Implement `login`.
- [ ] Return the same `401` style response for unknown email and wrong password.
- [ ] Implement `validateUserToken`.
- [ ] Require `tokenType=USER`.
- [ ] Require `aud=zbank-api`.
- [ ] Implement `issueServiceToken`.
- [ ] Validate service client exists and is enabled.
- [ ] Validate client secret with BCrypt.
- [ ] Validate requested scope is allowed.
- [ ] Validate requested audience is allowed.
- [ ] Implement `validateServiceToken`.
- [ ] Require `tokenType=SERVICE`.
- [ ] Require `aud` equals the expected audience query parameter.

## 10. Controller

- [ ] Create `AuthController`.
- [ ] Implement `POST /api/v1/auth/register`.
- [ ] Implement `POST /api/v1/auth/login`.
- [ ] Implement `GET /api/v1/auth/validate-user`.
- [ ] Implement `POST /api/v1/auth/service-token`.
- [ ] Implement `GET /api/v1/auth/validate-service?audience=...`.
- [ ] Extract bearer tokens consistently from `Authorization` headers.

## 11. Local Seed Data

- [ ] Add local seed support for service clients.
- [ ] Seed `card-application-service`.
- [ ] Allow scope `credit-score:read`.
- [ ] Allow audience `credit-rating-service`.
- [ ] Optionally seed async-related clients for future use.
- [ ] Store seed client secrets as BCrypt hashes.
- [ ] Keep local seed secrets configurable, not hardcoded in service logic.

## 12. Unit Tests

- [ ] Test user registration success.
- [ ] Test duplicate email returns `409`.
- [ ] Test password is BCrypt-hashed before save.
- [ ] Test login success.
- [ ] Test unknown email returns `401`.
- [ ] Test wrong password returns `401`.
- [ ] Test user JWT validation success.
- [ ] Test user JWT rejects service token.
- [ ] Test user JWT audience mismatch fails.
- [ ] Test service-token issuance success.
- [ ] Test disabled service client fails.
- [ ] Test invalid service secret fails.
- [ ] Test invalid service scope fails.
- [ ] Test invalid service audience fails.
- [ ] Test service JWT validation success.
- [ ] Test service JWT rejects user token.
- [ ] Test service JWT audience mismatch fails.

## 13. Controller Tests

- [ ] Test register request validation.
- [ ] Test login request validation.
- [ ] Test service-token request validation.
- [ ] Test missing bearer token for `validate-user`.
- [ ] Test missing bearer token for `validate-service`.
- [ ] Test missing audience query parameter for `validate-service`.
- [ ] Test structured error response shape.

## 14. Manual Verification

- [ ] Run MSSQL Server using Docker Compose.
- [ ] Run Auth Service on port `8081`.
- [ ] Verify register with curl.
- [ ] Verify duplicate register with curl.
- [ ] Verify login with curl.
- [ ] Verify `/api/v1/auth/validate-user` with a valid user JWT.
- [ ] Verify `/api/v1/auth/validate-user` rejects an invalid audience.
- [ ] Verify `/api/v1/auth/service-token` for `card-application-service`.
- [ ] Verify `/api/v1/auth/validate-service?audience=credit-rating-service`.
- [ ] Verify `/api/v1/auth/validate-service` rejects audience mismatch.

## 15. Documentation

- [ ] Add Auth Service curl examples to README.
- [ ] Document local service client credentials for development.
- [ ] Document expected JWT claims.
- [ ] Document audience rules.
- [ ] Document current M2M path: `card-application-service -> credit-rating-service`.
