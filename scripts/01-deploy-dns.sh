#!/bin/bash
# Deploy DNS Server VM
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}✓${NC}"
ARROW="${CYAN}→${NC}"

step() { echo -e "  ${ARROW} $1"; }
step_done() { echo -e "  ${CHECK} $1"; }

echo -e "${BOLD}Deploying DNS Server: ${YELLOW}$DNS_SERVER_NAME${NC}"
echo -e "${DIM}  IP: $DNS_SERVER_IP | Hostname: $DNS_SERVER_HOSTNAME${NC}"
echo ""

# Check if VM already exists
if multipass list 2>/dev/null | grep -q "^${DNS_SERVER_NAME} "; then
    echo -e "  ${YELLOW}⚠${NC} VM $DNS_SERVER_NAME already exists"
    read -p "  Delete and recreate? (y/N): " CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        step "Deleting existing VM..."
        multipass delete "$DNS_SERVER_NAME" --purge
        step_done "Old VM removed"
    else
        echo -e "  ${DIM}Skipping DNS server deployment${NC}"
        exit 0
    fi
fi

# Create cloud-init with static IP (in project dir for snap access)
CLOUD_INIT="$PROJECT_DIR/.cloud-init-dns.yaml"
cat > "$CLOUD_INIT" << 'CLOUD_INIT_EOF'
#cloud-config
package_update: true
package_upgrade: false

packages:
  - bind9
  - bind9utils
  - dnsutils

runcmd:
  - mkdir -p /var/log/named
  - chown bind:bind /var/log/named
  - mkdir -p /etc/bind/zones
  - systemctl enable bind9
CLOUD_INIT_EOF

# Launch VM
step "Creating VM (${DNS_CPU} CPU, ${DNS_RAM} RAM, ${DNS_DISK} disk)..."
multipass launch --name "$DNS_SERVER_NAME" \
    --cpus "$DNS_CPU" \
    --memory "$DNS_RAM" \
    --disk "$DNS_DISK" \
    --cloud-init "$CLOUD_INIT" \
    22.04 2>&1 | while read line; do echo -e "    ${DIM}$line${NC}"; done

rm "$CLOUD_INIT"
step_done "VM created"

# Wait for VM to be ready
step "Waiting for VM initialization..."
sleep 30
step_done "VM ready"

# Configure static IP
step "Configuring network (static IP: $DNS_SERVER_IP)..."

# Create netplan config file with correct permissions
multipass exec "$DNS_SERVER_NAME" -- sudo bash -c "cat > /etc/netplan/99-static.yaml << NETPLAN
network:
  version: 2
  ethernets:
    default:
      match:
        name: e*
      dhcp4: true
      addresses:
        - ${DNS_SERVER_IP}/24
NETPLAN"

# Fix permissions (netplan requires 600)
multipass exec "$DNS_SERVER_NAME" -- sudo chmod 600 /etc/netplan/99-static.yaml

# Apply netplan with timeout to avoid blocking
timeout 30 multipass exec "$DNS_SERVER_NAME" -- sudo netplan apply 2>/dev/null || {
    echo -e "    ${DIM}Netplan apply timed out, waiting for VM to stabilize...${NC}"
}
sleep 10

# Verify VM is still reachable
for i in {1..6}; do
    if multipass exec "$DNS_SERVER_NAME" -- echo "ok" 2>/dev/null >/dev/null; then
        break
    fi
    echo -e "    ${DIM}Waiting for VM to respond (attempt $i/6)...${NC}"
    sleep 5
done
step_done "Network configured"

# Copy BIND configuration files
step "Transferring BIND configuration..."
multipass transfer "$PROJECT_DIR/dns/named.conf.options" "${DNS_SERVER_NAME}:/tmp/named.conf.options"
multipass transfer "$PROJECT_DIR/dns/named.conf.local" "${DNS_SERVER_NAME}:/tmp/named.conf.local"

# Copy zone files
for ZONE_FILE in "$PROJECT_DIR/dns/zones/"*; do
    FILENAME=$(basename "$ZONE_FILE")
    multipass transfer "$ZONE_FILE" "${DNS_SERVER_NAME}:/tmp/${FILENAME}"
done
step_done "Configuration files transferred"

# Configure BIND
step "Configuring BIND DNS server..."
multipass exec "$DNS_SERVER_NAME" -- sudo bash -c '
    # Move config files
    cp /tmp/named.conf.options /etc/bind/named.conf.options
    cp /tmp/named.conf.local /etc/bind/named.conf.local

    # Move zone files
    mv /tmp/db.* /etc/bind/zones/

    # Set permissions
    chown -R bind:bind /etc/bind/zones
    chmod 644 /etc/bind/zones/*

    # Check configuration
    named-checkconf

    # Check zones
    for zone in mars.lab venus.lab jupiter.lab; do
        named-checkzone $zone /etc/bind/zones/db.$zone >/dev/null
    done
    named-checkzone 26.4.10.in-addr.arpa /etc/bind/zones/db.26.4.10.in-addr.arpa >/dev/null

    # Restart BIND
    systemctl restart bind9
' 2>/dev/null
step_done "BIND configured and started"

# Verify DNS is working
step "Verifying DNS resolution..."
sleep 5

# Test DNS queries silently
MX_RESULT=$(multipass exec "$DNS_SERVER_NAME" -- dig @127.0.0.1 mars.lab MX +short 2>/dev/null)
A_RESULT=$(multipass exec "$DNS_SERVER_NAME" -- dig @127.0.0.1 mail.venus.lab A +short 2>/dev/null)

if [ -n "$MX_RESULT" ] && [ -n "$A_RESULT" ]; then
    step_done "DNS resolution working"
else
    echo -e "  ${YELLOW}⚠${NC} DNS resolution test returned empty results"
fi

echo ""
step_done "${BOLD}DNS Server deployment complete${NC}"
echo -e "  ${DIM}Test: dig @$DNS_SERVER_IP mars.lab MX${NC}"
