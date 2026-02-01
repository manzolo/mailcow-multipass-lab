#!/bin/bash
# Check prerequisites for mail server lab
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/network.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"
INFO="${CYAN}ℹ${NC}"

ERRORS=0

check_item() {
    echo -ne "  ${CYAN}→${NC} $1... "
}

# Check multipass
check_item "Multipass installation"
if command -v multipass &> /dev/null; then
    VERSION=$(multipass version 2>/dev/null | head -1 | awk '{print $2}')
    echo -e "${CHECK} ${DIM}v${VERSION}${NC}"
else
    echo -e "${CROSS} Missing"
    echo -e "    ${DIM}Install: snap install multipass${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check if multipass daemon is running
check_item "Multipass daemon"
if multipass list &> /dev/null; then
    echo -e "${CHECK}"
else
    echo -e "${CROSS} Not running"
    echo -e "    ${DIM}Try: sudo snap restart multipass${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check available disk space (3x10GB mail + 5GB DNS = 35GB, recommend 40GB)
check_item "Disk space"
AVAILABLE_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
REQUIRED_GB=40
if [ "$AVAILABLE_GB" -ge "$REQUIRED_GB" ]; then
    echo -e "${CHECK} ${DIM}${AVAILABLE_GB}GB available${NC}"
else
    echo -e "${WARN} ${DIM}${AVAILABLE_GB}GB available (${REQUIRED_GB}GB recommended)${NC}"
fi

# Check available memory (3x2GB mail + 512MB DNS = 6.5GB, recommend 7GB)
check_item "Available memory"
AVAILABLE_MB=$(free -m | awk 'NR==2 {print $7}')
REQUIRED_MB=7000
if [ "$AVAILABLE_MB" -ge "$REQUIRED_MB" ]; then
    echo -e "${CHECK} ${DIM}${AVAILABLE_MB}MB available${NC}"
else
    echo -e "${WARN} ${DIM}${AVAILABLE_MB}MB available (${REQUIRED_MB}MB recommended)${NC}"
fi

# Check if VMs already exist
check_item "Existing VMs"
EXISTING_VMS=""
for VM in dns-server mars venus jupiter; do
    if multipass list 2>/dev/null | grep -q "^$VM "; then
        EXISTING_VMS="$EXISTING_VMS $VM"
    fi
done

if [ -z "$EXISTING_VMS" ]; then
    echo -e "${CHECK} ${DIM}No conflicts${NC}"
else
    echo -e "${WARN} ${DIM}Found:${EXISTING_VMS}${NC}"
    echo -e "    ${DIM}Run './manager.sh destroy' first for a fresh setup${NC}"
fi

# Check network bridge
check_item "Network bridge"
if ip link show mpqemubr0 &> /dev/null; then
    echo -e "${CHECK} ${DIM}mpqemubr0 found${NC}"
else
    echo -e "${INFO} ${DIM}Will be created by multipass${NC}"
fi

# Check for port conflicts
check_item "Port availability"
PORTS_IN_USE=""
for PORT in 25 80 443 587 993; do
    if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
        PORTS_IN_USE="$PORTS_IN_USE $PORT"
    fi
done

if [ -z "$PORTS_IN_USE" ]; then
    echo -e "${CHECK}"
else
    echo -e "${INFO} ${DIM}Host ports in use:${PORTS_IN_USE} (OK - VMs use own IPs)${NC}"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
    echo -e "  ${CROSS} Prerequisites check failed with $ERRORS error(s)"
    exit 1
else
    echo -e "  ${CHECK} All prerequisites met"
fi
