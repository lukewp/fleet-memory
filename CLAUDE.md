# Fleet Memory

Deployment wrapper for [gbrain](https://github.com/garrytan/gbrain) — a self-hosted personal knowledge brain. This repo is NOT a fork; gbrain is cloned from upstream at deploy time. We own the infra, config, and ingestion tooling.

## Architecture

GCP VM (configurable via Terraform variables) running gbrain with PGLite (embedded Postgres 17). No Docker, no containers. Access is Tailscale-only with Cloud NAT for outbound. Agents connect via MCP over HTTP with bearer token auth.

Stack: Bun runtime → gbrain → PGLite → pgvector. Embeddings via OpenRouter or direct OpenAI. Graph extraction is zero-LLM (deterministic).

## Key Constraints

- **PGLite is single-process.** The `serve` daemon holds an exclusive lock on the database. CLI commands (`import`, `dream`, `embed`, etc.) cannot run while serve is active. The dream timer handles this by stopping serve, running dream, then restarting.
- **gbrain is upstream, not forked.** Don't put patches here — upstream issues or PRs only. This repo is pure deployment config.
- **No secrets in this repo.** API keys, bearer tokens, Tailscale auth keys, terraform.tfvars — all gitignored. Use `.env.example` and `terraform.tfvars.example` as templates. Never commit actual values, hostnames, IP addresses, or Tailscale node names.

## File Layout

```
.env.example            # gbrain env config template (API keys, model selection)
scripts/                 # Ingestion helpers (transcript parser, etc.)
systemd/                 # gbrain.service, dream timer (service + timer + wrapper script)
terraform/               # GCP VM, data disk, snapshots, Cloud NAT, firewall
  startup.sh             # Bootstrap: Bun, Tailscale, gbrain clone, systemd install
```

## Common Tasks

**Deploy from scratch:** `cd terraform && cp terraform.tfvars.example terraform.tfvars` → edit → `terraform apply`. Startup script handles the rest.

**Import data:** Stop serve first (`systemctl stop gbrain`), then `gbrain import <dir>`. Restart after.

**Dream cycle:** Runs nightly via systemd timer. Wrapper script handles the stop/dream/start dance. Check status: `systemctl list-timers gbrain-dream`.

**Connect an agent:** Use `gbrain auth create <name>` to generate a bearer token, then configure the agent's MCP client with the HTTP endpoint and `Authorization: Bearer <token>` header.

**Backups:** Daily disk snapshots (30-day retention, Terraform-managed) + nightly vault git auto-commit.

## Development Notes

- `startup.sh` uses Terraform `templatefile()` — double-dollar `$$` escapes are required for shell variables (e.g., `$${DATA_OWNER:-ubuntu}`).
- The vault backup cron and dream timer both target overnight hours. Dream has `RandomizedDelaySec=300` to avoid collisions.
- Config and graphiti.yaml are vestigial from earlier pivots (Graphiti → Cognee → gbrain). They can be cleaned up but don't cause harm.
