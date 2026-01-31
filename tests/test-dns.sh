#!/bin/bash
# Test DNS resolution
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DNS_IP="$DNS_SERVER_IP"
PASSED=0
FAILED=0

test_dns() {
    local QUERY="$1"
    local TYPE="$2"
    local EXPECTED="$3"
    local DESC="$4"

    echo -n "  Testing $DESC... "

    # Handle PTR queries specially (dig -x needs unquoted argument)
    if [[ "$TYPE" == "PTR" && "$QUERY" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        RESULT=$(dig @"$DNS_IP" -x "$QUERY" +short 2>/dev/null | head -1)
    else
        RESULT=$(dig @"$DNS_IP" "$QUERY" "$TYPE" +short 2>/dev/null | head -1)
    fi

    if [[ "$RESULT" == *"$EXPECTED"* ]]; then
        echo -e "${GREEN}PASS${NC} ($RESULT)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (expected: $EXPECTED, got: $RESULT)"
        FAILED=$((FAILED + 1))
    fi
}

echo "============================================"
echo "DNS Resolution Tests"
echo "============================================"
echo "DNS Server: $DNS_IP"
echo ""

# Check if DNS server is reachable
echo -n "Checking DNS server reachability... "
if dig @"$DNS_IP" +short +time=5 &>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "DNS server at $DNS_IP is not responding"
    exit 1
fi

echo ""
echo "A Records:"
test_dns "mars.lab" "A" "10.4.26.11" "mars.lab A record"
test_dns "mail.mars.lab" "A" "10.4.26.11" "mail.mars.lab A record"
test_dns "venus.lab" "A" "10.4.26.12" "venus.lab A record"
test_dns "mail.venus.lab" "A" "10.4.26.12" "mail.venus.lab A record"
test_dns "jupiter.lab" "A" "10.4.26.13" "jupiter.lab A record"
test_dns "mail.jupiter.lab" "A" "10.4.26.13" "mail.jupiter.lab A record"

echo ""
echo "MX Records:"
test_dns "mars.lab" "MX" "mail.mars.lab" "mars.lab MX record"
test_dns "venus.lab" "MX" "mail.venus.lab" "venus.lab MX record"
test_dns "jupiter.lab" "MX" "mail.jupiter.lab" "jupiter.lab MX record"

echo ""
echo "PTR Records (Reverse DNS):"
test_dns "10.4.26.11" "PTR" "mail.mars.lab" "10.4.26.11 PTR record"
test_dns "10.4.26.12" "PTR" "mail.venus.lab" "10.4.26.12 PTR record"
test_dns "10.4.26.13" "PTR" "mail.jupiter.lab" "10.4.26.13 PTR record"

echo ""
echo "SPF Records:"
test_dns "mars.lab" "TXT" "v=spf1" "mars.lab SPF record"
test_dns "venus.lab" "TXT" "v=spf1" "venus.lab SPF record"
test_dns "jupiter.lab" "TXT" "v=spf1" "jupiter.lab SPF record"

echo ""
echo "============================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "============================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
