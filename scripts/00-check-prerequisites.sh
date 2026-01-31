#!/bin/bash
# Check prerequisites for mail server lab
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/network.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Checking prerequisites..."
echo ""

ERRORS=0

# Check multipass
echo -n "Checking multipass... "
if command -v multipass &> /dev/null; then
    VERSION=$(multipass version | head -1)
    echo -e "${GREEN}OK${NC} ($VERSION)"
else
    echo -e "${RED}MISSING${NC}"
    echo "  Install: snap install multipass"
    ERRORS=$((ERRORS + 1))
fi

# Check if multipass daemon is running
echo -n "Checking multipass daemon... "
if multipass list &> /dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}NOT RUNNING${NC}"
    echo "  Try: sudo snap restart multipass"
    ERRORS=$((ERRORS + 1))
fi

# Check available disk space (3x10GB mail + 5GB DNS = 35GB, recommend 40GB)
echo -n "Checking disk space... "
AVAILABLE_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
REQUIRED_GB=40
if [ "$AVAILABLE_GB" -ge "$REQUIRED_GB" ]; then
    echo -e "${GREEN}OK${NC} (${AVAILABLE_GB}GB available, ${REQUIRED_GB}GB required)"
else
    echo -e "${YELLOW}WARNING${NC} (${AVAILABLE_GB}GB available, ${REQUIRED_GB}GB recommended)"
fi

# Check available memory (3x2GB mail + 512MB DNS = 6.5GB, recommend 7GB)
echo -n "Checking available memory... "
AVAILABLE_MB=$(free -m | awk 'NR==2 {print $7}')
REQUIRED_MB=7000
if [ "$AVAILABLE_MB" -ge "$REQUIRED_MB" ]; then
    echo -e "${GREEN}OK${NC} (${AVAILABLE_MB}MB available, ${REQUIRED_MB}MB required)"
else
    echo -e "${YELLOW}WARNING${NC} (${AVAILABLE_MB}MB available, ${REQUIRED_MB}MB recommended)"
    echo "  The lab requires ~6.5GB RAM total for all VMs"
fi

# Check if VMs already exist
echo -n "Checking for existing VMs... "
EXISTING_VMS=""
for VM in dns-server mars venus jupiter; do
    if multipass list 2>/dev/null | grep -q "^$VM "; then
        EXISTING_VMS="$EXISTING_VMS $VM"
    fi
done

if [ -z "$EXISTING_VMS" ]; then
    echo -e "${GREEN}OK${NC} (no conflicts)"
else
    echo -e "${YELLOW}WARNING${NC}"
    echo "  Existing VMs found:$EXISTING_VMS"
    echo "  Run './manager.sh destroy' first if you want a fresh setup"
fi

# Check network bridge
echo -n "Checking network... "
if ip link show mpqemubr0 &> /dev/null; then
    echo -e "${GREEN}OK${NC} (mpqemubr0 bridge found)"
else
    echo -e "${YELLOW}INFO${NC} (mpqemubr0 will be created by multipass)"
fi

# Check for port conflicts
echo -n "Checking port availability... "
PORTS_IN_USE=""
for PORT in 25 80 443 587 993; do
    if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
        PORTS_IN_USE="$PORTS_IN_USE $PORT"
    fi
done

if [ -z "$PORTS_IN_USE" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}INFO${NC}"
    echo "  Ports in use on host:$PORTS_IN_USE"
    echo "  This is OK - VMs use their own IPs"
fi

echo ""
echo "============================================"
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}Prerequisites check failed with $ERRORS error(s)${NC}"
    exit 1
else
    echo -e "${GREEN}All prerequisites met!${NC}"
    exit 0
fi
