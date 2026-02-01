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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

update_status() {
    echo "$1" > "$STATUS_FILE"
    log "Status: $1"
}

mkdir -p /var/log/mailcow-setup

update_status "starting"
log "Setting up Mailcow for domain: $DOMAIN with IP: $IP"

# Install Docker
update_status "installing_docker"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Install Docker Compose plugin
apt-get update
apt-get install -y docker-compose-plugin

# Clone Mailcow (specific version for reproducibility)
update_status "cloning_mailcow"
cd /opt
if [ ! -d "mailcow-dockerized" ]; then
    log "Cloning Mailcow version: $MAILCOW_VERSION"
    # Clone repo, then reset master branch to specific tag
    git clone https://github.com/mailcow/mailcow-dockerized.git
    cd mailcow-dockerized
    git fetch --tags
    git reset --hard "$MAILCOW_VERSION"
    log "Mailcow pinned to version: $(git describe --tags)"
else
    cd mailcow-dockerized
fi

# Generate configuration
update_status "generating_config"

# Create base config first
DBPASS=$(openssl rand -hex 16)
DBROOT=$(openssl rand -hex 16)
API_KEY=$(openssl rand -hex 32)
API_KEY_RO=$(openssl rand -hex 32)

# Run generate_config.sh with inputs
./generate_config.sh << EOF
mail.${DOMAIN}
UTC
EOF

# Now modify the generated config
update_status "customizing_config"

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
log "Configuring API access..."
sed -i "s/^#API_KEY=$/API_KEY=${API_KEY}/" mailcow.conf
sed -i "s/^#API_KEY_READ_ONLY=$/API_KEY_READ_ONLY=${API_KEY_RO}/" mailcow.conf
sed -i "s|^#API_ALLOW_FROM=.*|API_ALLOW_FROM=172.22.1.1,127.0.0.1,10.4.26.0/24|" mailcow.conf

# Save API key for later use
echo "API_KEY=${API_KEY}" > /opt/mailcow-dockerized/api_key.txt
log "API_KEY saved to /opt/mailcow-dockerized/api_key.txt"

# Pull images
update_status "pulling_images"
docker compose pull

# Start containers
update_status "starting_containers"
docker compose up -d

# Configure unbound to forward lab DNS queries
update_status "configuring_dns"
log "Configuring DNS forwarding to lab DNS server..."
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
docker compose restart unbound-mailcow
sleep 10

# Configure Rspamd for lab environment
log "Configuring Rspamd for lab..."
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
log "Restarting rspamd to apply lab configuration..."
docker compose restart rspamd-mailcow
sleep 10

# Wait for services
update_status "waiting_for_services"
log "Waiting for Mailcow services to start..."
sleep 120

# Check if services are running
if docker compose ps | grep -q "Up"; then
    update_status "ready"
    log "Mailcow setup complete for $DOMAIN"
else
    update_status "error"
    log "ERROR: Some services failed to start"
    docker compose ps
    exit 1
fi

# Output access information
log ""
log "============================================"
log "Mailcow is ready!"
log "============================================"
log "Webmail (SOGo): https://${IP}/SOGo"
log "Admin UI: https://${IP}"
log "Admin User: admin"
log "Admin Pass: moohoo"
log "============================================"
