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

# --- Detect Compose command ---
if $CONTAINER_CLI compose version &> /dev/null; then
    COMPOSE_CMD="$CONTAINER_CLI compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo_error "Compose not found. Install the compose plugin or standalone binary."
    exit 1
fi

echo_warn "=== Elastic Stack Cleanup ==="
echo_warn "This will remove all containers and volumes!"
echo ""
read -p "Are you sure? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo_info "Cancelled."
    exit 0
fi

echo_info "Stopping and removing containers..."
$CONTAINER_CLI rm -f elastic-agent 2>/dev/null || true
$COMPOSE_CMD down -v 2>/dev/null || true

echo_info "Removing additional volumes..."
$CONTAINER_CLI volume ls --format '{{.Name}}' | grep -E '(fleetserverdata|agentdata)' | while read -r vol; do
    $CONTAINER_CLI volume rm "$vol" 2>/dev/null || true
done

echo_info "Cleanup complete!"
echo_info "Run ./setup.sh to start fresh."
