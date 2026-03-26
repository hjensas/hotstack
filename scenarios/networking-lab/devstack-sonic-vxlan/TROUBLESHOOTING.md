# Troubleshooting

## Switches Not Booting
- Check OpenStack console logs for the switch instances
- Verify the `hotstack-sonic` image is properly configured
- Check cloud-init logs: `sudo journalctl -u cloud-init`
- Verify the SONiC container is running: `sudo systemctl status sonic.service`

## Switches Not Reachable
- Verify management interface configuration on switches: `show interface Management0` or `ip addr show eth0`
- Check DNS resolution from controller: `dig spine01.stack.lab @192.168.32.254`
- Ensure routes are configured in management VRF: `show ip route vrf mgmt`
- Check that eth0 has the correct IP: `ip addr show eth0`

## OSPF Not Working
- Access FRR shell: `podman exec sonic vtysh`
- Verify OSPF is running: `show ip ospf`
- Check OSPF neighbors: `show ip ospf neighbor`
- Verify interface MTU matches (1442): `show interface Ethernet0`
- Check OSPF interface configuration: `show ip ospf interface`

## BGP EVPN Not Working
- Access FRR shell: `podman exec sonic vtysh`
- Verify BGP is running: `show bgp summary`
- Check BGP EVPN neighbors: `show bgp l2vpn evpn summary`
- Verify loopback reachability: `ping 10.255.255.1 -I 10.255.255.3`
- Check BGP configuration: `show running-config`

## Devstack Deployment Issues
- Check network connectivity on trunk0: `ip link show trunk0`
- Verify trunk0 is added to br-ex: `sudo ovs-vsctl show`
- Review devstack logs: `/opt/stack/logs/stack.sh.log`
- Check neutron-server logs: `sudo journalctl -u devstack@q-svc`

## ML2 Not Configuring Switches
- Verify networking-generic-switch credentials in `/etc/neutron/plugins/ml2/ml2_conf_genericswitch.ini`
- Check neutron-server can reach switches: `ping 192.168.32.13` from devstack
- Review neutron-server logs for genericswitch errors: `sudo journalctl -u devstack@q-svc | grep genericswitch`
- Test SSH connectivity manually: `ssh admin@192.168.32.13` from devstack
- Test SSH connectivity manually: `ssh admin@192.168.32.13` from devstack

## Container-Specific Issues
- Check SONiC container status: `sudo podman ps`
- View container logs: `sudo podman logs sonic`
- Restart SONiC service: `sudo systemctl restart sonic.service`
- Verify SONiC image is loaded: `sudo podman images | grep sonic`
- Access SONiC CLI: `sudo podman exec -it sonic bash`
