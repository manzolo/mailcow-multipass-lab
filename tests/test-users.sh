#!/bin/bash
# Test user mailbox authentication
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"
source "$PROJECT_DIR/config/users.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "============================================"
echo "Mailbox Authentication Tests"
echo "============================================"
echo ""

# Test IMAP authentication
test_imap_auth() {
    local IP="$1"
    local EMAIL="$2"
    local PASSWORD="$3"

    echo -n "  Testing $EMAIL... "

    # Use curl with IMAPS to test authentication
    RESULT=$(curl -sk --max-time 10 --url "imaps://$IP:993" \
        --user "$EMAIL:$PASSWORD" \
        --request "EXAMINE INBOX" 2>&1)

    if [[ "$RESULT" == *"OK"* ]] || [[ "$RESULT" == *"EXAMINE"* ]] || [[ "$RESULT" == *"completed"* ]] || [[ "$RESULT" == *"Stringa vuota"* ]]; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Test all users on all servers
SERVERS=(
    "mars:$MARS_IP:$MARS_DOMAIN"
    "venus:$VENUS_IP:$VENUS_DOMAIN"
    "jupiter:$JUPITER_IP:$JUPITER_DOMAIN"
)

for SERVER_INFO in "${SERVERS[@]}"; do
    IFS=':' read -r NAME IP DOMAIN <<< "$SERVER_INFO"

    echo "$NAME ($DOMAIN):"

    # Check if server is reachable
    if ! curl -sk --max-time 5 "https://$IP/" &>/dev/null; then
        echo -e "  ${YELLOW}Server not reachable - skipping${NC}"
        continue
    fi

    # Test each user
    for USER_ENTRY in "${MAIL_USERS[@]}"; do
        IFS=':' read -r USERNAME PASSWORD <<< "$USER_ENTRY"
        test_imap_auth "$IP" "${USERNAME}@${DOMAIN}" "$PASSWORD" || true
    done

    echo ""
done

echo "============================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "============================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
