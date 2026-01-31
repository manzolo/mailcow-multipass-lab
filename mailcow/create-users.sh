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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Get API key from mailcow.conf or api_key.txt
API_KEY=$(grep "^API_KEY=" /opt/mailcow-dockerized/mailcow.conf 2>/dev/null | cut -d'=' -f2)
if [ -z "$API_KEY" ]; then
    API_KEY=$(grep "^API_KEY=" /opt/mailcow-dockerized/api_key.txt 2>/dev/null | cut -d'=' -f2)
fi

if [ -z "$API_KEY" ]; then
    log "ERROR: Could not find API key in mailcow.conf or api_key.txt"
    exit 1
fi

# Use HTTPS with self-signed cert
API_URL="https://127.0.0.1/api/v1"
CURL_OPTS="-sk"  # -s silent, -k insecure (allow self-signed)

log "Creating users for domain: $DOMAIN"
log "Using API at: $API_URL"

# Wait for API to be ready
for i in {1..30}; do
    if curl $CURL_OPTS -o /dev/null -w "%{http_code}" "https://127.0.0.1/" | grep -q "200\|301\|302"; then
        log "API is ready"
        break
    fi
    log "Waiting for API... ($i/30)"
    sleep 10
done

# Add domain first
log "Adding domain: $DOMAIN"
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
    }")

log "Domain add result: $DOMAIN_RESULT"

# Create each user
for USER_ENTRY in "${USERS[@]}"; do
    USERNAME="${USER_ENTRY%%:*}"
    PASSWORD="${USER_ENTRY##*:}"
    EMAIL="${USERNAME}@${DOMAIN}"

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
        }")

    log "User $EMAIL result: $USER_RESULT"
done

log ""
log "============================================"
log "Users created for $DOMAIN:"
for USER_ENTRY in "${USERS[@]}"; do
    USERNAME="${USER_ENTRY%%:*}"
    PASSWORD="${USER_ENTRY##*:}"
    log "  - ${USERNAME}@${DOMAIN} (password: ${PASSWORD})"
done
log "============================================"
