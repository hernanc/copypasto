# Lessons Learned

Mistakes, failed approaches, regressions, and near-misses encountered during development. Every agent must read this file before starting non-trivial work and must add entries after encountering new issues.

## Format

Each entry follows this structure:

```
### [DATE] Short title
**What happened**: What went wrong or nearly went wrong.
**Root cause**: Why it happened.
**How detected**: How the issue was found.
**Fix**: What was done to resolve it.
**Prevention**: How to avoid repeating this.
```

---

### [2026-04-10] Docker image built for wrong platform — ECS deployment failed
**What happened**: `docker build` produced an ARM image (Apple Silicon default). ECS Fargate requires `linux/amd64`. The task failed with `CannotPullContainerError: image Manifest does not contain descriptor matching platform 'linux/amd64'`.
**Root cause**: `docker build` without `--platform` defaults to the host architecture. The deploy script originally used `docker build` instead of `docker buildx build --platform linux/amd64`.
**How detected**: ECS task failed to start. Error visible in ECS console task stopped reason.
**Fix**: Changed `deploy.sh` to use `docker buildx build --platform linux/amd64 --push` in a single command.
**Prevention**: Never use bare `docker build` for deployment images. Always use `docker buildx build --platform linux/amd64`. The `deploy.sh` script now handles this correctly — always use it rather than manual docker commands.

### [2026-04-10] SSM parameters created via CLI before Terraform — terraform apply failed
**What happened**: JWT secrets were created via `aws ssm put-parameter` before running `terraform apply`. Terraform tried to create the same parameters and failed with `ParameterAlreadyExists`.
**Root cause**: Terraform didn't know about resources created outside its state.
**Fix**: Used `terraform import aws_ssm_parameter.jwt_secret /copypasto/prod/jwt-secret` (and same for refresh secret) to bring existing resources into state.
**Prevention**: Either create all resources through Terraform from the start, or import existing resources before applying. If you create a resource manually that Terraform also manages, you must import it.

### [2026-04-10] Server code change not deployed — logs not appearing
**What happened**: Added a log line to `handler.ts` for clipboard storage events. Rebuilt the client and tested, but no logs appeared in CloudWatch.
**Root cause**: The server code was compiled locally but never deployed to ECS. The running container still had the old code.
**How detected**: User reported no logs appearing when copying to clipboard.
**Fix**: Ran `./deploy.sh` to build, push, and deploy the updated server.
**Prevention**: After any server-side code change, you must run `./deploy.sh` for the change to take effect in production. Local compilation (`npm run build`) only produces local artifacts. Always verify: did I deploy?

### [2026-04-10] API domain moved from apex to subdomain — client not updated
**What happened**: Terraform and Route53 were updated to serve the API from `api.copypasto.com` instead of `copypasto.com`, but the client initially still pointed to the apex domain.
**Root cause**: Cross-component change: domain change affects terraform (acm.tf, route53.tf), client (Constants.swift), and deploy script awareness.
**Fix**: Updated `Constants.swift` to use `https://api.copypasto.com/api` and `wss://api.copypasto.com/ws`.
**Prevention**: Domain/URL changes always require updating: `terraform/route53.tf`, `terraform/acm.tf`, and `client/Copypasto/Utilities/Constants.swift`. See the cross-component change matrix in `.cursor/rules/change-discipline.mdc`.
