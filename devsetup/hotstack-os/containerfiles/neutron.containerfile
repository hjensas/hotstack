FROM localhost/hotstack-os-base-builder:latest AS builder

ARG OPENSTACK_BRANCH=stable/2025.1

# Clone and build Neutron from source
RUN git clone --depth 1 --branch ${OPENSTACK_BRANCH} \
        https://opendev.org/openstack/neutron /tmp/neutron && \
    cd /tmp/neutron && \
    pip3 install --no-cache-dir --break-system-packages \
        -c https://opendev.org/openstack/requirements/raw/branch/${OPENSTACK_BRANCH}/upper-constraints.txt \
        . pymysql python-memcached python-openstackclient && \
    mkdir -p /etc/neutron && \
    (cp /tmp/neutron/etc/neutron/api-paste.ini /etc/neutron/ || \
     cp /tmp/neutron/etc/api-paste.ini /etc/neutron/)

# Runtime stage
FROM localhost/hotstack-os-base:latest

ARG OPENSTACK_BRANCH=stable/2025.1
ARG SERVICE_TYPE=server
ARG APT_PROXY=""

# Configure apt proxy if provided (for apt-cacher-ng)
RUN if [ -n "$APT_PROXY" ]; then \
        echo "Acquire::http::Proxy \"$APT_PROXY\";" > /etc/apt/apt.conf.d/01proxy; \
    fi

# Install Neutron-specific runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openvswitch-common \
        ovn-common \
        iproute2 \
        iptables \
        ebtables \
        iputils-ping \
        dnsmasq \
        haproxy \
        netcat-openbsd \
        procps \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages and config from builder
COPY --from=builder /usr/local /usr/local
COPY --from=builder /etc/neutron /etc/neutron

# Create directories and neutron user
RUN mkdir -p /var/lib/neutron /run/neutron && \
    (useradd -m -d /var/lib/neutron -s /bin/bash neutron || true) && \
    chown -R neutron:neutron /var/lib/neutron /run/neutron

# Copy entrypoint scripts with permissions
COPY --chmod=644 scripts/common.sh /usr/local/lib/common.sh
COPY --chmod=755 scripts/neutron-server-entrypoint.sh /usr/local/bin/neutron-server-entrypoint.sh
COPY --chmod=755 scripts/neutron-ovn-metadata-agent-entrypoint.sh /usr/local/bin/neutron-ovn-metadata-agent-entrypoint.sh

USER neutron
WORKDIR /var/lib/neutron

# Entrypoint will be overridden in compose file
ENTRYPOINT ["/usr/local/bin/neutron-server-entrypoint.sh"]
