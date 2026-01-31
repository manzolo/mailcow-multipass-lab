#!/bin/bash
# Teardown script - removes all mail server lab VMs
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VMS=("dns-server" "mars" "venus" "jupiter")

echo -e "${YELLOW}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Mail Server Lab - Teardown                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "This will delete the following VMs:"
for VM in "${VMS[@]}"; do
    if multipass list 2>/dev/null | grep -q "^${VM} "; then
        echo "  - $VM (exists)"
    else
        echo "  - $VM (not found)"
    fi
done
echo ""

read -p "Are you sure you want to delete all VMs? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Deleting VMs..."

for VM in "${VMS[@]}"; do
    if multipass list 2>/dev/null | grep -q "^${VM} "; then
        echo "  Deleting $VM..."
        multipass delete "$VM" 2>/dev/null || true
    fi
done

echo ""
echo "Purging deleted VMs..."
multipass purge

echo ""
echo -e "${GREEN}Teardown complete!${NC}"
echo ""
echo "All mail server lab VMs have been removed."
echo ""
echo "To also clean up /etc/hosts entries, run:"
echo "  ./manager.sh hosts remove"
