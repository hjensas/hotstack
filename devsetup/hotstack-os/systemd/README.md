# HotStack-OS systemd Services

This directory contains systemd unit files and helper scripts for deploying HotStack-OS as systemd services.

## Files

### Helper Scripts

- `hotstack-os-infra-setup.sh` - Idempotent infrastructure setup (OVS bridges, /etc/hosts, NFS exports)
- `hotstack-os-infra-cleanup.sh` - Infrastructure cleanup (removes /etc/hosts entries and NFS exports)
- `hotstack-healthcheck.sh` - Health check polling for container services

### Service Units

- `hotstack-os-infra-setup.service` - Oneshot service that sets up network and storage infrastructure
- `hotstack-os-*.service` - Individual container services (to be created)
- `hotstack-os.target` - Target that groups all HotStack-OS services

## Installation

Use the Makefile targets:

```bash
# Install systemd services
sudo make install

# Enable and start services
sudo systemctl enable --now hotstack-os.target

# Check status
sudo systemctl status hotstack-os.target

# View logs
sudo journalctl -u hotstack-os.target -f
```

## Configuration

Environment variables from `.env` are baked into the systemd service files during `make install`. To change configuration:

1. Edit `.env` in the project directory
2. Re-run `sudo make install`
3. Restart services: `sudo systemctl restart hotstack-os.target`

This ensures the service configuration always matches the source `.env` file.

## Architecture

Services are organized in dependency layers:

1. **Network Setup** (oneshot): Creates OVS bridges and configures /etc/hosts
2. **Infrastructure**: dnsmasq, haproxy, mariadb, rabbitmq, memcached
3. **Identity**: keystone
4. **Core Services**: glance, placement
5. **Networking**: ovn-northd, ovn-controller, neutron-server, neutron-metadata
6. **Compute**: nova-api, nova-conductor, nova-scheduler, nova-compute, nova-novncproxy
7. **Block Storage**: cinder-api, cinder-scheduler, cinder-volume
8. **Orchestration**: heat-api, heat-engine

## Design Principles

- **Idempotent**: All scripts can be run multiple times safely
- **Health Checks**: Services wait for dependencies to be healthy before starting
- **Proper Ordering**: Dependencies enforced via After/Requires directives
- **Journal Logging**: All output goes to systemd journal
- **Graceful Shutdown**: 10-second stop timeout for clean container shutdown
