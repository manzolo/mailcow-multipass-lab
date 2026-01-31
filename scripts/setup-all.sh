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
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Mail Server Lab - Full Setup                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Track timing
START_TIME=$(date +%s)

# Step 1: Check prerequisites
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"
"$SCRIPT_DIR/00-check-prerequisites.sh"
echo ""

# Step 2: Deploy DNS server
echo -e "${YELLOW}[2/6] Deploying DNS server...${NC}"
"$SCRIPT_DIR/01-deploy-dns.sh" <<< "y"
echo ""

# Step 3: Deploy Mars mail server
echo -e "${YELLOW}[3/6] Deploying Mars mail server...${NC}"
"$SCRIPT_DIR/02-deploy-mars.sh" <<< "y"
echo ""

# Step 4: Deploy Venus mail server
echo -e "${YELLOW}[4/6] Deploying Venus mail server...${NC}"
"$SCRIPT_DIR/03-deploy-venus.sh" <<< "y"
echo ""

# Step 5: Deploy Jupiter mail server
echo -e "${YELLOW}[5/6] Deploying Jupiter mail server...${NC}"
"$SCRIPT_DIR/04-deploy-jupiter.sh" <<< "y"
echo ""

# Step 6: Create users
echo -e "${YELLOW}[6/6] Creating mail users...${NC}"
sleep 30  # Give services time to fully start
"$SCRIPT_DIR/05-create-users.sh"
echo ""

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

# Show completion info
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║               Mail Server Lab is Ready!                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "   Setup completed in ${MINUTES}m ${SECONDS}s"
echo ""
echo "   Webmail Access (SOGo):"
echo "   ├── Mars:    https://10.4.26.11/SOGo  (or https://mail.mars.lab/SOGo)"
echo "   ├── Venus:   https://10.4.26.12/SOGo  (or https://mail.venus.lab/SOGo)"
echo "   └── Jupiter: https://10.4.26.13/SOGo  (or https://mail.jupiter.lab/SOGo)"
echo ""
echo "   Admin UI (Mailcow):"
echo "   ├── Mars:    https://10.4.26.11       User: admin  Pass: moohoo"
echo "   ├── Venus:   https://10.4.26.12       User: admin  Pass: moohoo"
echo "   └── Jupiter: https://10.4.26.13       User: admin  Pass: moohoo"
echo ""
echo "   Test Accounts:"
echo "   ├── alice@mars.lab     Password: alice123"
echo "   ├── bob@mars.lab       Password: bob123"
echo "   ├── alice@venus.lab    Password: alice123"
echo "   ├── bob@venus.lab      Password: bob123"
echo "   ├── alice@jupiter.lab  Password: alice123"
echo "   └── bob@jupiter.lab    Password: bob123"
echo ""
echo "   Run './manager.sh hosts add' to access via domain names"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
