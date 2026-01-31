#!/bin/bash
# Test SMTP connectivity
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

test_port() {
    local IP="$1"
    local PORT="$2"
    local DESC="$3"

    echo -n "  Testing $DESC ($IP:$PORT)... "

    if nc -zv -w5 "$IP" "$PORT" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED=$((FAILED + 1))
    fi
}

test_smtp_banner() {
    local IP="$1"
    local DESC="$2"

    echo -n "  Testing $DESC SMTP banner... "

    BANNER=$(echo "QUIT" | nc -w5 "$IP" 25 2>/dev/null | head -1)

    if [[ "$BANNER" == *"220"* ]]; then
        echo -e "${GREEN}PASS${NC} ($BANNER)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (no valid SMTP banner)"
        FAILED=$((FAILED + 1))
    fi
}

echo "============================================"
echo "SMTP Connectivity Tests"
echo "============================================"
echo ""

# Test Mars
echo "Mars (10.4.26.11):"
test_port "$MARS_IP" 25 "SMTP"
test_port "$MARS_IP" 587 "Submission"
test_port "$MARS_IP" 993 "IMAPS"
test_port "$MARS_IP" 443 "HTTPS"
test_smtp_banner "$MARS_IP" "Mars"

echo ""

# Test Venus
echo "Venus (10.4.26.12):"
test_port "$VENUS_IP" 25 "SMTP"
test_port "$VENUS_IP" 587 "Submission"
test_port "$VENUS_IP" 993 "IMAPS"
test_port "$VENUS_IP" 443 "HTTPS"
test_smtp_banner "$VENUS_IP" "Venus"

echo ""

# Test Jupiter
echo "Jupiter (10.4.26.13):"
test_port "$JUPITER_IP" 25 "SMTP"
test_port "$JUPITER_IP" 587 "Submission"
test_port "$JUPITER_IP" 993 "IMAPS"
test_port "$JUPITER_IP" 443 "HTTPS"
test_smtp_banner "$JUPITER_IP" "Jupiter"

echo ""
echo "============================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "============================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
