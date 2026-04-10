# Success Patterns

Implementation approaches, debugging methods, and procedures that worked well. Every agent should consult this before choosing an approach for a similar task.

## Format

Each entry follows this structure:

```
### [DATE] Short title
**Context**: What was being done.
**Approach**: What worked.
**Why it worked**: Key insight or principle.
**Reuse when**: When to apply this pattern again.
```

---

### [2026-04-10] Terraform import for pre-existing resources
**Context**: SSM parameters were created via AWS CLI before Terraform managed them.
**Approach**: `terraform import <resource_address> <resource_id>` for each parameter, then `terraform apply` succeeded.
**Why it worked**: Import brings the resource into Terraform state without recreating it. The `lifecycle { ignore_changes = [value] }` block then prevents Terraform from overwriting the live secret values.
**Reuse when**: Any time a resource exists in AWS before Terraform manages it. Always import before apply.

### [2026-04-10] Single buildx command for cross-platform Docker builds
**Context**: Needed to build and push a linux/amd64 image from Apple Silicon.
**Approach**: `docker buildx build --platform linux/amd64 -t <ecr-uri>:latest --push server/` — build and push in one command.
**Why it worked**: Avoids the multi-step build/tag/push flow. `buildx` handles cross-compilation transparently. The `--push` flag pushes immediately after build, reducing the chance of pushing a stale or wrong image.
**Reuse when**: Any Docker build intended for ECS or other x86_64 deployment from an ARM dev machine.

### [2026-04-10] XcodeGen for reproducible project generation
**Context**: Needed an Xcode project without manually configuring build settings.
**Approach**: Created `client/project.yml` with XcodeGen spec, then `xcodegen generate` produces the `.xcodeproj`.
**Why it worked**: The `.xcodeproj` is generated, not hand-edited. The `project.yml` is human-readable and version-controllable. Regeneration is idempotent.
**Reuse when**: Any Xcode project setup or when build settings need to change. Edit `project.yml`, then regenerate.

### [2026-04-10] Zod discriminated union for WebSocket message validation
**Context**: WebSocket handler receives multiple message types that need type-safe parsing.
**Approach**: `z.discriminatedUnion("type", [clipboardPushSchema, pingSchema])` in `server/src/types/ws.ts`. Handler calls `clientMessageSchema.safeParse(json)` and gets narrowed types.
**Why it worked**: Single parse call validates and narrows the type. Each message type's payload is validated independently. Adding a new message type means adding one schema to the union — handler dispatch is type-checked.
**Reuse when**: Adding new WebSocket message types. Define the schema in `ws.ts`, add to the union, handle in `handler.ts`.

### [2026-04-10] Cross-component verification after every change
**Context**: Multiple changes touched server, client, and terraform simultaneously.
**Approach**: After each change, verify all three: `npx tsc --noEmit` (server), `xcodebuild` (client), `terraform validate` (terraform). Then test the live endpoint with `curl`.
**Why it worked**: Catches cross-component breakage immediately rather than discovering it at deploy time.
**Reuse when**: Any change that touches more than one component. Always verify all affected components before declaring done.
