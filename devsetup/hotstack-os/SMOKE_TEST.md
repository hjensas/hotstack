# HotStack-OS Smoke Test

The smoke test validates the HotStack-OS deployment by creating a comprehensive Heat stack with various OpenStack resources and testing connectivity.

## Overview

The smoke test creates a minimal but thorough test environment that exercises key OpenStack services and resource types used in real HotStack scenarios.

### Resources Created

The Heat stack (`smoke-test-template.yaml`) includes:

**Networking:**
- 2 networks (test-net, vlan-net)
- 2 subnets with different configurations (DHCP enabled/disabled)
- 1 router with external gateway
- Trunk port with VLAN subport (segmentation_id: 100)
- 2 floating IPs

**Compute:**
- Instance 1: Volume boot with extra volume via `block_device_mapping`
- Instance 2: Ephemeral boot (image-based)
- Cloud-init configuration for both instances

**Storage:**
- Boot volume (5GB) for instance 1
- Extra volume (3GB) attached to instance 1
- Instance 2 uses ephemeral disk

**Security:**
- SSH keypair for instance access

### Test Coverage

This smoke test validates:
- ✅ Heat orchestration service
- ✅ Network creation and router connectivity
- ✅ Volume creation and attachment
- ✅ Boot from volume
- ✅ Ephemeral boot from image
- ✅ Trunk port with VLAN subport
- ✅ Floating IP allocation and association
- ✅ Cloud-init configuration
- ✅ Instance launch and basic connectivity (ICMP)

## Usage

### Prerequisites

1. Complete HotStack-OS setup:
   ```bash
   sudo make build
   sudo make setup
   sudo make start
   make post-setup  # Do NOT use sudo - must run as your user
   ```

2. Ensure you have an SSH key pair:
   ```bash
   # Generate if needed (ed25519 - modern default, recommended)
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

   # Or RSA (traditional)
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   ```

   **Important**: Do not run `post-setup` or `smoke-test` with sudo.

### Running the Smoke Test

**Simple run** (automatic cleanup):
```bash
make smoke-test
```

This will:
1. Create SSH keypair in OpenStack (auto-detects `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`)
2. Create Heat stack with all test resources
3. Verify all resources are in CREATE_COMPLETE state
4. Wait 30 seconds for instances to boot
5. Test ICMP connectivity to both floating IPs
6. Automatically delete the stack

**Keep stack for debugging**:
```bash
./scripts/smoke-test.py --keep-stack
```

**Manual cleanup**:
```bash
make smoke-test-cleanup
# or
./scripts/smoke-test.py --cleanup-only
```

### Command-Line Options

```bash
./scripts/smoke-test.py --help

Options:
  --cloud CLOUD                   OpenStack cloud name (default: hotstack-os)
  --stack-name NAME              Heat stack name (default: hotstack-smoke-test)
  --keypair-name NAME            SSH keypair name (default: hotstack-smoke-test)
  --ssh-public-key PATH          SSH public key path (default: auto-detect ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)
  --image-name IMAGE             Image for instances (default: cirros)
  --flavor-name FLAVOR           Flavor for instances (default: hotstack.small)
  --external-network NETWORK     External network (default: external)
  --keep-stack                   Keep stack after test (for debugging)
  --no-test-connectivity         Skip ping tests
  --cleanup-only                 Only cleanup existing stack
```

### Example: Custom Configuration

```bash
# Use different image and flavor
./scripts/smoke-test.py \
  --image-name CentOS-Stream-GenericCloud-9 \
  --flavor-name hotstack.medium \
  --keep-stack

# Skip connectivity tests (faster)
./scripts/smoke-test.py --no-test-connectivity
```

## Smoke Test Workflow

### Step-by-Step Process

1. **SSH Keypair Setup**
   - Checks if keypair exists in OpenStack
   - If not, uploads public key (auto-detects `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`)
   - Used for SSH access to test instances

2. **Stack Creation**
   - Deletes existing smoke test stack (if any)
   - Creates new Heat stack from `smoke-test-template.yaml`
   - Waits up to 600 seconds for CREATE_COMPLETE status

3. **Resource Verification**
   - Lists all stack resources
   - Verifies each resource is in CREATE_COMPLETE state
   - Reports any failed resources

4. **Stack Outputs**
   - Displays all Heat stack outputs:
     - Instance names and IPs (fixed and floating)
     - Network and router IDs
     - Volume IDs

5. **Connectivity Tests** (optional)
   - Waits 30 seconds for instances to boot
   - Pings both floating IPs (60 second timeout each)
   - Reports success/failure for each test

6. **Cleanup** (unless `--keep-stack`)
   - Deletes the Heat stack
   - Waits for deletion to complete (300 second timeout)

### Expected Output

```
=== HotStack-OS Smoke Test ===

✓ Connected to OpenStack cloud 'hotstack-os'
✓ Keypair 'hotstack-smoke-test' already exists
ℹ Creating stack 'hotstack-smoke-test'...
ℹ Waiting for stack creation to complete...
✓ Stack 'hotstack-smoke-test' created successfully
ℹ Verifying stack resources...
✓ All 17 stack resources created successfully

ℹ Stack outputs:
  instance1_name: smoke-test-instance1-volume-boot
  instance1_floating_ip: 172.31.0.150
  instance1_fixed_ip: 192.168.200.10
  instance2_name: smoke-test-instance2-ephemeral-boot
  instance2_floating_ip: 172.31.0.151
  instance2_fixed_ip: 192.168.200.11
  network_id: abc-123-xyz
  router_id: def-456-uvw
  volumes:
    boot_volume: ghi-789-rst
    extra_volume: jkl-012-mno

ℹ Testing connectivity...
ℹ Waiting 30 seconds for instances to boot...
ℹ Testing ICMP connectivity to 172.31.0.150...
✓ Successfully pinged 172.31.0.150
ℹ Testing ICMP connectivity to 172.31.0.151...
✓ Successfully pinged 172.31.0.151
✓ All connectivity tests passed

ℹ Deleting stack 'hotstack-smoke-test'...
✓ Stack 'hotstack-smoke-test' deleted successfully

✓ Smoke test completed successfully!
```

## Troubleshooting

### Stack Creation Fails

If stack creation fails:

```bash
# Keep the failed stack for inspection
./scripts/smoke-test.py --keep-stack

# Check stack status
openstack --os-cloud hotstack-os stack show hotstack-smoke-test

# Check stack resources
openstack --os-cloud hotstack-os stack resource list hotstack-smoke-test

# Check failed resource details
openstack --os-cloud hotstack-os stack resource show hotstack-smoke-test <resource-name>

# View stack events
openstack --os-cloud hotstack-os stack event list hotstack-smoke-test

# Manual cleanup
make smoke-test-cleanup
```

### Connectivity Tests Fail

Ping failures may occur if:
- Instances are still booting (wait longer or use `--keep-stack` and test manually)
- Security group rules are missing (check with `openstack security group rule list`)
- Floating IP association is incomplete

To debug:
```bash
# Keep stack and test manually
./scripts/smoke-test.py --keep-stack

# Check instance status
openstack --os-cloud hotstack-os server list
openstack --os-cloud hotstack-os server show smoke-test-instance1-volume-boot

# Check console logs
openstack --os-cloud hotstack-os console log show smoke-test-instance1-volume-boot

# Manual ping test
ping -c 4 <floating-ip>

# SSH into instance (if cirros)
ssh cirros@<floating-ip>  # password: gocubsgo
```

### SSH Keypair Issues

If SSH keypair creation fails:

```bash
# Check if key exists
ls -la ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub

# Generate new key if needed (ed25519 - recommended)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Or RSA (traditional)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa

# Run post-setup again to upload keypair (do NOT use sudo)
make post-setup
```

## Integration with CI/CD

The smoke test is designed to be easily integrated into CI/CD pipelines:

```bash
# Example CI script
#!/bin/bash
set -e

# Setup
sudo make build
sudo make setup
sudo make start
make post-setup

# Run smoke test (exits with non-zero on failure)
make smoke-test

echo "✓ All tests passed"
```

## Extending the Smoke Test

To add more test resources or scenarios:

1. Edit `smoke-test-template.yaml` to add resources
2. Update `smoke-test.py` if additional validation is needed
3. Consider adding test-specific parameters to the template

Example additions:
- Server groups (affinity/anti-affinity)
- Additional volumes and snapshots
- IPv6 networking
- Multiple availability zones
- Load balancers (Octavia)

## Related Documentation

- [README.md](README.md) - Main HotStack-OS documentation
- [QUICKSTART.md](QUICKSTART.md) - Quick setup guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting
- [HotStack Scenarios](../../docs/hotstack_scenarios.md) - Full scenario structure
