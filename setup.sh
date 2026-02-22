#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Prerequisite checks ---
for cmd in docker curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo_error "$cmd is not installed. Please install it first."
        exit 1
    fi
done

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

# Load environment variables
if [ ! -f .env ]; then
    echo_error ".env file not found! Please create it first."
    exit 1
fi
source .env

echo_info "=== Elastic Stack Setup Script ==="
echo_info "Version: ${STACK_VERSION}"
echo ""

# Step 1: Start all services (Elasticsearch, Kibana, Fleet Server)
echo_info "Step 1: Starting Elasticsearch, Kibana, and Fleet Server..."
$DOCKER_COMPOSE up -d

# Step 2: Wait for Elasticsearch to be ready
echo_info "Step 2: Waiting for Elasticsearch to be healthy..."
until docker exec es01 curl -s --cacert /usr/share/elasticsearch/config/certs/ca/ca.crt \
    -u "elastic:${ELASTIC_PASSWORD}" \
    https://localhost:9200/_cluster/health | grep -q '"status"'; do
    echo_warn "Elasticsearch not ready yet, waiting 10 seconds..."
    sleep 10
done
echo_info "Elasticsearch is healthy!"

# Step 3: Set kibana_system password
echo_info "Step 3: Setting kibana_system password..."
docker exec es01 curl -s -X POST --cacert /usr/share/elasticsearch/config/certs/ca/ca.crt \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H "Content-Type: application/json" \
    https://localhost:9200/_security/user/kibana_system/_password \
    -d "{\"password\":\"${ELASTIC_PASSWORD}\"}" > /dev/null
echo_info "kibana_system password set!"

# Step 4: Wait for Kibana to be ready
echo_info "Step 4: Waiting for Kibana to be healthy..."
until curl -s -I http://localhost:5601 2>/dev/null | grep -q "302 Found"; do
    echo_warn "Kibana not ready yet, waiting 10 seconds..."
    sleep 10
done
echo_info "Kibana is healthy!"

# Step 5: Wait for Fleet Server to be healthy
echo_info "Step 5: Waiting for Fleet Server to be healthy..."
RETRY=0
MAX_RETRY=30
until docker exec fleet-server curl -s --cacert /certs/ca/ca.crt https://localhost:8220/api/status 2>/dev/null | grep -q '"HEALTHY"'; do
    RETRY=$((RETRY + 1))
    if [ $RETRY -ge $MAX_RETRY ]; then
        echo_warn "Fleet Server taking longer than expected. Check logs with: docker logs fleet-server"
        break
    fi
    echo_warn "Fleet Server not ready yet, waiting 10 seconds... ($RETRY/$MAX_RETRY)"
    sleep 10
done

if docker exec fleet-server curl -s --cacert /certs/ca/ca.crt https://localhost:8220/api/status 2>/dev/null | grep -q '"HEALTHY"'; then
    echo_info "Fleet Server is healthy!"
fi

echo ""
echo_info "=== Setup Complete! ==="
echo ""
echo_info "Access URLs:"
echo "  - Kibana:         http://localhost:${KIBANA_PORT}"
echo "  - Elasticsearch:  https://localhost:${ES_PORT}"
echo "  - Fleet Server:   https://localhost:${FLEET_PORT}"
echo ""
echo_info "Login credentials:"
echo "  - Username: elastic"
echo "  - Password: ${ELASTIC_PASSWORD}"
echo ""
echo_info "To add an Elastic Agent, run:"
echo "  ./add-agent.sh"
