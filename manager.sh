#!/bin/bash
# manager.sh - Mail Server Lab Management CLI
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/network.env" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# VM list
VMS=("dns-server" "mars" "venus" "jupiter")
MAIL_VMS=("mars" "venus" "jupiter")

# Hosts file markers
HOSTS_BEGIN="# Mail Server Lab - BEGIN"
HOSTS_END="# Mail Server Lab - END"

usage() {
    echo -e "${CYAN}Mail Server Lab Manager${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo -e "${YELLOW}Lifecycle Commands:${NC}"
    echo "  setup              Full setup (create VMs, configure, deploy)"
    echo "  start [vm]         Start all VMs or specific VM"
    echo "  stop [vm]          Stop all VMs or specific VM"
    echo "  restart [vm]       Restart all VMs or specific VM"
    echo "  destroy            Remove all VMs"
    echo ""
    echo -e "${YELLOW}Status Commands:${NC}"
    echo "  status             Show status of all VMs and services"
    echo "  info               Show access URLs and credentials"
    echo "  logs <vm>          Show logs for VM (dns-server|mars|venus|jupiter)"
    echo "  shell <vm>         Open shell in VM"
    echo ""
    echo -e "${YELLOW}Testing Commands:${NC}"
    echo "  test               Run all tests (DNS, SMTP, mail flow)"
    echo "  test dns           Run DNS tests only"
    echo "  test smtp          Run SMTP tests only"
    echo "  test mail          Run mail flow tests only"
    echo ""
    echo -e "${YELLOW}Configuration Commands:${NC}"
    echo "  config show        Show current configuration"
    echo "  config reset       Reset to default configuration"
    echo "  hosts add          Add entries to /etc/hosts (sudo)"
    echo "  hosts remove       Remove entries from /etc/hosts (sudo)"
    echo "  hosts show         Show what would be added to /etc/hosts"
    echo ""
    echo -e "${YELLOW}Maintenance Commands:${NC}"
    echo "  update             Update Mailcow on all servers"
    echo "  backup             Create snapshots of all VMs"
    echo "  restore            Restore VMs from snapshots"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 setup           # Full setup"
    echo "  $0 start           # Start all VMs"
    echo "  $0 start mars      # Start only mars"
    echo "  $0 info            # Show access info"
    echo "  $0 shell mars      # SSH into mars VM"
    echo ""
    exit 1
}

# Validate VM name
validate_vm() {
    local VM="$1"
    for V in "${VMS[@]}"; do
        if [ "$V" = "$VM" ]; then
            return 0
        fi
    done
    echo -e "${RED}Error: Unknown VM '$VM'${NC}"
    echo "Valid VMs: ${VMS[*]}"
    exit 1
}

# Show access info
show_info() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Mail Server Lab - Access Information${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
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
    echo "   DNS Server: 10.4.26.10"
    echo ""
    echo -e "   ${YELLOW}Run './manager.sh hosts add' to access via domain names${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
}

# Setup command
cmd_setup() {
    echo -e "${BLUE}Starting full setup...${NC}"
    "$SCRIPT_DIR/scripts/setup-all.sh"
}

# Start command
cmd_start() {
    local VM="$1"

    if [ -n "$VM" ]; then
        validate_vm "$VM"
        echo "Starting $VM..."
        multipass start "$VM"
        echo -e "${GREEN}$VM started${NC}"
    else
        echo "Starting all VMs..."
        for V in "${VMS[@]}"; do
            if multipass list 2>/dev/null | grep -q "^${V} "; then
                echo "  Starting $V..."
                multipass start "$V" 2>/dev/null || true
            fi
        done
        echo -e "${GREEN}All VMs started${NC}"

        # Wait for services
        echo "Waiting for services to be ready..."
        sleep 30

        show_info
    fi
}

# Stop command
cmd_stop() {
    local VM="$1"

    if [ -n "$VM" ]; then
        validate_vm "$VM"
        echo "Stopping $VM..."
        multipass stop "$VM"
        echo -e "${GREEN}$VM stopped${NC}"
    else
        echo "Stopping all VMs..."
        for V in "${VMS[@]}"; do
            if multipass list 2>/dev/null | grep -q "^${V}.*Running"; then
                echo "  Stopping $V..."
                multipass stop "$V" 2>/dev/null || true
            fi
        done
        echo -e "${GREEN}All VMs stopped${NC}"
    fi
}

# Restart command
cmd_restart() {
    local VM="$1"

    if [ -n "$VM" ]; then
        validate_vm "$VM"
        echo "Restarting $VM..."
        multipass restart "$VM"
        echo -e "${GREEN}$VM restarted${NC}"
    else
        echo "Restarting all VMs..."
        for V in "${VMS[@]}"; do
            if multipass list 2>/dev/null | grep -q "^${V} "; then
                echo "  Restarting $V..."
                multipass restart "$V" 2>/dev/null || true
            fi
        done
        echo -e "${GREEN}All VMs restarted${NC}"
    fi
}

# Status command
cmd_status() {
    echo -e "${CYAN}Mail Server Lab Status${NC}"
    echo ""

    echo -e "${YELLOW}VM Status:${NC}"
    printf "%-15s %-12s %-15s %s\n" "NAME" "STATE" "IP" "ROLE"
    echo "─────────────────────────────────────────────────────────────"

    for VM in "${VMS[@]}"; do
        if multipass list 2>/dev/null | grep -q "^${VM} "; then
            STATE=$(multipass list | grep "^${VM} " | awk '{print $2}')
            IP=$(multipass info "$VM" 2>/dev/null | grep "IPv4" | awk '{print $2}' | head -1)

            case "$VM" in
                dns-server) ROLE="BIND DNS" ;;
                mars) ROLE="Mailcow (mars.lab)" ;;
                venus) ROLE="Mailcow (venus.lab)" ;;
                jupiter) ROLE="Mailcow (jupiter.lab)" ;;
            esac

            if [ "$STATE" = "Running" ]; then
                STATE_COLOR="${GREEN}Running${NC}"
            else
                STATE_COLOR="${YELLOW}$STATE${NC}"
            fi

            printf "%-15s %-22b %-15s %s\n" "$VM" "$STATE_COLOR" "${IP:-N/A}" "$ROLE"
        else
            printf "%-15s %-22b %-15s %s\n" "$VM" "${RED}Not found${NC}" "N/A" ""
        fi
    done

    echo ""

    # Check services on running mail servers
    echo -e "${YELLOW}Service Status:${NC}"
    for VM in "${MAIL_VMS[@]}"; do
        if multipass list 2>/dev/null | grep -q "^${VM}.*Running"; then
            echo -n "  $VM: "
            CONTAINERS=$(multipass exec "$VM" -- sudo docker ps --format '{{.Names}}' 2>/dev/null | wc -l || echo "0")
            if [ "$CONTAINERS" -gt 0 ]; then
                echo -e "${GREEN}$CONTAINERS containers running${NC}"
            else
                echo -e "${RED}No containers running${NC}"
            fi
        fi
    done

    echo ""
}

# Destroy command
cmd_destroy() {
    "$SCRIPT_DIR/scripts/teardown.sh"
}

# Logs command
cmd_logs() {
    local VM="$1"

    if [ -z "$VM" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        echo "Usage: $0 logs <vm>"
        echo "VMs: ${VMS[*]}"
        exit 1
    fi

    validate_vm "$VM"

    if [ "$VM" = "dns-server" ]; then
        echo "DNS Server logs:"
        multipass exec "$VM" -- sudo journalctl -u bind9 -n 50 --no-pager
    else
        echo "Mailcow logs for $VM:"
        multipass exec "$VM" -- bash -c "cd /opt/mailcow-dockerized && docker compose logs --tail=50"
    fi
}

# Shell command
cmd_shell() {
    local VM="$1"

    if [ -z "$VM" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        echo "Usage: $0 shell <vm>"
        echo "VMs: ${VMS[*]}"
        exit 1
    fi

    validate_vm "$VM"
    multipass shell "$VM"
}

# Test command
cmd_test() {
    local TEST_TYPE="$1"

    echo -e "${CYAN}Running tests...${NC}"
    echo ""

    case "$TEST_TYPE" in
        dns)
            "$SCRIPT_DIR/tests/test-dns.sh"
            ;;
        smtp)
            "$SCRIPT_DIR/tests/test-smtp.sh"
            ;;
        mail)
            "$SCRIPT_DIR/tests/test-mail-flow.sh"
            ;;
        *)
            # Run all tests
            echo -e "${YELLOW}[1/3] DNS Tests${NC}"
            "$SCRIPT_DIR/tests/test-dns.sh" || true
            echo ""
            echo -e "${YELLOW}[2/3] SMTP Tests${NC}"
            "$SCRIPT_DIR/tests/test-smtp.sh" || true
            echo ""
            echo -e "${YELLOW}[3/3] Mail Flow Tests${NC}"
            "$SCRIPT_DIR/tests/test-mail-flow.sh" || true
            ;;
    esac
}

# Info command
cmd_info() {
    show_info
}

# Config command
cmd_config() {
    local ACTION="$1"

    case "$ACTION" in
        show)
            echo -e "${CYAN}Current Configuration:${NC}"
            echo ""
            echo "Network:"
            echo "  Subnet: ${NETWORK_SUBNET:-10.4.26.0/24}"
            echo "  Gateway: ${NETWORK_GATEWAY:-10.4.26.1}"
            echo ""
            echo "DNS Server:"
            echo "  IP: ${DNS_SERVER_IP:-10.4.26.10}"
            echo "  Hostname: ${DNS_SERVER_HOSTNAME:-ns1.lab}"
            echo ""
            echo "Mail Servers:"
            echo "  Mars:    ${MARS_IP:-10.4.26.11} (${MARS_DOMAIN:-mars.lab})"
            echo "  Venus:   ${VENUS_IP:-10.4.26.12} (${VENUS_DOMAIN:-venus.lab})"
            echo "  Jupiter: ${JUPITER_IP:-10.4.26.13} (${JUPITER_DOMAIN:-jupiter.lab})"
            echo ""
            echo "Resources per mail server:"
            echo "  CPU: ${MAIL_CPU:-2}"
            echo "  RAM: ${MAIL_RAM:-2G}"
            echo "  Disk: ${MAIL_DISK:-10G}"
            ;;
        reset)
            echo "Configuration files are static. Edit files in config/ directory to customize."
            ;;
        *)
            echo "Usage: $0 config <show|reset>"
            ;;
    esac
}

# Hosts command
cmd_hosts() {
    local ACTION="$1"

    HOSTS_CONTENT="$HOSTS_BEGIN
10.4.26.10 ns1.lab
10.4.26.11 mail.mars.lab mars.lab
10.4.26.12 mail.venus.lab venus.lab
10.4.26.13 mail.jupiter.lab jupiter.lab
$HOSTS_END"

    case "$ACTION" in
        add)
            echo "Adding mail server entries to /etc/hosts..."

            # Check if entries already exist
            if grep -q "$HOSTS_BEGIN" /etc/hosts 2>/dev/null; then
                echo -e "${YELLOW}Entries already exist. Removing old entries first...${NC}"
                sudo sed -i "/$HOSTS_BEGIN/,/$HOSTS_END/d" /etc/hosts
            fi

            # Add new entries
            echo "$HOSTS_CONTENT" | sudo tee -a /etc/hosts > /dev/null

            echo -e "${GREEN}Entries added to /etc/hosts${NC}"
            echo ""
            echo "You can now access:"
            echo "  - https://mail.mars.lab"
            echo "  - https://mail.venus.lab"
            echo "  - https://mail.jupiter.lab"
            ;;
        remove)
            echo "Removing mail server entries from /etc/hosts..."

            if grep -q "$HOSTS_BEGIN" /etc/hosts 2>/dev/null; then
                sudo sed -i "/$HOSTS_BEGIN/,/$HOSTS_END/d" /etc/hosts
                echo -e "${GREEN}Entries removed from /etc/hosts${NC}"
            else
                echo -e "${YELLOW}No mail server entries found in /etc/hosts${NC}"
            fi
            ;;
        show)
            echo "The following would be added to /etc/hosts:"
            echo ""
            echo "$HOSTS_CONTENT"
            ;;
        *)
            echo "Usage: $0 hosts <add|remove|show>"
            ;;
    esac
}

# Update command
cmd_update() {
    echo "Updating Mailcow on all servers..."

    for VM in "${MAIL_VMS[@]}"; do
        if multipass list 2>/dev/null | grep -q "^${VM}.*Running"; then
            echo ""
            echo -e "${YELLOW}Updating $VM...${NC}"
            multipass exec "$VM" -- bash -c "cd /opt/mailcow-dockerized && sudo ./update.sh --skip-start && docker compose up -d"
        fi
    done

    echo ""
    echo -e "${GREEN}Update complete!${NC}"
}

# Backup command
cmd_backup() {
    echo "Creating snapshots of all VMs..."

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)

    for VM in "${VMS[@]}"; do
        if multipass list 2>/dev/null | grep -q "^${VM} "; then
            echo "  Creating snapshot: ${VM}-${TIMESTAMP}"
            multipass snapshot "$VM" --name "${VM}-${TIMESTAMP}" || {
                echo -e "${YELLOW}Warning: Could not create snapshot for $VM${NC}"
            }
        fi
    done

    echo ""
    echo -e "${GREEN}Backup complete!${NC}"
    echo "Use 'multipass list --snapshots' to see all snapshots"
}

# Restore command
cmd_restore() {
    echo "Available snapshots:"
    multipass list --snapshots 2>/dev/null || echo "No snapshots found"

    echo ""
    echo "To restore a specific snapshot, use:"
    echo "  multipass restore <vm>.<snapshot-name>"
}

# Main command handler
case "${1:-}" in
    setup)
        cmd_setup
        ;;
    start)
        cmd_start "${2:-}"
        ;;
    stop)
        cmd_stop "${2:-}"
        ;;
    restart)
        cmd_restart "${2:-}"
        ;;
    status)
        cmd_status
        ;;
    destroy)
        cmd_destroy
        ;;
    logs)
        cmd_logs "${2:-}"
        ;;
    shell)
        cmd_shell "${2:-}"
        ;;
    test)
        cmd_test "${2:-}"
        ;;
    info)
        cmd_info
        ;;
    config)
        cmd_config "${2:-}"
        ;;
    hosts)
        cmd_hosts "${2:-}"
        ;;
    update)
        cmd_update
        ;;
    backup)
        cmd_backup
        ;;
    restore)
        cmd_restore
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        usage
        ;;
esac
