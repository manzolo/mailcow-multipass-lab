#!/bin/bash
# Deploy DNS Server VM
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

echo "============================================"
echo "Deploying DNS Server"
echo "============================================"
echo "Name: $DNS_SERVER_NAME"
echo "IP: $DNS_SERVER_IP"
echo "Hostname: $DNS_SERVER_HOSTNAME"
echo ""

# Check if VM already exists
if multipass list 2>/dev/null | grep -q "^${DNS_SERVER_NAME} "; then
    echo "VM $DNS_SERVER_NAME already exists"
    read -p "Delete and recreate? (y/N): " CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        echo "Deleting existing VM..."
        multipass delete "$DNS_SERVER_NAME" --purge
    else
        echo "Skipping DNS server deployment"
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
echo "Launching DNS server VM..."
multipass launch --name "$DNS_SERVER_NAME" \
    --cpus "$DNS_CPU" \
    --memory "$DNS_RAM" \
    --disk "$DNS_DISK" \
    --cloud-init "$CLOUD_INIT" \
    22.04

rm "$CLOUD_INIT"

# Wait for VM to be ready
echo "Waiting for VM to be ready..."
sleep 30

# Configure static IP
echo "Configuring static IP..."

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
echo "Applying network configuration (with timeout)..."
timeout 30 multipass exec "$DNS_SERVER_NAME" -- sudo netplan apply 2>/dev/null || {
    echo "  Netplan apply timed out or failed, waiting for VM to stabilize..."
}
sleep 10

# Verify VM is still reachable
echo "Verifying VM connectivity..."
for i in {1..6}; do
    if multipass exec "$DNS_SERVER_NAME" -- echo "VM reachable" 2>/dev/null; then
        break
    fi
    echo "  Waiting for VM to respond (attempt $i/6)..."
    sleep 5
done

# Copy BIND configuration files
echo "Copying BIND configuration..."
multipass transfer "$PROJECT_DIR/dns/named.conf.options" "${DNS_SERVER_NAME}:/tmp/named.conf.options"
multipass transfer "$PROJECT_DIR/dns/named.conf.local" "${DNS_SERVER_NAME}:/tmp/named.conf.local"

# Copy zone files
for ZONE_FILE in "$PROJECT_DIR/dns/zones/"*; do
    FILENAME=$(basename "$ZONE_FILE")
    multipass transfer "$ZONE_FILE" "${DNS_SERVER_NAME}:/tmp/${FILENAME}"
done

# Configure BIND
echo "Configuring BIND..."
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
        named-checkzone $zone /etc/bind/zones/db.$zone
    done
    named-checkzone 26.4.10.in-addr.arpa /etc/bind/zones/db.26.4.10.in-addr.arpa

    # Restart BIND
    systemctl restart bind9
    systemctl status bind9 --no-pager
'

# Verify DNS is working
echo ""
echo "Verifying DNS server..."
sleep 5

# Test DNS queries
echo "Testing DNS resolution..."
multipass exec "$DNS_SERVER_NAME" -- dig @127.0.0.1 mars.lab MX +short
multipass exec "$DNS_SERVER_NAME" -- dig @127.0.0.1 mail.venus.lab A +short
multipass exec "$DNS_SERVER_NAME" -- dig @127.0.0.1 -x 10.4.26.11 +short

echo ""
echo "============================================"
echo "DNS Server deployment complete!"
echo "============================================"
echo "IP: $DNS_SERVER_IP"
echo "Test: dig @$DNS_SERVER_IP mars.lab MX"
echo "============================================"
