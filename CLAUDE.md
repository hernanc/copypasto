# Copypasto

Cross-computer clipboard sync with E2E encryption. macOS menu bar app + server API + AWS infrastructure.

## Repo Layout

```
client/          Swift/SwiftUI macOS menu bar app (macOS 14+, Xcode 16+, Swift 5.10)
server/          TypeScript REST + WebSocket API (Fastify 5, Node 20, strict TS)
terraform/       AWS infra (ECS Fargate, DynamoDB, ALB, ACM, Route53, us-east-1)
deploy.sh        Build linux/amd64 Docker image, push ECR, trigger ECS deployment
```

## Commands

```sh
cd server && npm run dev                # local dev (tsx watch)
cd server && npm run build              # compile TypeScript → dist/
cd client && ./run.sh                   # xcodebuild + launch menu bar app
cd client && xcodegen generate          # regenerate .xcodeproj from project.yml
./deploy.sh                             # full server deploy to ECS
cd terraform && terraform plan          # preview infra changes
cd terraform && terraform apply         # apply infra changes
aws logs tail /ecs/copypasto-prod-server --follow --region us-east-1
```

## Domain

- **API**: `api.copypasto.com` (ALB → ECS Fargate)
- **Apex**: `copypasto.com` reserved for marketing website — never point the API here

## Critical Architecture Rules

### E2E Encryption Invariant
The server NEVER sees plaintext clipboard content. All encryption/decryption happens client-side.
- Client derives AES-256-GCM key from password + server-stored salt via PBKDF2-SHA256 (600,000 iterations)
- Server stores only opaque `ciphertext` (base64) and `iv` (base64) — treat these as black boxes
- If you add any server-side feature that touches clipboard content, you are breaking the security model

### Auth Model
- JWT access tokens (15 min) + single-use refresh tokens (30 days, rotated on each use)
- Refresh token hash (SHA-256) stored in DynamoDB — never the raw token
- JWT secrets live in AWS SSM Parameter Store (SecureString), injected into ECS via task definition
- Client stores tokens in macOS Keychain, encryption key in memory only (never persisted)

### Multi-Tenancy
- Every DynamoDB query MUST be scoped to `USER#<userId>` partition key
- WebSocket broadcasts go only to connections of the SAME user
- Never expose one user's data to another — there is no admin/cross-user access path

### DynamoDB Tables

**copypasto-users** — PK: `USER#<uuid>`, SK: `PROFILE`, GSI: `email-index` (on `email`)
**copypasto-clipboard** — PK: `USER#<uuid>`, SK: `CLIP#<iso8601>#<ulid>`, TTL: 30 days, max 5 entries per user

### Clipboard Sync Flow
1. ClipboardMonitor detects NSPasteboard change (0.5s polling)
2. Client encrypts plaintext → `{ ciphertext, iv }` via AES-256-GCM
3. Client sends `clipboard:push` over WebSocket
4. Server stores encrypted entry in DynamoDB, prunes to 5 entries
5. Server sends `clipboard:push:ack` to sender, `clipboard:new` to other sessions of same user
6. Receiving client decrypts and writes to local clipboard
7. ClipboardMonitor skips the change it just wrote (loop prevention via `ignoreNextChange` flag)

## Conventions

### Server (TypeScript)
- **Validation**: Zod schemas at route entry points. Always `safeParse`, never `parse`.
- **Errors**: `reply.code(N).send({ error: "message" })` — never throw from route handlers.
- **Imports**: Named imports, `.js` extension on relative paths (NodeNext ESM resolution).
- **Logging**: Structured via Fastify logger — `app.log.info({ userId, entryId }, "message")`. Never log tokens, passwords, ciphertext, or plaintext.
- **Services**: Pure functions exported from `src/services/*.service.ts`. No classes.
- **DB access**: Only through `src/services/` — routes never import DynamoDB directly.
- **Auth**: `authMiddleware` preHandler for protected routes. WebSocket auth inline in handler via query param.
- **Config**: All env vars validated in `src/config.ts` via Zod. Fail-fast on missing vars.
- **Rate limiting**: Per-route config via `@fastify/rate-limit`. WebSocket rate limiting per-connection in handler.

### Client (Swift)
- **Services**: Classes/actors in `Services/`, ObservableObject for UI-bound state.
- **Views**: SwiftUI views in `Views/`, no business logic — delegate to services.
- **Crypto**: `CryptoService` for all encryption. Uses CryptoKit (AES-GCM) + CommonCrypto (PBKDF2).
- **Keychain**: All token/secret storage through `KeychainService` — never UserDefaults.
- **Network**: `NetworkService` (actor) handles REST + automatic 401 retry with token refresh.
- **Constants**: All config values in `Utilities/Constants.swift` — no magic strings in service code.

### Terraform
- **File organization**: One resource type per file (ecs.tf, dynamodb.tf, alb.tf, etc.).
- **Naming**: `copypasto-${var.environment}-<resource>` for all resource names.
- **Tagging**: Default tags (Project, Environment, ManagedBy) via provider block. Resource-specific `Name` tag on each resource.
- **IAM**: Least-privilege. Execution role for ECR/logs/SSM. Task role for DynamoDB only.
- **No hardcoded values**: Everything through variables with defaults in `variables.tf`.
- **State**: S3 backend (`copypasto-terraform-state`), encrypted, versioned.

## Security Boundaries — Do Not Weaken

1. Clipboard content encrypted client-side before transmission — server must never decrypt
2. Refresh tokens are single-use with hash rotation — never reuse or skip rotation
3. bcrypt (12 rounds) for password storage — never downgrade
4. PBKDF2 with 600,000 iterations for key derivation — never lower
5. TLS 1.3 enforced on ALB — never allow weaker TLS policies
6. ECS tasks run in private subnets — never expose directly to internet
7. IAM task role scoped to `copypasto-*` DynamoDB tables — never use wildcard resource ARNs
8. JWT secrets in SSM SecureString — never in env vars, code, or terraform.tfvars
9. Docker runs as non-root user — never switch to root
10. Rate limiting on all endpoints — never remove or significantly increase limits
