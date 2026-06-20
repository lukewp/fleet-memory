#!/usr/bin/env python3
"""
Parse OpenClaw JSONL session transcripts into markdown files.

Extracts conversation turns (user + assistant text) from session JSONL files,
stripping tool_use blocks, tool_result blocks, and raw file contents.
Output markdown files can then be imported into gbrain via `gbrain import`.

Usage:
    python scripts/parse_transcripts.py /path/to/sessions/ --agent myagent \
        --output /data/vault/transcripts/myagent/

    # Then import into gbrain:
    # gbrain import /data/vault/transcripts/myagent/

    # Dry run
    python scripts/parse_transcripts.py /path/to/sessions/ --agent myagent --dry-run
"""

import argparse
import json
import os
import sys
import glob
from datetime import datetime
from pathlib import Path

MAX_CHARS_PER_SESSION = 30_000


def extract_conversation(filepath: str, max_chars: int = MAX_CHARS_PER_SESSION) -> dict | None:
    """Extract conversation text from a session JSONL file.

    Returns dict with keys: session_id, timestamp, turns, text, char_count
    or None if no meaningful conversation found.
    """
    session_id = None
    session_ts = None
    turns = []

    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            if entry.get("type") == "session":
                session_id = entry.get("id", Path(filepath).stem)
                session_ts = entry.get("timestamp")
                continue

            if entry.get("type") != "message":
                continue

            msg = entry.get("message", {})
            role = msg.get("role", "")

            if role not in ("user", "assistant"):
                continue

            content = msg.get("content", [])
            text_parts = []

            if isinstance(content, str):
                text_parts.append(content)
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        text_parts.append(block["text"])

            text = "\n".join(text_parts).strip()
            if not text or text == "HEARTBEAT_OK":
                continue

            turns.append({"role": role, "text": text})

    if not turns or len(turns) < 2:
        return None

    parts = []
    char_count = 0
    for turn in turns:
        prefix = "Human" if turn["role"] == "user" else "Assistant"
        segment = f"{prefix}: {turn['text']}\n"

        if len(segment) > 5000:
            segment = segment[:5000] + "\n[...truncated...]\n"

        if char_count + len(segment) > max_chars:
            parts.append("[...remaining conversation truncated...]\n")
            break

        parts.append(segment)
        char_count += len(segment)

    text = "\n".join(parts)

    if not session_id:
        session_id = Path(filepath).stem.split(".")[0]

    return {
        "session_id": session_id,
        "timestamp": session_ts,
        "turns": len(turns),
        "text": text,
        "char_count": len(text),
    }


def find_session_files(sessions_dir: str) -> list[str]:
    """Find JSONL session files, excluding trajectories and checkpoints."""
    all_files = glob.glob(os.path.join(sessions_dir, "*.jsonl"))
    return sorted(
        f for f in all_files
        if not any(skip in os.path.basename(f) for skip in [".trajectory.", ".checkpoint.", "-path."])
    )


def main():
    parser = argparse.ArgumentParser(description="Parse OpenClaw transcripts to markdown")
    parser.add_argument("sessions_dir", help="Directory containing JSONL session files")
    parser.add_argument("--agent", required=True, help="Agent name (used in output filenames)")
    parser.add_argument("--output", required=True, help="Output directory for parsed .md files")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be processed")
    parser.add_argument("--max-chars", type=int, default=MAX_CHARS_PER_SESSION)
    parser.add_argument("--skip-existing", action="store_true", help="Skip sessions already in output dir")
    parser.add_argument("--limit", type=int, help="Process only N sessions")
    args = parser.parse_args()

    files = find_session_files(args.sessions_dir)
    print(f"Found {len(files)} session files in {args.sessions_dir}")

    if args.limit:
        files = files[:args.limit]

    if not args.dry_run:
        os.makedirs(args.output, exist_ok=True)

    success = 0
    skipped = 0

    for i, filepath in enumerate(files, 1):
        session_id = os.path.basename(filepath).split(".")[0]

        if args.skip_existing:
            if os.path.exists(os.path.join(args.output, f"{session_id}.md")):
                skipped += 1
                continue

        result = extract_conversation(filepath, args.max_chars)
        if not result:
            skipped += 1
            continue

        ts_str = ""
        if result["timestamp"]:
            try:
                dt = datetime.fromisoformat(result["timestamp"].replace("Z", "+00:00"))
                ts_str = dt.strftime("%Y-%m-%d %H:%M UTC")
            except (ValueError, AttributeError):
                ts_str = result["timestamp"]

        label = f"{args.agent}/{session_id[:8]}"
        info = f"[{i}/{len(files)}] {label} — {result['turns']} turns, {result['char_count']} chars"
        if ts_str:
            info += f", {ts_str}"

        if args.dry_run:
            print(f"  {info}")
            success += 1
            continue

        outfile = os.path.join(args.output, f"{session_id}.md")
        header = f"# {args.agent} session {session_id[:8]}\n"
        if ts_str:
            header += f"Date: {ts_str}\n"
        header += f"Turns: {result['turns']}\n\n---\n\n"
        with open(outfile, "w") as f:
            f.write(header + result["text"])
        print(f"  {info} [saved]")
        success += 1

    print(f"\n{'DRY RUN' if args.dry_run else 'Done'}: {success} processed, {skipped} skipped")
    if success > 0 and not args.dry_run:
        print(f"\nNext: gbrain import {args.output}")


if __name__ == "__main__":
    main()
