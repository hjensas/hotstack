# HotStack-OS Quick Start Guide

Complete step-by-step guide to get OpenStack running for HotStack development.

## Prerequisites

- CentOS Stream 9, RHEL 9, or Fedora (recent version)
- Root/sudo access
- At least 16 GB RAM and 100 GB disk space

**Note**: `make setup` will automatically install all required packages (openvswitch, libvirt, qemu-kvm, podman, etc.) and configure services.

## Setup Steps

### Step 1: Verify Host Prerequisites and Setup NFS

```bash
cd devsetup/hotstack-os/
sudo make setup
```

This performs complete host setup:
- Installs required packages (`openvswitch`, `libvirt`, `nfs-utils`, etc.)
- Enables and starts required services (`openvswitch`, `libvirt`, `nfs-server`)
- Verifies KVM support (`/dev/kvm` exists)
- Creates system directories for Nova instances with proper ownership
- Sets up NFS server for Cinder volumes (exported to localhost)
- Configures firewall zones for container and provider networks (172.31.0.0/24)

The NFS export directory for Cinder volumes is created at `/var/lib/hotstack-os/cinder-nfs` by default.

### Step 2: Configure Environment (Optional)

The setup, build, and start scripts will automatically create `.env` from `.env.example` if it doesn't exist. The defaults work for most users.

**If you need to customize** (e.g., network conflicts), create and edit `.env` before running setup:

```bash
cp .env.example .env
# Edit .env to customize
```

**Important settings to review:**
- **Network configuration**: All network subnets and service IPs are required in `.env`. Defaults use `172.31.0.0/24` subnet. Change if this conflicts with your existing network setup.
  - Subnets: `CONTAINER_NETWORK`, `PROVIDER_NETWORK`, `BREX_IP`
  - Service IPs: 19 variables (`MARIADB_IP`, `KEYSTONE_IP`, `NOVA_API_IP`, etc.)
  - Note: dnsmasq runs on `BREX_IP` using host networking
- **Storage paths**: Customize `HOTSTACK_DATA_DIR` or `NOVA_INSTANCES_PATH` if needed.
- **Passwords**: Change from defaults for any production-like testing (optional for dev).

### Step 3: Build Container Images

```bash
sudo make build
```

This takes **~8 minutes** on first run as it:
- Clones OpenStack services from source
- Installs Python dependencies with constraints
- Builds container images for all services

Once built, you can skip this step on subsequent runs (unless you've made changes to service code, dependencies, or containerfiles that require a rebuild).

**Note**: The build process creates portable container images that are not tied to your specific environment. Runtime configuration (passwords, IPs, hostnames) is prepared separately.

### Step 4: Prepare Runtime Configuration (Optional - automatically run by `make start`)

```bash
sudo make config
```

This prepares runtime configuration files by:
- Copying configuration templates from `configs/` to `${HOTSTACK_DATA_DIR}/runtime/config/`
- Copying container scripts from `containerfiles/scripts/` to `${HOTSTACK_DATA_DIR}/runtime/scripts/`
- Substituting environment-specific values (passwords, IPs, hostnames, DNS servers)
- Creating `clouds.yaml` in `${HOTSTACK_DATA_DIR}/` and copying to repo directory for convenience

**Note**: This step is automatically run by `sudo make start`, so you typically don't need to run it manually. However, you can run it explicitly if you:
- Changed environment variables in `.env` and want to regenerate configs without restarting services
- Want to verify configuration before starting services

The runtime directory structure created:
```
${HOTSTACK_DATA_DIR}/
├── runtime/
│   ├── config/     # All service configs with substituted values
│   └── scripts/    # Container entrypoint and utility scripts
└── clouds.yaml     # OpenStack client credentials
```

### Step 5: Start Services

```bash
sudo make start
```

This takes **~3 minutes** and will:
- Prepare runtime configuration (runs `make config` automatically)
- Create required data directories
- Start infrastructure services (DNS, HAProxy, MariaDB, Memcached, RabbitMQ)
- Start all OpenStack services

Expected output: Container IDs and some expected "not found" errors on first run (these are harmless).

### Step 6: Wait for Services to Be Healthy

```bash
# Check service status
sudo make status

# Or watch logs
sudo podman-compose logs -f
```

All services should show as "healthy" within 2-5 minutes. If any are unhealthy, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Step 7: Verify Deployment

```bash
# Setup OpenStack client credentials (clouds.yaml was auto-generated during 'make start')
# Use hotstack-os for regular user access or hotstack-os-admin for admin access
export OS_CLOUD=hotstack-os

# Verify services are working
openstack service list
openstack endpoint list
```

Your OpenStack cloud is now ready! You should see all services (keystone, nova, neutron, glance, cinder, heat, placement) listed.

## Using with HotStack

Once hotstack-os is running and verified, prepare it for HotStack scenarios:

### 1. Install OpenStack Client (Optional)

Install the OpenStack client packages on your host:

```bash
sudo make install-client
```

This installs:
- `python3-openstackclient` - Main OpenStack CLI
- `python3-heatclient` - Heat orchestration CLI

**Note**: You can also install these in a Python virtualenv if you prefer not to install system-wide.

### 2. Create HotStack Resources

```bash
make post-setup
```

This creates resources needed by HotStack scenarios:
- HotStack project and user (hotstack/hotstack)
- Quotas for hotstack project (40 cores, 100GB RAM, 1TB storage)
- Compute flavors (hotstack.small, medium, large, etc.) - shared/public
- Default private network (192.168.100.0/24) - shared
- Provider network (172.31.0.128/25) - shared, for floating IPs
- Router connecting private and external networks
- Security group rules (SSH, ICMP) for both admin and hotstack projects
- Test image (Cirros) - public
- HotStack images (controller, blank, nat64, iPXE) - downloaded from GitHub releases and uploaded

**Note**: Images are downloaded from the latest GitHub releases. If an image is not found, you may need to run the GitHub workflow to build and publish it first.

### 3. Create Application Credential

```bash
# Use the hotstack user for regular operations
export OS_CLOUD=hotstack-os
openstack application credential create hotstack-cred --unrestricted

# Or use the admin user for administrative tasks
export OS_CLOUD=hotstack-os-admin
```

Save the `id` and `secret` from the output.

### 4. Create Cloud Secret File

```bash
cat > ~/cloud-secret.yaml <<EOF
hotstack_cloud_secrets:
  auth_url: http://keystone.hotstack-os.local:5000
  application_credential_id: <ID_FROM_ABOVE>
  application_credential_secret: <SECRET_FROM_ABOVE>
  region_name: RegionOne
  interface: internal
  identity_api_version: 3
  auth_type: v3applicationcredential
EOF
```

### 5. Run HotStack Scenario

```bash
cd ../../  # Back to hotstack root

# Run any HotStack scenario
ansible-playbook bootstrap.yml \
  -e @scenarios/sno-2-bm/bootstrap_vars.yml \
  -e @~/cloud-secret.yaml
```

## Daily Usage

```bash
sudo make start   # Start all services (wait 2-5 minutes)
sudo make status  # Check service status
sudo make stop    # Stop all services
```

For additional commands (logs, restart, clean, etc.), see [README.md](README.md#management-commands).

## Troubleshooting

**Having issues?** See **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for detailed solutions to common problems.

## Next Steps

- See [README.md](README.md) for architecture, service endpoints, and limitations
- Use this cloud with HotStack scenarios to deploy OpenShift
