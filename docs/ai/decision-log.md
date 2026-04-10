# Decision Log

Major technical decisions, alternatives considered, rationale, and implications. Every agent should consult this to understand why things are the way they are before proposing changes.

## Format

Each entry follows this structure:

```
### [DATE] Decision title
**Decision**: What was decided.
**Alternatives considered**: What else was evaluated.
**Rationale**: Why this option was chosen.
**Tradeoffs**: What was given up or deferred.
**Implications**: What this means for future work.
```

---

### [2026-04-10] E2E encryption with deterministic key derivation from password
**Decision**: Derive the AES-256-GCM encryption key from the user's password + a server-stored salt using PBKDF2-SHA256 (600,000 iterations). No key wrapping or key escrow.
**Alternatives considered**: (1) Stored wrapped key — server stores an encrypted version of the key, unwrapped by a password-derived key. (2) Device-specific keys with key exchange.
**Rationale**: For a clipboard tool with ephemeral data (max 5 entries, 30-day TTL), deterministic derivation from password is the simplest correct approach. Same password + same salt = same key on any device. No key synchronization needed.
**Tradeoffs**: Password change invalidates all existing encrypted entries (server deletes them). No way to recover entries if password is lost. These are acceptable because clipboard data is ephemeral.
**Implications**: Any future "password change" feature must delete all clipboard entries. Any future "export history" feature must happen client-side (server can't decrypt).

### [2026-04-10] Single ECS task with in-memory WebSocket state
**Decision**: Run 1 ECS Fargate task. WebSocket connections tracked in an in-memory `Map<string, Set<WebSocket>>`.
**Alternatives considered**: (1) Multiple tasks with Redis pub/sub for cross-task messaging. (2) API Gateway WebSocket API (managed, scales automatically).
**Rationale**: For initial launch, 1 task is simpler and sufficient. No need for Redis/ElastiCache infrastructure. The in-memory map is fast and correct when there's a single process.
**Tradeoffs**: Cannot scale horizontally without adding a messaging layer. Single point of failure (mitigated by ECS auto-restart on failure).
**Implications**: `desired_count` in `terraform/ecs.tf` must stay at 1 until a cross-task broadcast mechanism is implemented. If scaling is needed, evaluate: DynamoDB Streams + Lambda fan-out, SNS, or Redis pub/sub.

### [2026-04-10] DynamoDB over PostgreSQL (RDS)
**Decision**: Use DynamoDB with on-demand billing for both users and clipboard data.
**Alternatives considered**: (1) PostgreSQL on RDS — relational, strong consistency, familiar. (2) Aurora Serverless — scales to zero but more expensive.
**Rationale**: The access patterns are simple key-value lookups and single-partition queries. DynamoDB on-demand has no idle cost, scales automatically, and requires zero database management. The data model (user profiles + clipboard entries per user) maps naturally to partition-key-scoped queries.
**Tradeoffs**: No ad-hoc SQL queries. No joins. Adding complex query patterns later requires GSIs or application-side logic. Schema changes require more thought than ALTER TABLE.
**Implications**: New features must work within DynamoDB's access patterns. If a feature requires cross-user queries or complex aggregations, it will need a GSI or a separate data store.

### [2026-04-10] api.copypasto.com subdomain for the API
**Decision**: Serve the API from `api.copypasto.com`. Reserve the apex `copypasto.com` for a future marketing website.
**Alternatives considered**: (1) Keep API on apex domain. (2) Use a path prefix on the apex domain.
**Rationale**: Separating the API to a subdomain allows the marketing site to be hosted independently (e.g., on Vercel, Netlify, or S3+CloudFront) without sharing the ALB or ECS infrastructure.
**Tradeoffs**: Client must use the `api.` subdomain. Separate ACM certificate required.
**Implications**: The ACM cert in `terraform/acm.tf` covers `api.copypasto.com` only. If adding more subdomains (e.g., `ws.copypasto.com`), new certs or a wildcard cert will be needed. The client `Constants.swift` must always point to the `api.` subdomain.

### [2026-04-10] Fastify over Express
**Decision**: Use Fastify 5 as the HTTP/WebSocket framework.
**Alternatives considered**: Express + ws library.
**Rationale**: First-class TypeScript support, native WebSocket via `@fastify/websocket`, built-in JSON schema validation support, plugin architecture for clean route organization, better performance characteristics.
**Tradeoffs**: Smaller ecosystem than Express. Some middleware patterns differ. Fastify's `preHandler` hook model is different from Express middleware chaining.
**Implications**: Use Fastify's plugin system for new route groups. Use `preHandler` for auth middleware (not Express-style `app.use`). WebSocket handling uses the `@fastify/websocket` API, not raw `ws`.

### [2026-04-10] Keychain with data protection keychain flag
**Decision**: Use `kSecUseDataProtectionKeychain: true` in all Keychain operations.
**Alternatives considered**: Default Keychain without data protection flag.
**Rationale**: The data protection keychain provides better security isolation on macOS. Items are encrypted with the device's secure enclave and protected by the user's login credentials.
**Tradeoffs**: Slightly stricter access requirements. Items may not be accessible in some edge cases (e.g., before first unlock after reboot, handled by `kSecAttrAccessibleAfterFirstUnlock`).
**Implications**: All `KeychainService` methods must include `kSecUseDataProtectionKeychain: true` in their queries. Omitting it from any operation (save, load, delete) will cause items to be invisible to operations that include it.
