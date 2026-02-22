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
if ! command -v docker &> /dev/null; then
    echo_error "docker is not installed. Please install Docker first."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo_error "Docker daemon is not running. Please start Docker first."
    exit 1
fi

# --- Detect Docker Compose command (V2 plugin vs V1 standalone) ---
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo_error "Docker Compose not found. Install the Docker Compose plugin or standalone binary."
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
docker rm -f elastic-agent 2>/dev/null || true
$DOCKER_COMPOSE down -v 2>/dev/null || true

echo_info "Removing additional volumes..."
docker volume ls --format '{{.Name}}' | grep -E '(fleetserverdata|agentdata)' | while read -r vol; do
    docker volume rm "$vol" 2>/dev/null || true
done

echo_info "Cleanup complete!"
echo_info "Run ./setup.sh to start fresh."
