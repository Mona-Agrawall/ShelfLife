#!/bin/bash
# =============================================================================
# user_data_app.sh — Bootstrap script for ShelfLife Application Server
# Runs as root on first boot via EC2 user data
# =============================================================================

set -euo pipefail
LOG="/var/log/user_data.log"
exec > >(tee -a "$LOG") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting application server bootstrap..."

# -----------------------------------------------------------------------------
# 1. Update apt package index
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updating apt package index..."
apt-get update -y

# -----------------------------------------------------------------------------
# 2. Install Docker from Docker's official apt repository
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing Docker..."

# Install prerequisite packages
apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor --batch --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Docker installed."

# -----------------------------------------------------------------------------
# 3. Add ubuntu user to docker group
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding ubuntu user to docker group..."
usermod -aG docker ubuntu
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ubuntu user added to docker group."

# -----------------------------------------------------------------------------
# 4. Enable and start Docker service
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Docker service started."

# -----------------------------------------------------------------------------
# 5. Create /data directory for SQLite persistence
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating /data directory..."
mkdir -p /data
chown ubuntu:ubuntu /data
chmod 755 /data
echo "[$(date '+%Y-%m-%d %H:%M:%S')] /data directory created with proper permissions."

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Application server bootstrap complete!"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Docker is ready. Deploy the ShelfLife container with:"
echo "[$(date '+%Y-%m-%d %H:%M:%S')]   docker run -d -p 5000:5000 -v /data:/data shelflife-app"
