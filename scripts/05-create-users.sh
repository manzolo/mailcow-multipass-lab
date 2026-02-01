#!/bin/bash
# Create mail users on all mail servers
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"
ARROW="${CYAN}→${NC}"

# Define servers
declare -A SERVERS
SERVERS["mars"]="$MARS_DOMAIN:$MARS_IP"
SERVERS["venus"]="$VENUS_DOMAIN:$VENUS_IP"
SERVERS["jupiter"]="$JUPITER_DOMAIN:$JUPITER_IP"

TOTAL_SUCCESS=0
TOTAL_FAILED=0

for VM_NAME in mars venus jupiter; do
    IFS=':' read -r DOMAIN IP <<< "${SERVERS[$VM_NAME]}"

    echo -e "  ${ARROW} ${BOLD}${VM_NAME}${NC} ${DIM}(${DOMAIN})${NC}"

    # Check if VM is running
    if ! multipass list 2>/dev/null | grep -q "^${VM_NAME}.*Running"; then
        echo -e "    ${WARN} VM not running, skipping"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        continue
    fi

    # Run user creation script
    if multipass exec "$VM_NAME" -- sudo /root/create-users.sh "$DOMAIN" "$IP" 2>/dev/null; then
        TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    else
        echo -e "    ${WARN} User creation may have partially failed"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi

    echo ""
done

# Summary
echo -e "  ${CHECK} ${BOLD}User creation complete${NC}"
echo ""
echo -e "  ${DIM}Created accounts:${NC}"
echo -e "    ${GREEN}alice@${NC}mars.lab, venus.lab, jupiter.lab ${DIM}(pass: alice123)${NC}"
echo -e "    ${GREEN}bob@${NC}mars.lab, venus.lab, jupiter.lab ${DIM}(pass: bob123)${NC}"
