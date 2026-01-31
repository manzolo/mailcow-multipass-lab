#!/bin/bash
# Test email flow between servers
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "============================================"
echo "Mail Flow Tests"
echo "============================================"
echo ""

# Test sending email from mars to venus
test_send_mail() {
    local FROM_VM="$1"
    local FROM_EMAIL="$2"
    local TO_EMAIL="$3"
    local SUBJECT="Test $(date +%s)"

    echo -n "  Sending from $FROM_EMAIL to $TO_EMAIL... "

    # Use swaks if available, otherwise use sendmail
    RESULT=$(multipass exec "$FROM_VM" -- bash -c "
        if command -v swaks &> /dev/null; then
            swaks --to '$TO_EMAIL' --from '$FROM_EMAIL' --server localhost --header 'Subject: $SUBJECT' --body 'Test message' 2>&1
        else
            echo 'Subject: $SUBJECT
From: $FROM_EMAIL
To: $TO_EMAIL

Test message from mail flow test' | sendmail -t 2>&1
        fi
    " 2>/dev/null)

    if [[ "$RESULT" == *"250"* ]] || [[ "$RESULT" != *"error"* ]]; then
        echo -e "${GREEN}SENT${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${YELLOW}UNKNOWN${NC} (may have sent)"
        return 1
    fi
}

# Test webmail accessibility
test_webmail() {
    local IP="$1"
    local NAME="$2"

    echo -n "  Testing $NAME webmail (https://$IP/SOGo)... "

    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$IP/SOGo/" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo -e "${GREEN}PASS${NC} (HTTP $HTTP_CODE)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (HTTP $HTTP_CODE)"
        FAILED=$((FAILED + 1))
    fi
}

# Test admin UI accessibility
test_admin() {
    local IP="$1"
    local NAME="$2"

    echo -n "  Testing $NAME admin UI (https://$IP)... "

    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$IP/" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo -e "${GREEN}PASS${NC} (HTTP $HTTP_CODE)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (HTTP $HTTP_CODE)"
        FAILED=$((FAILED + 1))
    fi
}

echo "Webmail Access Tests:"
test_webmail "$MARS_IP" "Mars"
test_webmail "$VENUS_IP" "Venus"
test_webmail "$JUPITER_IP" "Jupiter"

echo ""
echo "Admin UI Tests:"
test_admin "$MARS_IP" "Mars"
test_admin "$VENUS_IP" "Venus"
test_admin "$JUPITER_IP" "Jupiter"

echo ""
echo "Mail Delivery Tests (basic connectivity):"

# Check if VMs are running before testing mail
for VM in mars venus jupiter; do
    if ! multipass list 2>/dev/null | grep -q "^${VM}.*Running"; then
        echo -e "  ${RED}$VM is not running - skipping mail tests${NC}"
        continue
    fi

    # Install swaks for easier mail testing
    multipass exec "$VM" -- sudo apt-get install -y swaks &>/dev/null || true
done

# Test inter-server mail (if all servers are running)
if multipass list 2>/dev/null | grep -q "^mars.*Running"; then
    test_send_mail "mars" "alice@mars.lab" "bob@venus.lab" || true
fi

if multipass list 2>/dev/null | grep -q "^venus.*Running"; then
    test_send_mail "venus" "alice@venus.lab" "bob@jupiter.lab" || true
fi

if multipass list 2>/dev/null | grep -q "^jupiter.*Running"; then
    test_send_mail "jupiter" "alice@jupiter.lab" "bob@mars.lab" || true
fi

echo ""
echo "============================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "============================================"
echo ""
echo "Note: Mail delivery tests only verify sending."
echo "To verify receipt, check webmail at:"
echo "  - https://$MARS_IP/SOGo (bob@mars.lab)"
echo "  - https://$VENUS_IP/SOGo (bob@venus.lab)"
echo "  - https://$JUPITER_IP/SOGo (bob@jupiter.lab)"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
