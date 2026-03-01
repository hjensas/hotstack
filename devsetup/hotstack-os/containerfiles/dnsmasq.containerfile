# DNS service for hotstack-os
# Provides name resolution for OpenStack services to VMs
FROM docker.io/library/alpine:3.21

# Install dnsmasq
RUN apk add --no-cache dnsmasq

# Create config directory
RUN mkdir -p /etc/dnsmasq.d

# Expose DNS port
EXPOSE 53/udp 53/tcp

# Run dnsmasq in foreground
CMD ["dnsmasq", "--no-daemon", "--log-facility=-"]
