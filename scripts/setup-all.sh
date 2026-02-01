#!/bin/bash
# Master setup script - deploys entire mail server lab
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}✓${NC}"
ARROW="${CYAN}▶${NC}"

clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║${NC}        ${BOLD}${CYAN}Mail Server Lab${NC} - ${DIM}Full Setup${NC}                         ${BOLD}${BLUE}║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${DIM}This will create 4 VMs: DNS server + 3 mail servers (Mars, Venus, Jupiter)${NC}"
echo ""

# Track timing
START_TIME=$(date +%s)

# Helper to show step header
show_step() {
    local STEP_NUM=$1
    local STEP_TITLE=$2
    local STEP_DESC=$3
    echo ""
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${ARROW} ${BOLD}[${STEP_NUM}/6]${NC} ${BOLD}${STEP_TITLE}${NC}"
    echo -e "${DIM}   ${STEP_DESC}${NC}"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Step 1: Check prerequisites
show_step "1" "Checking Prerequisites" "Verifying multipass, network connectivity, and system resources"
"$SCRIPT_DIR/00-check-prerequisites.sh"

# Step 2: Deploy DNS server
show_step "2" "Deploying DNS Server" "Creating BIND9 DNS server for .lab domain resolution"
"$SCRIPT_DIR/01-deploy-dns.sh" <<< "y"

# Step 3: Deploy Mars mail server
show_step "3" "Deploying Mars Mail Server" "Installing Mailcow on mars.lab (10.4.26.11)"
"$SCRIPT_DIR/02-deploy-mars.sh" <<< "y"

# Step 4: Deploy Venus mail server
show_step "4" "Deploying Venus Mail Server" "Installing Mailcow on venus.lab (10.4.26.12)"
"$SCRIPT_DIR/03-deploy-venus.sh" <<< "y"

# Step 5: Deploy Jupiter mail server
show_step "5" "Deploying Jupiter Mail Server" "Installing Mailcow on jupiter.lab (10.4.26.13)"
"$SCRIPT_DIR/04-deploy-jupiter.sh" <<< "y"

# Step 6: Create users
show_step "6" "Creating Mail Users" "Adding alice@ and bob@ accounts to each mail server"
echo -e "  ${DIM}Waiting for services to fully initialize...${NC}"
sleep 30  # Give services time to fully start
"$SCRIPT_DIR/05-create-users.sh"

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

# Show completion info
echo ""
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║${NC}     ${CHECK} ${BOLD}Mail Server Lab is Ready!${NC}                               ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   ${DIM}Setup completed in${NC} ${BOLD}${MINUTES}m ${SECS}s${NC}"
echo ""
echo -e "   ${BOLD}${CYAN}Webmail Access (SOGo):${NC}"
echo -e "   ├── ${YELLOW}Mars:${NC}    https://10.4.26.11/SOGo"
echo -e "   ├── ${YELLOW}Venus:${NC}   https://10.4.26.12/SOGo"
echo -e "   └── ${YELLOW}Jupiter:${NC} https://10.4.26.13/SOGo"
echo ""
echo -e "   ${BOLD}${CYAN}Admin UI (Mailcow):${NC} ${DIM}User: admin | Pass: moohoo${NC}"
echo -e "   ├── ${YELLOW}Mars:${NC}    https://10.4.26.11"
echo -e "   ├── ${YELLOW}Venus:${NC}   https://10.4.26.12"
echo -e "   └── ${YELLOW}Jupiter:${NC} https://10.4.26.13"
echo ""
echo -e "   ${BOLD}${CYAN}Test Accounts:${NC} ${DIM}(available on all servers)${NC}"
echo -e "   ├── ${GREEN}alice@<domain>${NC}  Password: alice123"
echo -e "   └── ${GREEN}bob@<domain>${NC}    Password: bob123"
echo ""
echo -e "   ${DIM}Tip: Run${NC} ${YELLOW}./manager.sh hosts add${NC} ${DIM}to access via domain names${NC}"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════${NC}"
echo ""
