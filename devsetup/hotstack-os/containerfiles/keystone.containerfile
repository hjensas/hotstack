FROM localhost/hotstack-os-base-builder:latest AS builder

ARG OPENSTACK_BRANCH=stable/2025.1

# Clone and build Keystone from source
RUN git clone --depth 1 --branch ${OPENSTACK_BRANCH} \
        https://opendev.org/openstack/keystone /tmp/keystone && \
    cd /tmp/keystone && \
    pip3 install --no-cache-dir --break-system-packages \
        -c https://opendev.org/openstack/requirements/raw/branch/${OPENSTACK_BRANCH}/upper-constraints.txt \
        . uwsgi pymysql python-memcached python-openstackclient

# Runtime stage
FROM localhost/hotstack-os-base:latest

ARG OPENSTACK_BRANCH=stable/2025.1

# Copy installed packages from builder
COPY --from=builder /usr/local /usr/local

# Create directories with proper ownership
RUN mkdir -p /etc/keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys \
        /var/log/keystone && \
    chown -R openstack:openstack /etc/keystone

# Copy uwsgi configuration with ownership
COPY --chown=openstack:openstack configs/keystone-uwsgi.ini /etc/keystone/keystone-uwsgi.ini

# Copy scripts with permissions
COPY --chmod=644 scripts/common.sh /usr/local/lib/common.sh
COPY --chmod=755 scripts/keystone-entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=10 \
    CMD curl -f http://localhost:5000/v3 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
