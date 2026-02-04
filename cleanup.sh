#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

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
docker rm -f fleet-server elastic-agent 2>/dev/null || true
docker-compose down -v 2>/dev/null || true

echo_info "Removing additional volumes..."
docker volume ls --format '{{.Name}}' | grep -E '(fleetserverdata|agentdata)' | xargs -r docker volume rm 2>/dev/null || true

echo_info "Cleanup complete!"
echo_info "Run ./setup.sh to start fresh."
