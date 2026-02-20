# HotStack-OS - Containerized OpenStack for HotStack Development

A minimal containerized OpenStack deployment using podman-compose, designed for running HotStack scenarios on developer workstations.

## Features

- **Fast setup**: ~10 minutes from zero to working OpenStack (first-time build), ~3 minutes for subsequent starts
- **Self-contained**: All services in containers with file-backed storage
- **Host integration**: Uses host libvirt (KVM), OpenvSwitch, and NFS
- **HotStack-ready**: Supports Heat orchestration, trunk ports, VLANs, boot from volume, NoVNC console, and serial console logging
- **Minimal dependencies**: Requires libvirt, OpenvSwitch, podman, NFS server, and nmap-ncat on host

> ⚠️ **Security Warning**: This environment uses default passwords, no encryption, and minimal access controls. It is intended ONLY for development and testing on trusted private networks.

## Quick Start

See **[QUICKSTART.md](QUICKSTART.md)** for detailed step-by-step instructions.

**TL;DR**:
```bash
sudo make install-client # Install OpenStack client packages
sudo make setup          # Verify host prerequisites and setup NFS
sudo make build          # Build container images (~5 min)
sudo make start          # Prepare configs and start all services
sudo make status         # Check service status
make post-setup          # Create hotstack project/user, resources, and download/upload images (no sudo required)
```

Then set `export OS_CLOUD=hotstack-os` for regular user access or `export OS_CLOUD=hotstack-os-admin` for admin access and run `openstack` commands.

## Architecture

HotStack-OS uses a hybrid architecture with OpenStack control plane services running in containers (22 total) while integrating with host libvirt (KVM) and OpenvSwitch for compute and networking. All services are accessible through a load balancer at `172.31.0.129` (hot-ex interface). See **[ARCHITECTURE.md](ARCHITECTURE.md)** for detailed information on components, networking, security, and data persistence.

## Smoke Test

Validate your deployment with `make smoke-test`. See [SMOKE_TEST.md](SMOKE_TEST.md) for details.

## Configuration

The default configuration works for most development environments. If you need to customize settings (passwords, network ranges, storage paths, quotas, etc.), see **[CONFIGURATION.md](CONFIGURATION.md)** for detailed documentation.

## Coexistence with Other Workloads

HotStack-OS is designed to coexist safely with other podman containers and workloads. The setup uses project-scoped resources and explicit naming to avoid conflicts.

**⚠️ WARNING about `make clean`:**
- `make clean` removes hotstack-os containers and data
- **Also destroys ALL libvirt VMs matching pattern `notapet-<uuid>`**
- **Removes ALL network namespaces matching pattern `netns-*`**
- Review `virsh list --all` and `ip netns list` before running if you have other deployments

## Known Limitations

- **Single-node only**: No HA or multi-node support
- **Networking**: Default setup provides isolated private networks; external internet access requires provider network configuration
- **Storage**: NFS-based Cinder volumes using shared filesystem for HotStack scenario testing
- **Security**: Default passwords, no SSL/TLS, no authentication tokens

## Management Commands

```bash
sudo make setup           # Verify host prerequisites
sudo make install-client  # Install OpenStack client packages on host
sudo make build           # Build all container images
sudo make config          # Prepare runtime configuration files (automatically run by 'make start')
sudo make start           # Start all services (includes config preparation)
sudo make stop            # Stop all services
sudo make restart         # Restart all services
sudo make status          # Check status of all services
make post-setup           # Create hotstack project/user, resources, and download/upload images (no sudo required)
sudo make logs            # View logs from all services
sudo make clean           # Complete reset (WARNING: destroys ALL libvirt VMs with pattern 'notapet-<uuid>')
```

## Troubleshooting

See **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for common problems and solutions.

## License

Apache License 2.0
