# Copypasto

Copypasto is a cross-computer clipboard sharing service. Copy text on one Mac, paste it on another — instantly, with end-to-end encryption.

## Architecture

```
┌──────────────┐         wss://api.copypasto.com/ws         ┌──────────────┐
│   Mac App    │◄──────────────────────────────────────────►│   Fastify    │
│  (Swift)     │         https://api.copypasto.com/api       │  (Node.js)   │
│              │◄──────────────────────────────────────────►│              │
└──────────────┘                                             └──────┬───────┘
                                                                    │
       Clipboard text is encrypted                                  │
       on-device before sending.                           ┌────────▼───────┐
       The server only stores                              │   DynamoDB     │
       opaque ciphertext.                                  │  (us-east-1)   │
                                                           └────────────────┘
```

**Components:**

| Directory | Description |
|-----------|-------------|
| `client/` | macOS menu bar app (Swift / SwiftUI) |
| `server/` | REST + WebSocket API (TypeScript / Fastify) |
| `terraform/` | AWS infrastructure as code |

## Quick Start

### Prerequisites

- macOS 14+ with Xcode 16+
- Node.js 20+
- Docker with buildx
- Terraform 1.5+
- AWS CLI configured with credentials

### Run the Client

```sh
cd client && ./run.sh
```

This builds the Xcode project and launches the menu bar app.

### Run the Server Locally

```sh
cd server
cp .env.example .env   # Edit with your values
npm install
npm run dev
```

### Deploy

```sh
./deploy.sh
```

Builds a `linux/amd64` Docker image, pushes to ECR, and triggers an ECS rolling deployment.

### Tail Server Logs

```sh
aws logs tail /ecs/copypasto-prod-server --follow --region us-east-1
```

## End-to-End Encryption

The server never sees plaintext clipboard content. The encryption scheme works as follows:

1. **Signup**: The server generates a random 32-byte `encryptionSalt` and stores it alongside the user record.
2. **Login**: The server returns the `encryptionSalt` to the client.
3. **Key derivation**: The client derives a 256-bit key using PBKDF2-SHA256 (600,000 iterations) from the user's password and the salt.
4. **Encrypt**: Each clipboard entry is encrypted with AES-256-GCM using a fresh random 12-byte IV. The client sends `{ ciphertext, iv }` to the server.
5. **Decrypt**: On receiving a clipboard update, the client decrypts using the same derived key.
6. **Multi-device**: Because the key is derived deterministically from password + salt, any device with the correct password derives the same key.

**Password change**: All existing clipboard entries become undecryptable. The server deletes them on password change. This is acceptable since clipboard data is ephemeral.

## API Reference

Base URL: `https://api.copypasto.com`

### Authentication

#### `POST /api/auth/signup`

Create a new account.

```json
// Request
{ "email": "user@example.com", "password": "securepassword" }

// Response 201
{
  "userId": "uuid",
  "accessToken": "jwt",
  "refreshToken": "jwt",
  "encryptionSalt": "base64"
}
```

| Status | Meaning |
|--------|---------|
| 201 | Account created |
| 400 | Invalid input (email format, password < 8 chars) |
| 409 | Email already registered |

#### `POST /api/auth/login`

```json
// Request
{ "email": "user@example.com", "password": "securepassword" }

// Response 200
{
  "userId": "uuid",
  "accessToken": "jwt",
  "refreshToken": "jwt",
  "encryptionSalt": "base64"
}
```

| Status | Meaning |
|--------|---------|
| 200 | Login successful |
| 400 | Invalid input |
| 401 | Invalid email or password |

#### `POST /api/auth/refresh`

Rotate tokens. Refresh tokens are single-use — each call invalidates the previous token.

```json
// Request
{ "refreshToken": "jwt" }

// Response 200
{ "accessToken": "jwt", "refreshToken": "jwt" }
```

### Clipboard

#### `GET /api/clipboard`

Returns the user's last 5 encrypted clipboard entries (newest first).

Requires `Authorization: Bearer <accessToken>` header.

```json
// Response 200
{
  "items": [
    {
      "id": "ulid",
      "ciphertext": "base64",
      "iv": "base64",
      "contentLength": 42,
      "createdAt": "2026-04-10T19:00:00.000Z"
    }
  ]
}
```

### Health

#### `GET /api/health`

```json
{ "status": "ok", "timestamp": "2026-04-10T19:00:00.000Z" }
```

### Rate Limits

| Endpoint | Limit |
|----------|-------|
| `/api/auth/*` | 5 requests/minute |
| `/api/clipboard` | 30 requests/minute |
| WebSocket messages | 60 messages/minute per connection |

## WebSocket Protocol

Connect to `wss://api.copypasto.com/ws?token=<accessToken>`

### Client → Server

**Push clipboard entry:**
```json
{
  "type": "clipboard:push",
  "id": "client-generated-ulid",
  "payload": {
    "ciphertext": "base64",
    "iv": "base64",
    "contentLength": 42
  }
}
```

**Keepalive:**
```json
{ "type": "ping" }
```

### Server → Client

**New clipboard entry** (broadcast to all other sessions of the same user):
```json
{
  "type": "clipboard:new",
  "id": "ulid",
  "payload": { "ciphertext": "base64", "iv": "base64", "contentLength": 42 },
  "createdAt": "2026-04-10T19:00:00.000Z"
}
```

**Acknowledgements and errors:**
```json
{ "type": "clipboard:push:ack", "id": "ulid" }
{ "type": "clipboard:push:error", "id": "ulid", "error": "Payload too large" }
{ "type": "pong" }
{ "type": "error", "code": "AUTH_EXPIRED", "message": "Token expired" }
```

### Connection Behavior

- Client sends a `ping` every 30 seconds to keep the connection alive (ALB idle timeout is 1 hour).
- On disconnect, the client reconnects with exponential backoff: 1s, 2s, 4s, 8s, ... up to 30s max.
- On `AUTH_EXPIRED`, the client refreshes the access token and reconnects.

## Client

The macOS client is a menu bar app — it has no dock icon and no main window.

### Features

- **Login / Signup** form in the menu bar popover
- **Clipboard history** showing the last 5 entries with truncated previews
- Click any entry to copy its decrypted content to the system clipboard
- **Real-time sync** via WebSocket — clipboard changes appear on other devices within milliseconds
- **Clipboard monitoring** polls `NSPasteboard` every 0.5 seconds for changes
- **Loop prevention**: when writing a remote clipboard update locally, the monitor skips the resulting change to avoid echoing it back to the server
- Tokens stored in macOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`)
- Encryption key derived in memory from the user's password — never persisted to disk

### Limits

- Text only (no images, files, or rich content)
- 1 MB maximum per clipboard entry
- 5 entries retained per user

### Building

Requires Xcode 16+ and macOS 14+ SDK. The Xcode project is generated from `client/project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd client
xcodegen generate      # regenerate .xcodeproj from project.yml
./run.sh               # build and launch
```

## Server

TypeScript API running on Fastify 5 with `@fastify/websocket`.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3000` | Server listen port |
| `JWT_SECRET` | — | Signing key for access tokens (min 16 chars) |
| `JWT_REFRESH_SECRET` | — | Signing key for refresh tokens (min 16 chars) |
| `AWS_REGION` | `us-east-1` | AWS region for DynamoDB |
| `DYNAMODB_USERS_TABLE` | `copypasto-users` | Users table name |
| `DYNAMODB_CLIPBOARD_TABLE` | `copypasto-clipboard` | Clipboard table name |

### Token Strategy

| Token | Lifetime | Storage (client) |
|-------|----------|------------------|
| Access token | 15 minutes | In-memory only |
| Refresh token | 30 days | macOS Keychain |

Refresh tokens are single-use. Each refresh rotates the token and invalidates the previous one (stored as a SHA-256 hash in DynamoDB).

### Docker

Multi-stage build on `node:20-alpine`. Runs as non-root user `appuser`.

```sh
docker buildx build --platform linux/amd64 -t copypasto-server server/
```

## Infrastructure

All AWS resources are managed with Terraform. State is stored in S3 (`copypasto-terraform-state`).

### Resources

| Resource | Details |
|----------|---------|
| **VPC** | 10.0.0.0/16, 2 public subnets (ALB), 2 private subnets (ECS), 1 NAT Gateway |
| **ALB** | HTTPS with TLS 1.3, HTTP→HTTPS redirect, 1-hour idle timeout for WebSocket |
| **ECS Fargate** | 256 CPU / 512 MiB, 1 task, private subnet, CloudWatch logging |
| **DynamoDB** | 2 tables (users + clipboard), on-demand billing, TTL on clipboard entries |
| **ACM** | Certificate for `api.copypasto.com`, DNS validation via Route53 |
| **Route53** | A record alias `api.copypasto.com` → ALB |
| **ECR** | `copypasto-server` repo, keep last 10 images, scan on push |
| **SSM** | SecureString parameters for JWT secrets |
| **CloudWatch** | Log group `/ecs/copypasto-prod-server`, 30-day retention |

### DynamoDB Schema

**copypasto-users**

| Key | Format | Example |
|-----|--------|---------|
| `pk` (hash) | `USER#<uuid>` | `USER#a1b2c3d4-...` |
| `sk` (range) | `PROFILE` | `PROFILE` |

Attributes: `email`, `passwordHash`, `encryptionSalt`, `refreshTokenHash`, `createdAt`, `updatedAt`

GSI `email-index`: hash key = `email`, projection = ALL

**copypasto-clipboard**

| Key | Format | Example |
|-----|--------|---------|
| `pk` (hash) | `USER#<uuid>` | `USER#a1b2c3d4-...` |
| `sk` (range) | `CLIP#<iso8601>#<ulid>` | `CLIP#2026-04-10T19:00:00Z#01HXY...` |

Attributes: `ciphertext`, `iv`, `contentLength`, `createdAt`, `ttl`

TTL: 30 days from creation. Entries beyond the 5-entry limit are pruned on insert.

### Terraform Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `domain_name` | `copypasto.com` | Base domain (API runs on `api.` subdomain) |
| `environment` | `prod` | Environment tag |
| `ecs_cpu` | `256` | Fargate CPU units |
| `ecs_memory` | `512` | Fargate memory (MiB) |
| `container_port` | `3000` | Container port |

### Initial Setup

```sh
# Create state bucket
aws s3 mb s3://copypasto-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket copypasto-terraform-state \
    --versioning-configuration Status=Enabled

# Set JWT secrets
aws ssm put-parameter --name /copypasto/prod/jwt-secret \
    --value "$(openssl rand -hex 32)" --type SecureString --region us-east-1
aws ssm put-parameter --name /copypasto/prod/jwt-refresh-secret \
    --value "$(openssl rand -hex 32)" --type SecureString --region us-east-1

# Deploy infrastructure
cd terraform
terraform init
terraform apply
```

## Security Summary

| Layer | Mechanism |
|-------|-----------|
| Data at rest | AES-256-GCM (client-side, server stores only ciphertext) |
| Data in transit | TLS 1.3 (HTTPS + WSS) |
| Passwords | bcrypt (12 rounds) |
| Key derivation | PBKDF2-SHA256 (600,000 iterations) |
| Tokens | JWT with single-use refresh token rotation |
| Token storage | macOS Keychain |
| Network | Private subnets for ECS, ALB in public subnets, security groups restrict access |
| Secrets | AWS SSM Parameter Store (SecureString) |
