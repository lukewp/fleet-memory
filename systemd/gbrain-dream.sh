#!/bin/bash
# Nightly dream cycle — stops serve, runs dream, restarts serve.
# PGLite is single-process so CLI and serve can't run concurrently.
set -euo pipefail

LOG_TAG="gbrain-dream"

logger -t "$LOG_TAG" "Starting dream cycle"
systemctl stop gbrain.service || true
sleep 2

# Run dream as the gbrain user
GBRAIN_USER=$(stat -c '%U' /data/gbrain/brain)
sudo -u "$GBRAIN_USER" bash -c '
  cd /data/gbrain
  set -a; source /data/fleet-memory/.env; set +a
  ~/.bun/bin/bun run src/cli.ts dream --json
' 2>&1 | logger -t "$LOG_TAG"

logger -t "$LOG_TAG" "Dream complete, restarting serve"
systemctl start gbrain.service
