# Mailcow Multipass Lab

A complete mail server lab environment using [Multipass](https://multipass.run/) VMs and [Mailcow](https://mailcow.email/). Deploy three independent mail servers with integrated DNS in minutes.

## Overview

This project creates a fully functional mail infrastructure for testing, development, and learning:

- **3 Mail Servers**: Mars, Venus, Jupiter (each running Mailcow)
- **1 DNS Server**: BIND9 with MX, SPF, DKIM, DMARC records
- **Webmail**: SOGo interface on each server
- **Pre-configured**: Test accounts, static IPs, domain names

```
┌─────────────────────────────────────────────────────┐
│                    Mail Server Lab                  │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │    Mars     │  │    Venus    │  │   Jupiter   │  │
│  │  mars.lab   │  │  venus.lab  │  │ jupiter.lab │  │
│  │ 10.4.26.11  │  │ 10.4.26.12  │  │ 10.4.26.13  │  │
│  │   Mailcow   │  │   Mailcow   │  │   Mailcow   │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
│          │               │               │          │
│          └───────────────┼───────────────┘          │
│                          │                          │
│                  ┌───────────────┐                  │
│                  │  DNS Server   │                  │
│                  │    ns1.lab    │                  │
│                  │  10.4.26.10   │                  │
│                  │    BIND9      │                  │
│                  └───────────────┘                  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Requirements

- **OS**: Linux (tested on Ubuntu 22.04+)
- **Multipass**: v1.10+
- **RAM**: 7GB available (~6.5GB used by VMs)
- **Disk**: 40GB available (~35GB used by VMs)
- **CPU**: 4+ cores recommended

## Quick Start

```bash
# Clone the repository
git clone https://github.com/manzolo/mailcow-multipass-lab.git
cd mailcow-multipass-lab

# Run full setup
./manager.sh setup

# Show access information
./manager.sh info
```

The setup takes approximately 15-30 minutes depending on your internet connection.

## Access Information

### Webmail (SOGo)

| Server  | URL                        | Alternative               |
|---------|----------------------------|---------------------------|
| Mars    | https://10.4.26.11/SOGo    | https://mail.mars.lab/SOGo |
| Venus   | https://10.4.26.12/SOGo    | https://mail.venus.lab/SOGo |
| Jupiter | https://10.4.26.13/SOGo    | https://mail.jupiter.lab/SOGo |

### Admin UI (Mailcow)

| Server  | URL                  | Username | Password |
|---------|----------------------|----------|----------|
| Mars    | https://10.4.26.11   | admin    | moohoo   |
| Venus   | https://10.4.26.12   | admin    | moohoo   |
| Jupiter | https://10.4.26.13   | admin    | moohoo   |

### Test Accounts

| Email              | Password  |
|--------------------|-----------|
| alice@mars.lab     | alice123  |
| bob@mars.lab       | bob123    |
| alice@venus.lab    | alice123  |
| bob@venus.lab      | bob123    |
| alice@jupiter.lab  | alice123  |
| bob@jupiter.lab    | bob123    |

### DNS Server

```bash
# Test DNS resolution
dig @10.4.26.10 mars.lab MX
dig @10.4.26.10 mail.venus.lab A
```

## CLI Reference

### Lifecycle Commands

```bash
./manager.sh setup              # Full deployment
./manager.sh start [vm]         # Start all or specific VM
./manager.sh stop [vm]          # Stop all or specific VM
./manager.sh restart [vm]       # Restart VMs
./manager.sh destroy            # Remove all VMs
```

### Status Commands

```bash
./manager.sh status             # Show VM states and services
./manager.sh info               # Display access URLs and credentials
./manager.sh logs <vm>          # Show logs (dns-server|mars|venus|jupiter)
./manager.sh shell <vm>         # SSH into VM
```

### Testing Commands

```bash
./manager.sh test               # Run all tests
./manager.sh test dns           # DNS resolution tests
./manager.sh test smtp          # SMTP connectivity tests
./manager.sh test mail          # Mail flow tests
```

### Configuration Commands

```bash
./manager.sh config show        # Show current configuration
./manager.sh hosts add          # Add entries to /etc/hosts (sudo)
./manager.sh hosts remove       # Remove entries from /etc/hosts
./manager.sh hosts show         # Show what would be added
```

### Maintenance Commands

```bash
./manager.sh update             # Update Mailcow on all servers
./manager.sh backup             # Create VM snapshots
./manager.sh restore            # Show available snapshots
```

## Project Structure

```
.
├── manager.sh                  # Main CLI tool
├── config/
│   ├── network.env             # Network configuration
│   ├── domains.env             # Domain mappings
│   └── users.env               # Default user credentials
├── scripts/
│   ├── 00-check-prerequisites.sh
│   ├── 01-deploy-dns.sh
│   ├── 02-deploy-mars.sh
│   ├── 03-deploy-venus.sh
│   ├── 04-deploy-jupiter.sh
│   ├── 05-create-users.sh
│   ├── setup-all.sh
│   └── teardown.sh
├── dns/
│   ├── named.conf.options
│   ├── named.conf.local
│   └── zones/
│       ├── db.mars.lab
│       ├── db.venus.lab
│       ├── db.jupiter.lab
│       └── db.26.4.10.in-addr.arpa
├── mailcow/
│   ├── mailcow-setup.sh
│   └── create-users.sh
└── tests/
    ├── test-dns.sh
    ├── test-smtp.sh
    └── test-mail-flow.sh
```

## Configuration

### Network Configuration

Edit `config/network.env` to customize:

```bash
# Network
NETWORK_SUBNET="10.4.26.0/24"
NETWORK_GATEWAY="10.4.26.1"

# DNS Server
DNS_SERVER_IP="10.4.26.10"

# Mail Servers
MARS_IP="10.4.26.11"
VENUS_IP="10.4.26.12"
JUPITER_IP="10.4.26.13"

# Resources per mail server
MAIL_CPU="2"
MAIL_RAM="2G"
MAIL_DISK="10G"
```

### DNS Records

Each domain includes:
- **MX**: Mail exchanger record
- **SPF**: Sender Policy Framework
- **DKIM**: DomainKeys (placeholder)
- **DMARC**: Domain-based Message Authentication
- **SRV**: Autodiscovery records

## Lab Optimizations

To reduce resource usage, the following services are disabled by default:

- **ClamAV**: Antivirus scanning (saves ~1GB RAM per server)
- **Solr**: Full-text search (saves ~512MB RAM per server)
- **Let's Encrypt**: Uses self-signed certificates
- **Greylisting**: Disabled for instant mail delivery between servers

### Mailcow Version

The lab uses a pinned Mailcow version for reproducibility. To change the version, edit `mailcow/mailcow-setup.sh`:

```bash
MAILCOW_VERSION="2026-01"  # Change to desired tag
```

Available tags: https://github.com/mailcow/mailcow-dockerized/tags

## Troubleshooting

### Check VM Status

```bash
multipass list
./manager.sh status
```

### View Mailcow Logs

```bash
./manager.sh logs mars
# or directly
multipass exec mars -- docker compose -f /opt/mailcow-dockerized/docker-compose.yml logs -f
```

### Restart Mailcow Services

```bash
multipass exec mars -- bash -c "cd /opt/mailcow-dockerized && docker compose restart"
```

### DNS Issues

```bash
# Test from host
dig @10.4.26.10 mars.lab MX

# Test from VM
multipass exec mars -- dig @10.4.26.10 mars.lab MX
```

### Reset Everything

```bash
./manager.sh destroy
./manager.sh setup
```

## Use Cases

- **Email Development**: Test email sending/receiving in isolation
- **Mailcow Learning**: Explore Mailcow features without affecting production
- **Multi-Domain Testing**: Test inter-domain email delivery
- **CI/CD Integration**: Automated email infrastructure testing
- **Security Testing**: Test SPF, DKIM, DMARC configurations
- **Migration Testing**: Validate configurations before production deployment

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Mailcow](https://mailcow.email/) - The open-source mail server suite
- [Multipass](https://multipass.run/) - Lightweight VM manager by Canonical
- [BIND9](https://www.isc.org/bind/) - The most widely used DNS software
