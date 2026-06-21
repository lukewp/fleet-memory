#!/bin/bash
# Nightly dream cycle — stops serve, runs dream, restarts serve.
# PGLite is single-process so CLI and serve can't run concurrently.
# IMPORTANT: Always restart serve, even if dream fails.

LOG_TAG="gbrain-dream"

logger -t "$LOG_TAG" "Starting dream cycle"
systemctl stop gbrain.service || true
sleep 2

# Run dream as the data owner
GBRAIN_USER=$(stat -c '%U' /data/brain)
sudo -u "$GBRAIN_USER" bash -c '
  cd /data/gbrain
  set -a; source /data/fleet-memory/.env; set +a
  ~/.bun/bin/bun run src/cli.ts dream --json
' 2>&1 | logger -t "$LOG_TAG"
DREAM_EXIT=$?

if [ $DREAM_EXIT -ne 0 ]; then
  logger -t "$LOG_TAG" "Dream exited with code $DREAM_EXIT"
fi

logger -t "$LOG_TAG" "Restarting serve"
systemctl start gbrain.service
