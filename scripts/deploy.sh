#!/usr/bin/env bash
# deploy.sh — Runs ON the app server (called via SSH from Jenkins).
# Usage: IMAGE=<registry/image:tag> ./deploy.sh
#   or:  ./deploy.sh <registry/image:tag>
#
# This script:
#   1. Accepts the full Docker image name:tag as $1 or env var IMAGE
#   2. Pulls the new image from the registry
#   3. Stops and removes any existing container named "shelflife"
#   4. Starts a new container with the updated image
#   5. Waits 10 s, then verifies the /health endpoint responds OK
#   6. Exits 0 on success, 1 on health-check failure

# ---------------------------------------------------------------------------
# Strict mode: exit on error, undefined variables, or pipe failures
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve the image name: CLI argument takes precedence over env var IMAGE
# ---------------------------------------------------------------------------
IMAGE="${1:-${IMAGE:-}}"
if [[ -z "$IMAGE" ]]; then
    echo "ERROR: No image specified. Pass it as the first argument or set IMAGE env var." >&2
    exit 1
fi

CONTAINER_NAME="shelflife"

echo "==> Deploying image: $IMAGE"

# ---------------------------------------------------------------------------
# Step 1: Pull the latest image from the registry
# ---------------------------------------------------------------------------
echo "==> Pulling image..."
docker pull "$IMAGE"

# ---------------------------------------------------------------------------
# Step 2: Stop and remove the old container (ignore errors if not running)
# ---------------------------------------------------------------------------
echo "==> Stopping and removing existing container (if any)..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 3: Run the new container
#   -d                      — detached (background)
#   --name shelflife        — fixed container name for easy management
#   -p 80:5000              — map host port 80 → container port 5000
#   -v shelflife-data:/data — named volume for persistent SQLite database
#   -e DB_PATH              — tell the app where to store the database
#   --restart unless-stopped— auto-restart on reboot or crash
#
# AWS CloudWatch Logs (optional — uncomment to enable):
#   --log-driver=awslogs
#   --log-opt awslogs-group=/shelflife/app
#   --log-opt awslogs-region=us-east-1
# ---------------------------------------------------------------------------
echo "==> Starting new container..."
# To enable AWS CloudWatch Logs, uncomment the three --log-* lines below
# and remove them from the comment block before adding to the docker run command.
#   --log-driver=awslogs
#   --log-opt awslogs-group=/shelflife/app
#   --log-opt awslogs-region=us-east-1
docker run -d \
    --name "$CONTAINER_NAME" \
    -p 80:5000 \
    -v shelflife-data:/data \
    -e DB_PATH=/data/shelflife.db \
    --restart unless-stopped \
    "$IMAGE"

# ---------------------------------------------------------------------------
# Step 4: Wait for the container to initialize, then check the health endpoint
# ---------------------------------------------------------------------------
echo "==> Waiting for container to initialize and checking health endpoint..."
HEALTHY=false
for i in {1..15}; do
    if curl -sf http://localhost/health >/dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    echo "Waiting for container to become healthy (attempt $i/15)..."
    sleep 2
done

if [ "$HEALTHY" = true ]; then
    echo "==> Health check PASSED: http://localhost/health responded with HTTP 200."
    curl -s http://localhost/health
    echo ""
    echo "==> Deployment successful."
    exit 0
else
    echo "ERROR: Health check FAILED. The container may not be running correctly." >&2
    docker logs "$CONTAINER_NAME" >&2 || true
    exit 1
fi
