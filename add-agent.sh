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

# --- Detect local vs remote mode ---
if $CONTAINER_CLI ps --format '{{.Names}}' 2>/dev/null | grep -q '^fleet-server$'; then
    echo_info "Fleet Server detected locally — local mode"
    LOCAL_MODE=true
else
    echo_info "Fleet Server not found locally — remote mode"
    LOCAL_MODE=false
fi

# --- Validate remote mode requirements ---
if [ "$LOCAL_MODE" = false ]; then
    if [ -z "$CA_CERT" ] || [ ! -f "$CA_CERT" ]; then
        echo_error "Remote mode requires CA_CERT in .env (path to ca.crt file)"
        echo_error "Extract from Fleet Server host: $CONTAINER_CLI cp fleet-server:/certs/ca/ca.crt ./ca.crt"
        exit 1
    fi
    if [ -z "$FLEET_URL" ] || [ "$FLEET_URL" = "https://fleet-server:8220" ]; then
        echo_error "Remote mode requires FLEET_URL in .env set to Fleet Server's external address"
        echo_error "Example: FLEET_URL=https://10.0.0.1:8220"
        exit 1
    fi
fi

# --- Set URLs per mode ---
if [ "$LOCAL_MODE" = true ]; then
    SCRIPT_KIBANA_URL="http://localhost:${KIBANA_PORT}"
    AGENT_FLEET_URL="https://fleet-server:8220"
    AGENT_KIBANA_HOST="http://kibana:5601"
    AGENT_ES_HOST="https://es01:9200"
else
    SCRIPT_KIBANA_URL="${KIBANA_URL}"
    AGENT_FLEET_URL="${FLEET_URL}"
    AGENT_KIBANA_HOST="${KIBANA_URL}"
    AGENT_ES_HOST="${ES_URL}"
fi

# Create agent policy if it doesn't exist
echo_info "Creating agent policy..."
curl -s -X POST "${SCRIPT_KIBANA_URL}/api/fleet/agent_policies" \
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
curl -s -X POST "${SCRIPT_KIBANA_URL}/api/fleet/package_policies" \
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

# --- Build run arguments ---
RUN_ARGS=()

if [ "$LOCAL_MODE" = true ]; then
    # Local: mount certs volume, join compose network
    VOLUME_PREFIX=$($CONTAINER_CLI volume ls --format '{{.Name}}' | grep certs | head -1 | sed 's/_certs$//')
    RUN_ARGS+=(-v "${VOLUME_PREFIX}_certs:/certs:ro")
    RUN_ARGS+=(--network elastic)
else
    # Remote: mount CA cert file only
    RUN_ARGS+=(-v "${CA_CERT}:/certs/ca/ca.crt:ro")
fi

# --- Detect OS for host filesystem mounts ---
PLATFORM="$(uname -s)"
case "$PLATFORM" in
    Linux)
        RUN_ARGS+=(
            -v /var/log:/var/log:ro
            -v /var/lib/docker/containers:/var/lib/docker/containers:ro
            -v /proc:/hostfs/proc:ro
            -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro
            -v /:/hostfs:ro
        )
        ;;
    Darwin)
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
    --user root \
    "${RUN_ARGS[@]}" \
    -e FLEET_ENROLL=1 \
    -e FLEET_URL=${AGENT_FLEET_URL} \
    -e FLEET_CA=/certs/ca/ca.crt \
    -e KIBANA_HOST=${AGENT_KIBANA_HOST} \
    -e ELASTICSEARCH_HOST=${AGENT_ES_HOST} \
    -e ELASTICSEARCH_CA=/certs/ca/ca.crt \
    docker.elastic.co/beats/elastic-agent:${STACK_VERSION} > /dev/null

echo_info "Elastic Agent '${AGENT_NAME}' started!"
echo_info "Check status in Kibana: Fleet > Agents"
