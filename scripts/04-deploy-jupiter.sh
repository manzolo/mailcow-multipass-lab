#!/bin/bash
# Deploy Jupiter Mail Server
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

VM_NAME="$JUPITER_NAME"
VM_IP="$JUPITER_IP"
VM_DOMAIN="$JUPITER_DOMAIN"
VM_HOSTNAME="$JUPITER_HOSTNAME"

echo "============================================"
echo "Deploying Mail Server: $VM_NAME"
echo "============================================"
echo "Domain: $VM_DOMAIN"
echo "IP: $VM_IP"
echo "Hostname: $VM_HOSTNAME"
echo ""

# Check if VM already exists
if multipass list 2>/dev/null | grep -q "^${VM_NAME} "; then
    echo "VM $VM_NAME already exists"
    read -p "Delete and recreate? (y/N): " CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        echo "Deleting existing VM..."
        multipass delete "$VM_NAME" --purge
    else
        echo "Skipping $VM_NAME deployment"
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
echo "Launching $VM_NAME VM..."
multipass launch --name "$VM_NAME" \
    --cpus "$MAIL_CPU" \
    --memory "$MAIL_RAM" \
    --disk "$MAIL_DISK" \
    --cloud-init "$CLOUD_INIT" \
    22.04

rm "$CLOUD_INIT"

# Wait for VM to be ready
echo "Waiting for VM to be ready..."
sleep 30

# Configure static IP and hostname
echo "Configuring network and hostname..."

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
echo "Applying network configuration (with timeout)..."
timeout 30 multipass exec "$VM_NAME" -- sudo netplan apply 2>/dev/null || {
    echo "  Netplan apply timed out or failed, waiting for VM to stabilize..."
}
sleep 10

# Verify VM is still reachable
echo "Verifying VM connectivity..."
for i in {1..6}; do
    if multipass exec "$VM_NAME" -- echo "VM reachable" 2>/dev/null; then
        break
    fi
    echo "  Waiting for VM to respond (attempt $i/6)..."
    sleep 5
done

# Copy setup scripts
echo "Copying setup scripts..."
multipass transfer "$PROJECT_DIR/mailcow/mailcow-setup.sh" "${VM_NAME}:/tmp/mailcow-setup.sh"
multipass transfer "$PROJECT_DIR/mailcow/create-users.sh" "${VM_NAME}:/tmp/create-users.sh"

# Make scripts executable and move them
multipass exec "$VM_NAME" -- sudo bash -c '
    chmod +x /tmp/mailcow-setup.sh /tmp/create-users.sh
    mv /tmp/mailcow-setup.sh /root/
    mv /tmp/create-users.sh /root/
'

# Run Mailcow setup
echo ""
echo "Installing Mailcow (this will take several minutes)..."
echo "You can monitor progress with: multipass exec $VM_NAME -- tail -f /var/log/mailcow-setup/setup.log"
echo ""

multipass exec "$VM_NAME" -- sudo /root/mailcow-setup.sh "$VM_DOMAIN" "$VM_IP" "$DNS_SERVER_IP"

echo ""
echo "============================================"
echo "Mail Server $VM_NAME deployment complete!"
echo "============================================"
echo "Domain: $VM_DOMAIN"
echo "IP: $VM_IP"
echo "Webmail: https://$VM_IP/SOGo"
echo "Admin: https://$VM_IP (admin/moohoo)"
echo "============================================"
