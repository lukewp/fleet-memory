# Fleet Memory

Self-hosted [gbrain](https://github.com/garrytan/gbrain) deployment for cross-agent memory. Agents connect via MCP (stdio or HTTP) over Tailscale; data stays on your own infrastructure.

## What This Repo Contains

This is **not** a fork of gbrain. It's a deployment wrapper: Terraform for the GCP VM, environment config, and ingestion helpers. gbrain itself is cloned from upstream at deploy time.

## Architecture

```
GCP VM (e2-standard-2) — Tailscale-only access
├── gbrain (Bun runtime + PGLite)
│   ├── MCP Server (HTTP, OAuth 2.1)
│   ├── Knowledge Graph (zero-LLM, deterministic)
│   ├── Vector Search (pgvector/PGLite)
│   └── Dream Cycle (overnight enrichment)
└── Markdown Vault (/data/vault/, git-managed)
```

**Runtime:** Bun (TypeScript), no Docker required
**Storage:** PGLite (embedded Postgres 17, zero-config)
**Embeddings:** OpenAI text-embedding-3-large
**Graph:** Zero-LLM entity extraction (deterministic)
**Access:** Tailscale mesh VPN, no public IP (Cloud NAT for outbound)

## Prerequisites

- GCP project with billing enabled
- [Terraform](https://developer.hashicorp.com/terraform/install) installed locally
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- Compute Engine API enabled (`gcloud services enable compute.googleapis.com`)
- [Tailscale](https://tailscale.com) account with a reusable auth key
- OpenAI API key (embeddings)
- Anthropic API key (optional — dream cycle, search expansion)

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: set project, region/zone, tailscale_auth_key

terraform init
terraform plan
terraform apply
```

The startup script installs Bun, Tailscale, clones gbrain, and creates data directories. Takes ~3 minutes.

## Configure & Start

SSH into the VM (via IAP or Tailscale) and initialize:

```bash
cd /data/fleet-memory
cp .env.example .env
nano .env  # Add API keys

source .env
cd /data/gbrain
gbrain init --home /data/brain
```

Start the MCP server:

```bash
gbrain serve --http
```

## Connect Agents

Any MCP-compatible agent can connect via Tailscale:

```json
{
  "mcpServers": {
    "memory": {
      "transport": "http",
      "url": "http://fleet-memory:8080"
    }
  }
}
```

Works with Claude Code, Claude Desktop, Codex, Cursor, ChatGPT, and Perplexity.

## Ingest Data

```bash
# Import a directory of markdown notes
gbrain import /data/vault/notes/ --workers 4

# Generate embeddings
gbrain embed --stale

# Build knowledge graph
gbrain extract links --source db

# Sync from a git repo (incremental)
gbrain sync --repo /data/vault
```

For session transcripts, use the included parser to convert JSONL to markdown first:

```bash
python scripts/parse_transcripts.py /path/to/sessions/ --agent myagent \
    --output /data/vault/transcripts/myagent/

# Then import
gbrain import /data/vault/transcripts/myagent/
```

## Dream Cycle

gbrain can run overnight enrichment — dedup, citation fixing, salience scoring, contradiction detection:

```bash
gbrain dream
```

Set up as a cron job for autonomous maintenance.

## Backups

- **Disk snapshots:** Daily, 30-day retention (Terraform-managed)
- **Vault:** Nightly git auto-commit via cron
- **Brain data:** PGLite on persistent data disk (survives VM restarts)

## Cost

~$55/month: e2-standard-2 VM + 100 GB disk + snapshots + Cloud NAT + minimal API costs.

API costs are low — graph extraction is zero-LLM. Embeddings (OpenAI) are ~$1-2 for initial bulk import, negligible ongoing.

## Files

```
├── .env.example               # gbrain environment config template
├── scripts/
│   ├── parse_transcripts.py   # Parse OpenClaw JSONL sessions to markdown
│   └── requirements.txt
├── terraform/
│   ├── main.tf                # VM, disk, firewall, Cloud NAT
│   ├── variables.tf
│   ├── outputs.tf
│   ├── startup.sh             # Bootstrap: Bun, Tailscale, gbrain
│   └── terraform.tfvars.example
└── README.md
```

## License

MIT
