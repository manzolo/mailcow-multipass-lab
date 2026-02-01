#!/bin/bash
# Mailcow setup script - runs inside the VM
set -e

# Mailcow version - use a specific tag for reproducibility
# Check available tags: https://github.com/mailcow/mailcow-dockerized/tags
MAILCOW_VERSION="2026-01"

DOMAIN="${1:?Domain required}"
IP="${2:?IP required}"
DNS_SERVER="${3:-10.4.26.10}"

LOG_FILE="/var/log/mailcow-setup/setup.log"
STATUS_FILE="/var/log/mailcow-setup/status"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

# Symbols
CHECK="${GREEN}✓${NC}"
ARROW="${CYAN}→${NC}"
WARN="${YELLOW}⚠${NC}"
INFO="${BLUE}ℹ${NC}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_verbose() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

update_status() {
    echo "$1" > "$STATUS_FILE"
    log "Status: $1"
}

step() {
    echo -e "  ${ARROW} $1"
    log "$1"
}

step_done() {
    echo -e "  ${CHECK} $1"
    log "Done: $1"
}

step_info() {
    echo -e "  ${INFO} ${DIM}$1${NC}"
    log "$1"
}

mkdir -p /var/log/mailcow-setup

update_status "starting"
echo ""
echo -e "${BOLD}${CYAN}Setting up Mailcow for ${YELLOW}$DOMAIN${NC}"
echo -e "${DIM}IP: $IP | DNS: $DNS_SERVER${NC}"
echo ""
log "Setting up Mailcow for domain: $DOMAIN with IP: $IP"

# Install Docker
update_status "installing_docker"
if ! command -v docker &> /dev/null; then
    step "Installing Docker Engine..."
    step_info "This may take a moment (output suppressed)"
    curl -fsSL https://get.docker.com 2>/dev/null | sh >> "$LOG_FILE" 2>&1
    systemctl enable docker >> "$LOG_FILE" 2>&1
    systemctl start docker >> "$LOG_FILE" 2>&1
    step_done "Docker Engine installed"
else
    step_done "Docker Engine already installed"
fi

# Install Docker Compose plugin
step "Installing Docker Compose plugin..."
apt-get update >> "$LOG_FILE" 2>&1
apt-get install -y docker-compose-plugin >> "$LOG_FILE" 2>&1
step_done "Docker Compose plugin installed"

# Clone Mailcow (specific version for reproducibility)
update_status "cloning_mailcow"
cd /opt
if [ ! -d "mailcow-dockerized" ]; then
    step "Cloning Mailcow repository (version: $MAILCOW_VERSION)..."
    # Clone repo, then reset master branch to specific tag
    git clone --quiet https://github.com/mailcow/mailcow-dockerized.git >> "$LOG_FILE" 2>&1
    cd mailcow-dockerized
    git fetch --tags --quiet >> "$LOG_FILE" 2>&1
    git reset --hard "$MAILCOW_VERSION" >> "$LOG_FILE" 2>&1
    step_done "Mailcow cloned ($(git describe --tags 2>/dev/null || echo $MAILCOW_VERSION))"
else
    cd mailcow-dockerized
    step_done "Mailcow repository already exists"
fi

# Generate configuration
update_status "generating_config"
step "Generating Mailcow configuration..."

# Create base config first
DBPASS=$(openssl rand -hex 16)
DBROOT=$(openssl rand -hex 16)
API_KEY=$(openssl rand -hex 32)
API_KEY_RO=$(openssl rand -hex 32)

# Run generate_config.sh with inputs (suppress output)
./generate_config.sh >> "$LOG_FILE" 2>&1 << EOF
mail.${DOMAIN}
UTC
EOF
step_done "Base configuration generated"

# Now modify the generated config
update_status "customizing_config"
step "Customizing configuration for lab environment..."

# Disable ClamAV to save RAM
sed -i 's/^SKIP_CLAMD=.*/SKIP_CLAMD=y/' mailcow.conf

# Skip Let's Encrypt for local lab
sed -i 's/^SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/' mailcow.conf

# Disable Solr to save RAM
sed -i 's/^SKIP_SOLR=.*/SKIP_SOLR=y/' mailcow.conf

# Reduce SOGo workers
sed -i 's/^SOGO_WORKERS=.*/SOGO_WORKERS=1/' mailcow.conf

# Enable API access (uncomment and set values)
# Generate API keys if not already set
sed -i "s/^#API_KEY=$/API_KEY=${API_KEY}/" mailcow.conf
sed -i "s/^#API_KEY_READ_ONLY=$/API_KEY_READ_ONLY=${API_KEY_RO}/" mailcow.conf
sed -i "s|^#API_ALLOW_FROM=.*|API_ALLOW_FROM=172.22.1.1,127.0.0.1,10.4.26.0/24|" mailcow.conf

# Save API key for later use
echo "API_KEY=${API_KEY}" > /opt/mailcow-dockerized/api_key.txt
log "API_KEY saved to /opt/mailcow-dockerized/api_key.txt"
step_done "Configuration customized (ClamAV/Solr disabled, API enabled)"

# Pull images
update_status "pulling_images"
echo ""
echo -e "${BOLD}${BLUE}Downloading Docker images...${NC}"
step_info "This is the longest step - please wait"
docker compose pull --quiet >> "$LOG_FILE" 2>&1
step_done "All Docker images downloaded"

# Start containers
update_status "starting_containers"
step "Starting Mailcow containers..."
docker compose up -d >> "$LOG_FILE" 2>&1
step_done "Containers started"

# Configure unbound to forward lab DNS queries
update_status "configuring_dns"
echo ""
echo -e "${BOLD}${BLUE}Configuring services...${NC}"
step "Setting up DNS forwarding to lab DNS server..."
cat >> data/conf/unbound/unbound.conf << DNSEOF

# Lab DNS forwarding - mark zones as insecure (no DNSSEC)
server:
  domain-insecure: "mars.lab"
  domain-insecure: "venus.lab"
  domain-insecure: "jupiter.lab"
  domain-insecure: "26.4.10.in-addr.arpa"

forward-zone:
  name: "mars.lab"
  forward-addr: ${DNS_SERVER}
  forward-first: yes

forward-zone:
  name: "venus.lab"
  forward-addr: ${DNS_SERVER}
  forward-first: yes

forward-zone:
  name: "jupiter.lab"
  forward-addr: ${DNS_SERVER}
  forward-first: yes

forward-zone:
  name: "26.4.10.in-addr.arpa"
  forward-addr: ${DNS_SERVER}
  forward-first: yes
DNSEOF

# Restart unbound to apply DNS config
docker compose restart unbound-mailcow >> "$LOG_FILE" 2>&1
sleep 10
step_done "DNS forwarding configured"

# Configure Rspamd for lab environment
step "Configuring Rspamd anti-spam for lab environment..."
mkdir -p data/conf/rspamd/local.d
mkdir -p data/conf/rspamd/override.d

# Disable greylisting
cat > data/conf/rspamd/local.d/greylist.conf << GREYEOF
enabled = false;
GREYEOF

# Disable hfilter hostname checks (causes spam for lab emails)
cat > data/conf/rspamd/local.d/hfilter.conf << HFEOF
helo_enabled = false;
hostname_enabled = false;
url_enabled = false;
from_enabled = false;
rcpt_enabled = false;
mid_enabled = false;
HFEOF

# Override scores for lab environment - append to groups.conf
cat >> data/conf/rspamd/local.d/groups.conf << SCOREEOF

# Lab environment overrides - disable spam scoring for internal mail
symbols {
  "HFILTER_HOSTNAME_UNKNOWN" { score = 0.0; }
  "RDNS_NONE" { score = 0.0; }
  "R_DKIM_PERMFAIL" { score = 0.0; }
  "DKIM_TRACE" { score = 0.0; }
  "ONCE_RECEIVED" { score = 0.0; }
  "MISSING_MID" { score = 0.0; }
  "HFILTER_HELO_BAREIP" { score = 0.0; }
  "HFILTER_FROMHOST_NOT_FQDN" { score = 0.0; }
  "HFILTER_FROM_BOUNCE" { score = 0.0; }
  "FORGED_SENDER" { score = 0.0; }
  "R_MIXED_CHARSET" { score = 0.0; }
}
SCOREEOF

# Restart rspamd to apply configuration
docker compose restart rspamd-mailcow >> "$LOG_FILE" 2>&1
sleep 10
step_done "Rspamd configured (greylisting disabled)"

# Wait for services
update_status "waiting_for_services"
echo ""
echo -e "${BOLD}${BLUE}Waiting for services to initialize...${NC}"
step_info "Services need time to fully start (~2 minutes)"

# Show a simple progress indicator
for i in {1..12}; do
    echo -ne "  ${DIM}[$(printf '%*s' $i | tr ' ' '█')$(printf '%*s' $((12-i)) | tr ' ' '░')] ${i}0s${NC}\r"
    sleep 10
done
echo ""

# Check if services are running
RUNNING=$(docker compose ps --format '{{.Status}}' 2>/dev/null | grep -c "Up" || echo "0")
TOTAL=$(docker compose ps --format '{{.Name}}' 2>/dev/null | wc -l || echo "0")

if [ "$RUNNING" -gt 0 ]; then
    update_status "ready"
    step_done "Mailcow is ready ($RUNNING/$TOTAL containers running)"
    log "Mailcow setup complete for $DOMAIN"
else
    update_status "error"
    echo -e "  ${RED}✗ ERROR: Services failed to start${NC}"
    log "ERROR: Some services failed to start"
    docker compose ps >> "$LOG_FILE" 2>&1
    exit 1
fi

# Output access information
echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Mailcow setup complete for ${BOLD}$DOMAIN${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "  ${CYAN}Webmail:${NC} https://${IP}/SOGo"
echo -e "  ${CYAN}Admin:${NC}   https://${IP} (admin/moohoo)"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
log ""
log "Mailcow is ready!"
log "Webmail (SOGo): https://${IP}/SOGo"
log "Admin UI: https://${IP}"
