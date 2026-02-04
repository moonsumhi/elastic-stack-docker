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

# Load environment variables
if [ ! -f .env ]; then
    echo_error ".env file not found! Please create it first."
    exit 1
fi
source .env

echo_info "=== Elastic Stack Setup Script ==="
echo_info "Version: ${STACK_VERSION}"
echo ""

# Step 1: Start Elasticsearch and Kibana
echo_info "Step 1: Starting Elasticsearch and Kibana..."
docker-compose up -d

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

# Step 5: Initialize Fleet
echo_info "Step 5: Initializing Fleet..."
curl -s -X POST "http://localhost:5601/api/fleet/setup" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" > /dev/null
echo_info "Fleet initialized!"

# Step 6: Create Fleet Server policy
echo_info "Step 6: Creating Fleet Server policy..."
POLICY_RESPONSE=$(curl -s -X POST "http://localhost:5601/api/fleet/agent_policies" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "id": "fleet-server-policy",
        "name": "Fleet Server Policy",
        "namespace": "default",
        "has_fleet_server": true,
        "monitoring_enabled": ["logs", "metrics"]
    }' 2>/dev/null)

if echo "$POLICY_RESPONSE" | grep -q '"id":"fleet-server-policy"'; then
    echo_info "Fleet Server policy created!"
else
    echo_warn "Fleet Server policy may already exist, continuing..."
fi

# Step 7: Add Fleet Server integration to policy
echo_info "Step 7: Adding Fleet Server integration..."
curl -s -X POST "http://localhost:5601/api/fleet/package_policies" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Fleet Server",
        "namespace": "default",
        "policy_id": "fleet-server-policy",
        "package": {
            "name": "fleet_server",
            "version": "1.6.0"
        },
        "inputs": [{
            "type": "fleet-server",
            "enabled": true,
            "vars": {},
            "streams": []
        }]
    }' > /dev/null 2>&1
echo_info "Fleet Server integration added!"

# Step 8: Set Fleet Server hosts
echo_info "Step 8: Configuring Fleet Server hosts..."
curl -s -X PUT "http://localhost:5601/api/fleet/settings" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{
        "fleet_server_hosts": ["https://fleet-server:8220"]
    }' > /dev/null
echo_info "Fleet Server hosts configured!"

# Step 9: Get volume name prefix
VOLUME_PREFIX=$(docker volume ls --format '{{.Name}}' | grep certs | head -1 | sed 's/_certs$//')
echo_info "Using volume prefix: ${VOLUME_PREFIX}"

# Step 10: Start Fleet Server
echo_info "Step 9: Starting Fleet Server..."
docker rm -f fleet-server 2>/dev/null || true

docker run -d \
    --name fleet-server \
    --network elastic \
    --user root \
    -p ${FLEET_PORT}:8220 \
    -v ${VOLUME_PREFIX}_certs:/certs:ro \
    -e FLEET_SERVER_ENABLE=true \
    -e FLEET_SERVER_POLICY_ID=fleet-server-policy \
    -e FLEET_SERVER_ELASTICSEARCH_HOST=https://es01:9200 \
    -e FLEET_SERVER_ELASTICSEARCH_CA=/certs/ca/ca.crt \
    -e FLEET_SERVER_CERT=/certs/fleet-server/fleet-server.crt \
    -e FLEET_SERVER_CERT_KEY=/certs/fleet-server/fleet-server.key \
    -e FLEET_URL=https://fleet-server:8220 \
    -e FLEET_CA=/certs/ca/ca.crt \
    -e KIBANA_FLEET_SETUP=1 \
    -e KIBANA_HOST=http://kibana:5601 \
    -e ELASTICSEARCH_USERNAME=elastic \
    -e ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD} \
    docker.elastic.co/beats/elastic-agent:${STACK_VERSION} > /dev/null

# Step 11: Wait for Fleet Server to be healthy
echo_info "Step 10: Waiting for Fleet Server to be healthy..."
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
