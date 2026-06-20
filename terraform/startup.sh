#!/bin/bash
set -euo pipefail

LOG="/var/log/fleet-memory-setup.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== Fleet Memory setup started $(date) ==="

# --- Format and mount data disk (only on first boot) ---
DATA_DEV="/dev/disk/by-id/google-fleet-memory-data"
DATA_MNT="/data"

if ! mountpoint -q "$DATA_MNT"; then
  mkdir -p "$DATA_MNT"
  if ! blkid "$DATA_DEV"; then
    mkfs.ext4 -m 0 -F "$DATA_DEV"
  fi
  mount "$DATA_DEV" "$DATA_MNT"
  echo "$DATA_DEV $DATA_MNT ext4 defaults,nofail 0 2" >> /etc/fstab
  echo "Data disk mounted at $DATA_MNT"
fi

# --- Install Docker ---
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  # Add all non-root human users to docker group (handles OS Login + default ubuntu)
  for u in $(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}'); do
    usermod -aG docker "$u"
  done
  systemctl enable docker
  echo "Docker installed"
fi

# --- Install Docker Compose plugin ---
if ! docker compose version &>/dev/null; then
  apt-get update -qq
  apt-get install -y -qq docker-compose-plugin
  echo "Docker Compose plugin installed"
fi

# --- Install Tailscale ---
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "Tailscale installed"
fi

# Authenticate Tailscale (idempotent)
tailscale up --authkey="${tailscale_auth_key}" --hostname=fleet-memory

# --- Unattended security upgrades ---
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' > /etc/apt/apt.conf.d/51fleet-memory

# --- Create data directories ---
mkdir -p /data/{cognee-data,cognee-system,vault/{transcripts,notes}}

# --- Clone fleet-memory repo (our config + scripts) ---
if [ ! -d /data/fleet-memory ]; then
  apt-get install -y -qq git
  git clone https://github.com/lukewp/fleet-memory.git /data/fleet-memory
  echo "Fleet-memory repo cloned"
fi

# --- Clone Cognee (application source) ---
if [ ! -d /data/cognee ]; then
  apt-get install -y -qq git
  git clone https://github.com/topoteretes/cognee.git /data/cognee
  echo "Cognee repo cloned"
fi

# --- Fix port conflicts: cognee API on 8000, MCP on 8001 ---
cd /data/cognee
if grep -q '"8000:8000" # MCP port' docker-compose.yml 2>/dev/null; then
  sed -i 's/- "8000:8000" # MCP port/- "8001:8000" # MCP port/' docker-compose.yml
  sed -i 's/- "5678:5678" # MCP debugger port/- "5679:5678" # MCP debugger port/' docker-compose.yml
  echo "MCP port updated to 8001"
fi

# --- Initialize vault git repo ---
if [ ! -d /data/vault/.git ]; then
  cd /data/vault
  git init
  git add -A
  git commit -m "Initialize vault" --allow-empty
  echo "Vault git repo initialized"
fi

# --- Nightly vault backup cron ---
cat > /etc/cron.d/vault-backup << 'EOF'
0 3 * * * root cd /data/vault && git add -A && git commit -m "auto $(date +\%F)" --allow-empty 2>/dev/null; true
EOF

# --- Weekly Docker cleanup (dangling images, stopped containers, build cache) ---
cat > /etc/cron.d/docker-prune << 'EOF'
0 4 * * 0 root docker system prune -af --filter "until=72h" >> /var/log/docker-prune.log 2>&1
EOF

# Set ownership to the first non-root human user (works with OS Login or default 'ubuntu')
DATA_OWNER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
DATA_OWNER=${DATA_OWNER:-ubuntu}
chown -R "$DATA_OWNER:$DATA_OWNER" /data

# --- Start services (if .env exists) ---
if [ -f /data/fleet-memory/.env ]; then
  cp /data/fleet-memory/.env /data/cognee/.env
  cd /data/cognee
  docker compose --profile mcp up -d --build
  echo "Cognee services started (API on :8000, MCP on :8001)"
else
  echo "WARNING: /data/fleet-memory/.env not found"
  echo "  cp /data/fleet-memory/.env.example /data/fleet-memory/.env"
  echo "  nano /data/fleet-memory/.env  # add API keys"
  echo "  cp /data/fleet-memory/.env /data/cognee/.env"
  echo "  cd /data/cognee && docker compose --profile mcp up -d --build"
fi

echo "=== Fleet Memory setup complete $(date) ==="
