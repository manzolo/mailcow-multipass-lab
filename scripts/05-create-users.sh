#!/bin/bash
# Create mail users on all mail servers
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config/network.env"

echo "============================================"
echo "Creating Mail Users"
echo "============================================"
echo ""

# Define servers
declare -A SERVERS
SERVERS["mars"]="$MARS_DOMAIN:$MARS_IP"
SERVERS["venus"]="$VENUS_DOMAIN:$VENUS_IP"
SERVERS["jupiter"]="$JUPITER_DOMAIN:$JUPITER_IP"

for VM_NAME in mars venus jupiter; do
    IFS=':' read -r DOMAIN IP <<< "${SERVERS[$VM_NAME]}"

    echo "Creating users on $VM_NAME ($DOMAIN)..."

    # Check if VM is running
    if ! multipass list 2>/dev/null | grep -q "^${VM_NAME}.*Running"; then
        echo "WARNING: $VM_NAME is not running, skipping..."
        continue
    fi

    # Run user creation script
    multipass exec "$VM_NAME" -- sudo /root/create-users.sh "$DOMAIN" "$IP" || {
        echo "WARNING: User creation on $VM_NAME may have partially failed"
    }

    echo ""
done

echo "============================================"
echo "User Creation Complete"
echo "============================================"
echo ""
echo "Created accounts on all domains:"
echo "  - alice@mars.lab     (password: alice123)"
echo "  - bob@mars.lab       (password: bob123)"
echo "  - alice@venus.lab    (password: alice123)"
echo "  - bob@venus.lab      (password: bob123)"
echo "  - alice@jupiter.lab  (password: alice123)"
echo "  - bob@jupiter.lab    (password: bob123)"
echo ""
