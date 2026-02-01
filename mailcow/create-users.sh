#!/bin/bash
# Create mail users via Mailcow API
set -e

DOMAIN="${1:?Domain required}"
IP="${2:?IP required}"

# Users to create (username:password)
USERS=(
    "alice:alice123"
    "bob:bob123"
)

LOG_FILE="/var/log/mailcow-setup/users.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

step() {
    echo -e "    ${ARROW} $1"
    log "$1"
}

step_done() {
    echo -e "    ${CHECK} $1"
    log "Done: $1"
}

step_fail() {
    echo -e "    ${CROSS} $1"
    log "FAILED: $1"
}

# Get API key from mailcow.conf or api_key.txt
API_KEY=$(grep "^API_KEY=" /opt/mailcow-dockerized/mailcow.conf 2>/dev/null | cut -d'=' -f2)
if [ -z "$API_KEY" ]; then
    API_KEY=$(grep "^API_KEY=" /opt/mailcow-dockerized/api_key.txt 2>/dev/null | cut -d'=' -f2)
fi

if [ -z "$API_KEY" ]; then
    step_fail "Could not find API key"
    exit 1
fi

# Use HTTPS with self-signed cert
API_URL="https://127.0.0.1/api/v1"
CURL_OPTS="-sk"  # -s silent, -k insecure (allow self-signed)

log "Creating users for domain: $DOMAIN"
log "Using API at: $API_URL"

# Wait for API to be ready
step "Waiting for API..."
API_READY=false
for i in {1..30}; do
    if curl $CURL_OPTS -o /dev/null -w "%{http_code}" "https://127.0.0.1/" 2>/dev/null | grep -q "200\|301\|302"; then
        API_READY=true
        break
    fi
    log "Waiting for API... ($i/30)"
    sleep 10
done

if [ "$API_READY" = true ]; then
    step_done "API ready"
else
    step_fail "API not responding"
    exit 1
fi

# Add domain first
step "Adding domain ${DOMAIN}..."
DOMAIN_RESULT=$(curl $CURL_OPTS -X POST "${API_URL}/add/domain" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${API_KEY}" \
    -d "{
        \"domain\": \"${DOMAIN}\",
        \"description\": \"Mail domain ${DOMAIN}\",
        \"aliases\": 100,
        \"mailboxes\": 100,
        \"defquota\": 1024,
        \"maxquota\": 10240,
        \"quota\": 10240,
        \"active\": 1,
        \"rl_value\": 10,
        \"rl_frame\": \"s\",
        \"backupmx\": 0,
        \"relay_all_recipients\": 0,
        \"restart_sogo\": 1
    }" 2>/dev/null)

log "Domain add result: $DOMAIN_RESULT"

if echo "$DOMAIN_RESULT" | grep -q '"type":"success"'; then
    step_done "Domain ${DOMAIN} added"
elif echo "$DOMAIN_RESULT" | grep -q "domain_exists"; then
    step_done "Domain ${DOMAIN} already exists"
else
    step_fail "Failed to add domain ${DOMAIN}"
    log "Error: $DOMAIN_RESULT"
fi

# Create each user
CREATED_USERS=()
for USER_ENTRY in "${USERS[@]}"; do
    USERNAME="${USER_ENTRY%%:*}"
    PASSWORD="${USER_ENTRY##*:}"
    EMAIL="${USERNAME}@${DOMAIN}"

    step "Creating user ${EMAIL}..."
    log "Creating user: $EMAIL"

    USER_RESULT=$(curl $CURL_OPTS -X POST "${API_URL}/add/mailbox" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY}" \
        -d "{
            \"local_part\": \"${USERNAME}\",
            \"domain\": \"${DOMAIN}\",
            \"name\": \"${USERNAME^}\",
            \"password\": \"${PASSWORD}\",
            \"password2\": \"${PASSWORD}\",
            \"quota\": 1024,
            \"active\": 1,
            \"force_pw_update\": 0,
            \"tls_enforce_in\": 0,
            \"tls_enforce_out\": 0
        }" 2>/dev/null)

    log "User $EMAIL result: $USER_RESULT"

    if echo "$USER_RESULT" | grep -q '"type":"success"'; then
        step_done "${EMAIL} created"
        CREATED_USERS+=("$EMAIL")
    elif echo "$USER_RESULT" | grep -q "object_exists"; then
        step_done "${EMAIL} already exists"
        CREATED_USERS+=("$EMAIL")
    else
        step_fail "Failed to create ${EMAIL}"
        log "Error: $USER_RESULT"
    fi
done

log "Users created for $DOMAIN: ${CREATED_USERS[*]}"
