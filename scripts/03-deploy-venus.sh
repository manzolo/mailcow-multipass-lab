#!/bin/bash
# Deploy Venus Mail Server
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

VM_NAME="$VENUS_NAME"
VM_IP="$VENUS_IP"
VM_DOMAIN="$VENUS_DOMAIN"
VM_HOSTNAME="$VENUS_HOSTNAME"

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

echo -e "${BOLD}Deploying Mail Server: ${YELLOW}$VM_NAME${NC}"
echo -e "${DIM}  Domain: $VM_DOMAIN | IP: $VM_IP${NC}"
echo ""

# Check if VM already exists
if multipass list 2>/dev/null | grep -q "^${VM_NAME} "; then
    echo -e "  ${YELLOW}⚠${NC} VM $VM_NAME already exists"
    read -p "  Delete and recreate? (y/N): " CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        step "Deleting existing VM..."
        multipass delete "$VM_NAME" --purge
        step_done "Old VM removed"
    else
        echo -e "  ${DIM}Skipping $VM_NAME deployment${NC}"
        exit 0
    fi
fi

# Create cloud-init (in project dir for snap access)
CLOUD_INIT="$PROJECT_DIR/.cloud-init-${VM_NAME}.yaml"
cat > "$CLOUD_INIT" << 'CLOUD_INIT_EOF'
#cloud-config
package_update: true
package_upgrade: false

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - git
  - jq

runcmd:
  - mkdir -p /var/log/mailcow-setup
  - echo "initialized" > /var/log/mailcow-setup/status
CLOUD_INIT_EOF

# Launch VM
step "Creating VM (${MAIL_CPU} CPU, ${MAIL_RAM} RAM, ${MAIL_DISK} disk)..."
multipass launch --name "$VM_NAME" \
    --cpus "$MAIL_CPU" \
    --memory "$MAIL_RAM" \
    --disk "$MAIL_DISK" \
    --cloud-init "$CLOUD_INIT" \
    22.04 2>&1 | while read line; do echo -e "    ${DIM}$line${NC}"; done

rm "$CLOUD_INIT"
step_done "VM created"

# Wait for VM to be ready
step "Waiting for VM initialization..."
sleep 30
step_done "VM ready"

# Configure static IP and hostname
step "Configuring network (static IP: $VM_IP)..."

# Create netplan config - keep DHCP for stability, add static IP
multipass exec "$VM_NAME" -- sudo bash -c "cat > /etc/netplan/99-static.yaml << NETPLAN
network:
  version: 2
  ethernets:
    default:
      match:
        name: e*
      dhcp4: true
      addresses:
        - ${VM_IP}/24
      nameservers:
        addresses:
          - ${DNS_SERVER_IP}
          - 8.8.8.8
NETPLAN"

# Fix permissions (netplan requires 600)
multipass exec "$VM_NAME" -- sudo chmod 600 /etc/netplan/99-static.yaml

# Set hostname
multipass exec "$VM_NAME" -- sudo hostnamectl set-hostname "$VM_HOSTNAME"
multipass exec "$VM_NAME" -- sudo bash -c "echo '${VM_IP} ${VM_HOSTNAME} mail' >> /etc/hosts"

# Apply netplan with timeout to avoid blocking
timeout 30 multipass exec "$VM_NAME" -- sudo netplan apply 2>/dev/null || {
    echo -e "    ${DIM}Netplan apply timed out, waiting for VM to stabilize...${NC}"
}
sleep 10

# Verify VM is still reachable
for i in {1..6}; do
    if multipass exec "$VM_NAME" -- echo "ok" 2>/dev/null >/dev/null; then
        break
    fi
    echo -e "    ${DIM}Waiting for VM to respond (attempt $i/6)...${NC}"
    sleep 5
done
step_done "Network configured"

# Copy setup scripts
step "Transferring setup scripts..."
multipass transfer "$PROJECT_DIR/mailcow/mailcow-setup.sh" "${VM_NAME}:/tmp/mailcow-setup.sh"
multipass transfer "$PROJECT_DIR/mailcow/create-users.sh" "${VM_NAME}:/tmp/create-users.sh"

# Make scripts executable and move them
multipass exec "$VM_NAME" -- sudo bash -c '
    chmod +x /tmp/mailcow-setup.sh /tmp/create-users.sh
    mv /tmp/mailcow-setup.sh /root/
    mv /tmp/create-users.sh /root/
'
step_done "Scripts transferred"

# Run Mailcow setup
echo ""
echo -e "${BOLD}Installing Mailcow on $VM_NAME...${NC}"
echo -e "${DIM}  Monitor: multipass exec $VM_NAME -- tail -f /var/log/mailcow-setup/setup.log${NC}"
echo ""

multipass exec "$VM_NAME" -- sudo /root/mailcow-setup.sh "$VM_DOMAIN" "$VM_IP" "$DNS_SERVER_IP"

echo ""
step_done "${BOLD}$VM_NAME deployment complete${NC}"
