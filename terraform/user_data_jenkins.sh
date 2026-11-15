#!/bin/bash
# =============================================================================
# user_data_jenkins.sh — Bootstrap script for Jenkins CI Server
# Runs as root on first boot via EC2 user data
# =============================================================================

set -euo pipefail
LOG="/var/log/user_data.log"
exec > >(tee -a "$LOG") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Jenkins server bootstrap..."

# -----------------------------------------------------------------------------
# 1. Update apt package index
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updating apt package index..."
apt-get update -y

# -----------------------------------------------------------------------------
# 2. Install Java 17 (required by Jenkins)
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing Java 17..."
apt-get install -y openjdk-17-jdk

java -version
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Java 17 installed."

# -----------------------------------------------------------------------------
# 3. Add Jenkins official apt repository and install Jenkins
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding Jenkins repository..."
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
  gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] \
  https://pkg.jenkins.io/debian-stable binary/" | \
  tee /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update -y
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing Jenkins..."
apt-get install -y jenkins

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jenkins installed."

# -----------------------------------------------------------------------------
# 4. Install Docker from Docker's official apt repository
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing Docker..."

# Install prerequisite packages
apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
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
# 5. Add ubuntu and jenkins users to docker group
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding users to docker group..."
usermod -aG docker ubuntu
usermod -aG docker jenkins
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Users added to docker group."

# -----------------------------------------------------------------------------
# 6. Install git
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing git..."
apt-get install -y git
git --version
echo "[$(date '+%Y-%m-%d %H:%M:%S')] git installed."

# -----------------------------------------------------------------------------
# 7. Create 2GB swap file for t2.micro/t3.small memory relief
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating 2GB swap file..."
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  # Persist swap across reboots
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Swap file created and enabled."
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Swap file already exists, skipping."
fi

# Show current swap
swapon --show

# -----------------------------------------------------------------------------
# 8. Enable and start Docker and Jenkins services
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Enabling and starting services..."

systemctl enable docker
systemctl start docker
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Docker service started."

systemctl enable jenkins
systemctl start jenkins
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jenkins service started."

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jenkins server bootstrap complete!"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jenkins initial admin password location: /var/lib/jenkins/secrets/initialAdminPassword"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wait ~2 minutes for Jenkins to fully start, then visit http://<public-ip>:8080"
