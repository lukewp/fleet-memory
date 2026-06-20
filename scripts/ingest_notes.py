#!/usr/bin/env python3
"""
Ingest markdown notes into Cognee via its REST API.

Usage:
    python scripts/ingest_notes.py [--server http://fleet-memory:8000] [--vault /data/vault]
    python scripts/ingest_notes.py --dry-run  # preview what would be ingested

Reads .md files from vault/notes/{agent}/ directories, uploads them to Cognee
as datasets (one per agent), then triggers cognify to build the knowledge graph.
"""

import argparse
import glob
import os
import sys
import time

import httpx

DEFAULT_SERVER = os.environ.get("COGNEE_SERVER", "http://localhost:8000")
DEFAULT_VAULT = os.environ.get("VAULT_PATH", "/data/vault")

# Auto-discover subdirectories under vault/notes/, or override with --agent
AGENT_DIRS = None  # discovered at runtime


def health_check(client: httpx.Client, server: str) -> bool:
    try:
        resp = client.get(f"{server}/health", timeout=10.0)
        return resp.status_code == 200
    except Exception:
        return False


def add_text(client: httpx.Client, server: str, text: str, dataset: str) -> dict:
    """Add text content to a Cognee dataset."""
    resp = client.post(
        f"{server}/api/v1/add",
        json={"data": text, "dataset_name": dataset},
        timeout=60.0,
    )
    resp.raise_for_status()
    return resp.json()


def cognify(client: httpx.Client, server: str, datasets: list[str] | None = None) -> dict:
    """Trigger Cognee to process added data into the knowledge graph."""
    params = {}
    if datasets:
        params["datasets"] = datasets
    resp = client.post(
        f"{server}/api/v1/cognify",
        json=params if params else None,
        timeout=300.0,  # cognify can take a while
    )
    resp.raise_for_status()
    return resp.json()


def search(client: httpx.Client, server: str, query: str) -> dict:
    """Search the knowledge graph."""
    resp = client.post(
        f"{server}/api/v1/search",
        json={"query": query},
        timeout=30.0,
    )
    resp.raise_for_status()
    return resp.json()


def ingest_directory(
    client: httpx.Client,
    server: str,
    agent: str,
    notes_dir: str,
    dry_run: bool = False,
) -> int:
    """Ingest all markdown files from a directory. Returns count of files added."""
    files = sorted(glob.glob(os.path.join(notes_dir, "*.md")))
    if not files:
        print(f"  No .md files found in {notes_dir}")
        return 0

    added = 0
    for i, filepath in enumerate(files, 1):
        name = os.path.basename(filepath)
        with open(filepath) as f:
            text = f.read().strip()

        if not text:
            print(f"  [{i}/{len(files)}] Skipping empty: {name}")
            continue

        # Truncate very large files
        if len(text) > 50_000:
            print(f"  [{i}/{len(files)}] Truncating {name} ({len(text)} -> 50000 chars)")
            text = text[:50_000]

        if dry_run:
            print(f"  [{i}/{len(files)}] Would add: {name} ({len(text)} chars) -> dataset '{agent}'")
            added += 1
            continue

        try:
            print(f"  [{i}/{len(files)}] Adding {name} ({len(text)} chars)...", end=" ", flush=True)
            start = time.time()
            add_text(client, server, text, dataset=agent)
            elapsed = time.time() - start
            print(f"OK ({elapsed:.1f}s)")
            added += 1
        except Exception as e:
            print(f"ERROR: {e}")

    return added


def main():
    parser = argparse.ArgumentParser(description="Ingest markdown notes into Cognee")
    parser.add_argument("--server", default=DEFAULT_SERVER, help="Cognee API server URL")
    parser.add_argument("--vault", default=DEFAULT_VAULT, help="Vault root directory")
    parser.add_argument("--agent", help="Only ingest for a specific agent")
    parser.add_argument("--dry-run", action="store_true", help="List files without ingesting")
    parser.add_argument("--skip-cognify", action="store_true", help="Add data but don't build graph yet")
    parser.add_argument("--verify", help="Search query to verify after ingestion")
    args = parser.parse_args()

    if args.agent:
        agents = [args.agent]
    else:
        notes_root = os.path.join(args.vault, "notes")
        if not os.path.isdir(notes_root):
            print(f"Notes directory not found: {notes_root}")
            sys.exit(1)
        agents = sorted(d for d in os.listdir(notes_root)
                        if os.path.isdir(os.path.join(notes_root, d)) and not d.startswith("."))

    with httpx.Client() as client:
        if not args.dry_run:
            print(f"Connecting to Cognee at {args.server}...")
            if not health_check(client, args.server):
                print("Failed — is Cognee running? Try: cd /data/cognee && docker compose up -d")
                sys.exit(1)
            print("Connected.\n")

        datasets_with_data = []

        for agent in agents:
            notes_dir = os.path.join(args.vault, "notes", agent)
            if not os.path.isdir(notes_dir):
                print(f"Skipping {agent}: {notes_dir} not found")
                continue

            print(f"\n--- {agent} ---")
            added = ingest_directory(client, args.server, agent, notes_dir, args.dry_run)
            if added > 0:
                datasets_with_data.append(agent)

        if args.dry_run:
            print(f"\nDRY RUN complete: {sum(1 for _ in datasets_with_data)} datasets would be created")
            return

        if datasets_with_data and not args.skip_cognify:
            print(f"\nBuilding knowledge graph for: {', '.join(datasets_with_data)}...")
            try:
                start = time.time()
                cognify(client, args.server, datasets_with_data)
                elapsed = time.time() - start
                print(f"Cognify complete ({elapsed:.1f}s)")
            except Exception as e:
                print(f"Cognify error: {e}")
                print("You can retry later: POST /api/v1/cognify")

        if args.verify and datasets_with_data:
            print(f"\nVerifying: '{args.verify}'")
            try:
                results = search(client, args.server, args.verify)
                print(f"Results: {results}")
            except Exception as e:
                print(f"Search error: {e}")


if __name__ == "__main__":
    main()
