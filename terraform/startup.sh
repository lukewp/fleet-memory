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

# --- Install Tailscale ---
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "Tailscale installed"
fi

# Authenticate Tailscale (idempotent)
tailscale up --authkey="${tailscale_auth_key}" --hostname=fleet-memory

# --- Install Bun ---
if ! command -v bun &>/dev/null; then
  curl -fsSL https://bun.sh/install | bash
  echo 'export BUN_INSTALL="$HOME/.bun"' >> /etc/profile.d/bun.sh
  echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> /etc/profile.d/bun.sh
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  echo "Bun installed"
fi

# --- System packages ---
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip git unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' > /etc/apt/apt.conf.d/51fleet-memory

# --- Create data directories ---
mkdir -p /data/{brain,vault/{transcripts,notes}}

# --- Clone fleet-memory repo (our config + scripts) ---
if [ ! -d /data/fleet-memory ]; then
  git clone https://github.com/lukewp/fleet-memory.git /data/fleet-memory
  echo "Fleet-memory repo cloned"
fi

# --- Clone and install gbrain ---
if [ ! -d /data/gbrain ]; then
  git clone https://github.com/garrytan/gbrain.git /data/gbrain
  cd /data/gbrain
  $BUN_INSTALL/bin/bun install
  $BUN_INSTALL/bin/bun link
  echo "gbrain installed"
fi


# --- Initialize brain git repo (needed for gbrain sync phase) ---
if [ ! -d /data/brain/.git ]; then
  cd /data/brain
  git init
  git add -A
  git commit -m "Initialize brain" --allow-empty
  echo "Brain git repo initialized"
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

# --- Set ownership ---
DATA_OWNER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
DATA_OWNER=$${DATA_OWNER:-ubuntu}
chown -R "$DATA_OWNER:$DATA_OWNER" /data

# --- Install gbrain CLI wrapper ---
if [ ! -f /usr/local/bin/gbrain ]; then
  cat > /usr/local/bin/gbrain << WRAPPER
#!/bin/bash
cd /data/gbrain && /home/$DATA_OWNER/.bun/bin/bun run src/cli.ts "\\\$@"
WRAPPER
  chmod +x /usr/local/bin/gbrain
  echo "gbrain CLI wrapper installed"
fi

# --- Install gbrain systemd service ---
if [ ! -f /etc/systemd/system/gbrain.service ]; then
  sed "s|User=.*|User=$DATA_OWNER|g; s|ExecStart=.*bun|ExecStart=/home/$DATA_OWNER/.bun/bin/bun|g" \
    /data/fleet-memory/systemd/gbrain.service > /etc/systemd/system/gbrain.service
  systemctl daemon-reload
  systemctl enable gbrain
  echo "gbrain systemd service installed"
fi

# --- Install gbrain dream timer (nightly maintenance) ---
if [ ! -f /etc/systemd/system/gbrain-dream.timer ]; then
  cp /data/fleet-memory/systemd/gbrain-dream.service /etc/systemd/system/
  cp /data/fleet-memory/systemd/gbrain-dream.timer /etc/systemd/system/
  chmod +x /data/fleet-memory/systemd/gbrain-dream.sh
  systemctl daemon-reload
  systemctl enable --now gbrain-dream.timer
  echo "gbrain dream timer installed (nightly at 3am)"
fi

# --- Set up Tailscale Funnel (persistent via --bg) ---
tailscale funnel --bg 8787 2>/dev/null || true

echo "=== Fleet Memory setup complete $(date) ==="
