FROM debian:bookworm-slim

ARG SERVICE_TYPE=northd

# Install OVN and OpenvSwitch
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ovn-central \
        ovn-host \
        openvswitch-common \
        iproute2 \
        curl \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create directories (rootful containers run as root, no permission issues)
RUN mkdir -p /etc/ovn /var/lib/ovn /run/ovn

# Copy entrypoint scripts with permissions
COPY --chmod=755 scripts/ovn-northd-entrypoint.sh /usr/local/bin/ovn-northd-entrypoint.sh
COPY --chmod=755 scripts/ovn-controller-entrypoint.sh /usr/local/bin/ovn-controller-entrypoint.sh

# Entrypoint will be set in compose file
