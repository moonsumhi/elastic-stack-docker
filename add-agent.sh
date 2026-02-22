#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Prerequisite checks ---
if ! command -v curl &> /dev/null; then
    echo_error "curl is not installed. Please install it first."
    exit 1
fi

# --- Detect container runtime (Docker or Podman) ---
if command -v docker &> /dev/null; then
    CONTAINER_CLI="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_CLI="podman"
else
    echo_error "Neither docker nor podman found. Please install a container runtime."
    exit 1
fi

# Daemon check (Docker only — Podman is daemonless)
if [ "$CONTAINER_CLI" = "docker" ] && ! docker info &> /dev/null; then
    echo_error "Docker daemon is not running. Please start Docker first."
    exit 1
fi

# Load environment variables
if [ ! -f .env ]; then
    echo_error ".env file not found!"
    exit 1
fi
source .env

# Agent name (optional argument)
AGENT_NAME=${1:-elastic-agent}

echo_info "=== Adding Elastic Agent: ${AGENT_NAME} ==="

# Check if Fleet Server is running
if ! $CONTAINER_CLI ps --format '{{.Names}}' | grep -q '^fleet-server$'; then
    echo_error "Fleet Server is not running! Run ./setup.sh first."
    exit 1
fi

# Get volume name prefix
VOLUME_PREFIX=$($CONTAINER_CLI volume ls --format '{{.Name}}' | grep certs | head -1 | sed 's/_certs$//')

# Create agent policy if it doesn't exist
echo_info "Creating agent policy..."
curl -s -X POST "http://localhost:5601/api/fleet/agent_policies" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "id": "default-agent-policy",
        "name": "Default Agent Policy",
        "namespace": "default",
        "monitoring_enabled": ["logs", "metrics"]
    }' > /dev/null 2>&1 || true

# Add System integration for metrics/logs collection
echo_info "Adding System integration..."
curl -s -X POST "http://localhost:5601/api/fleet/package_policies" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "System Integration",
        "namespace": "default",
        "policy_id": "default-agent-policy",
        "package": {
            "name": "system",
            "version": "1.64.2"
        }
    }' > /dev/null 2>&1 || true

# Remove existing agent if exists
$CONTAINER_CLI rm -f ${AGENT_NAME} 2>/dev/null || true

# --- Detect OS for volume mounts ---
PLATFORM="$(uname -s)"
VOLUME_ARGS=(
    -v "${VOLUME_PREFIX}_certs:/certs:ro"
)

case "$PLATFORM" in
    Linux)
        # Covers native Linux and WSL2
        VOLUME_ARGS+=(
            -v /var/log:/var/log:ro
            -v /var/lib/docker/containers:/var/lib/docker/containers:ro
            -v /proc:/hostfs/proc:ro
            -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro
            -v /:/hostfs:ro
        )
        ;;
    Darwin)
        # macOS: Docker Desktop runs in a VM, host filesystem mounts are not meaningful
        echo_warn "macOS detected: skipping host filesystem mounts (Docker Desktop VM)"
        ;;
    *)
        echo_warn "Unknown OS ($PLATFORM): skipping host filesystem mounts"
        ;;
esac

# Start Elastic Agent
echo_info "Starting Elastic Agent..."
$CONTAINER_CLI run -d \
    --name ${AGENT_NAME} \
    --network elastic \
    --user root \
    "${VOLUME_ARGS[@]}" \
    -e FLEET_ENROLL=1 \
    -e FLEET_URL=https://fleet-server:8220 \
    -e FLEET_CA=/certs/ca/ca.crt \
    -e KIBANA_HOST=http://kibana:5601 \
    -e ELASTICSEARCH_HOST=https://es01:9200 \
    -e ELASTICSEARCH_CA=/certs/ca/ca.crt \
    docker.elastic.co/beats/elastic-agent:${STACK_VERSION} > /dev/null

echo_info "Elastic Agent '${AGENT_NAME}' started!"
echo_info "Check status in Kibana: Fleet > Agents"
