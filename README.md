# Fleet Memory

Self-hosted [Cognee](https://github.com/topoteretes/cognee) deployment for cross-agent memory. Agents connect via MCP (SSE transport) over Tailscale; data stays on your own infrastructure.

## What This Repo Contains

This is **not** a fork of Cognee. It's a deployment wrapper: Terraform for the GCP VM, environment config, and ingestion scripts for loading existing data. Cognee itself is cloned from upstream at deploy time.

## Architecture

```
GCP VM (e2-standard-2) — Tailscale-only access
├── Cognee REST API  (port 8000) — ingestion + search
├── Cognee MCP Server (port 8001) — SSE transport for agents
└── Markdown Vault (/data/vault/, git-managed)

Storage (file-based, no extra containers):
  SQLite · KuzuDB · LanceDB
```

**LLM:** Configurable — defaults to DeepSeek via OpenRouter for entity extraction
**Embeddings:** OpenAI text-embedding-3-small (1536-dim)
**Access:** Tailscale mesh VPN, no public IP (Cloud NAT for outbound)

## Prerequisites

- GCP project with billing enabled
- [Terraform](https://developer.hashicorp.com/terraform/install) installed locally
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- Compute Engine API enabled (`gcloud services enable compute.googleapis.com`)
- [Tailscale](https://tailscale.com) account with a reusable auth key

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: set project, region/zone, tailscale_auth_key

terraform init
terraform plan
terraform apply
```

The startup script installs Docker, Tailscale, clones Cognee, and creates data directories. Takes ~5 minutes.

## Configure & Start

SSH into the VM (via IAP or Tailscale) and add your API keys:

```bash
cd /data/fleet-memory
cp .env.example .env
nano .env  # Add LLM + embedding API keys

cp .env /data/cognee/.env
cd /data/cognee
docker compose --profile mcp up -d --build
```

Verify: `curl http://localhost:8000/health`

## Connect Agents

Any MCP-compatible agent can connect via Tailscale:

```json
{
  "mcpServers": {
    "memory": {
      "transport": "sse",
      "url": "http://fleet-memory:8001"
    }
  }
}
```

## Ingest Data

Two scripts for bulk-loading existing data:

```bash
# Markdown notes
python scripts/ingest_notes.py --vault /data/vault --server http://localhost:8000

# OpenClaw JSONL session transcripts
python scripts/parse_transcripts.py /path/to/sessions/ --agent myagent \
    --ingest --server http://localhost:8000
```

Both support `--dry-run` to preview before committing. See each script's `--help` for full options.

## Backups

- **Disk snapshots:** Daily, 30-day retention (Terraform-managed)
- **Vault:** Nightly git auto-commit via cron
- **Docker:** Weekly prune of unused images

## Cost

~$55/month: e2-standard-2 VM + 100 GB disk + snapshots + Cloud NAT + minimal API costs.

## Files

```
├── .env.example               # Cognee environment config template
├── scripts/
│   ├── ingest_notes.py        # Bulk-ingest markdown files via REST API
│   ├── parse_transcripts.py   # Parse JSONL transcripts + optional ingestion
│   └── requirements.txt
├── terraform/
│   ├── main.tf                # VM, disk, firewall, Cloud NAT
│   ├── variables.tf
│   ├── outputs.tf
│   ├── startup.sh             # Bootstrap: Docker, Tailscale, Cognee
│   └── terraform.tfvars.example
└── README.md
```

## License

MIT
