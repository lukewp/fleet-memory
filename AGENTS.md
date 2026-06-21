# Agent Guidelines — Fleet Memory

## Security: No Secrets in This Repo

This is a public-facing deployment repo. Every commit is assumed visible.

**Never commit:**
- API keys, bearer tokens, or auth secrets
- `terraform.tfvars` or `.env` (both gitignored)
- Tailscale node names, hostnames, or tailnet identifiers
- GCP project IDs, service account emails, or IP addresses
- Specific usernames or email addresses
- Terraform state files (gitignored but be vigilant)

**Always use:**
- `.env.example` / `terraform.tfvars.example` with placeholder values
- Terraform variables for anything deployment-specific
- Generic references ("the VM", "the MCP endpoint") in docs and comments

If you're unsure whether something is a secret, it is. Use a variable or placeholder.

## Architecture Decisions

These are settled and should not be revisited without explicit discussion:

1. **gbrain from upstream** — cloned at deploy time, not forked. No local patches.
2. **PGLite over Supabase** — single-VM simplicity, no external DB dependency.
3. **Tailscale-only access** — no public IP, no ingress firewall rules.
4. **Bearer token auth** — OAuth custom connector path didn't work (Claude.ai can't reach tailnet endpoints for token exchange). Legacy bearer tokens via `gbrain auth create` bypass OAuth entirely.
5. **OpenRouter for LLM/embeddings** — single API key for multiple providers.
6. **systemd for lifecycle** — gbrain.service for serve, timer for dream cycle.
7. **Stop/dream/start pattern** — PGLite single-process lock means CLI and serve can't coexist. Dream wrapper handles this.

## Data Ingestion Patterns

- **Markdown notes:** `gbrain import <dir>` (stop serve first)
- **Session transcripts (JSONL):** Parse with `scripts/parse_transcripts.py` → markdown → import
- **ChatGPT exports:** Parse with conversation linearizer → markdown → import
- **Ad-hoc pages:** `gbrain put <slug> < file.md` or via MCP `put_page` tool
- **All writes are idempotent** — `put` creates or updates. Safe to re-run.

## Pivot History

Graphiti → Cognee → gbrain. Each pivot was operational (Docker disk exhaustion, dependency hell), not conceptual. The current stack is stable. Don't suggest alternatives unless there's a concrete operational failure.

## What This Repo Does NOT Contain

- gbrain source code (upstream)
- Brain data or vault contents (on the VM's data disk)
- Agent configurations (live in each agent's own config)
- Session transcripts or memory notes (ingested into gbrain, not stored here)
