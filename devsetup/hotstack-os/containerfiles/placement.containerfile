FROM localhost/hotstack-os-base-builder:latest AS builder

ARG OPENSTACK_BRANCH=stable/2025.1

# Clone and build Placement from source
RUN git clone --depth 1 --branch ${OPENSTACK_BRANCH} \
        https://opendev.org/openstack/placement /tmp/placement && \
    cd /tmp/placement && \
    pip3 install --no-cache-dir --break-system-packages \
        -c https://opendev.org/openstack/requirements/raw/branch/${OPENSTACK_BRANCH}/upper-constraints.txt \
        . uwsgi pymysql python-memcached python-openstackclient

# Runtime stage
FROM localhost/hotstack-os-base:latest

ARG OPENSTACK_BRANCH=stable/2025.1

# Copy installed packages from builder
COPY --from=builder /usr/local /usr/local

# Create directories with proper ownership
RUN mkdir -p /etc/placement /var/log/placement && \
    chown -R openstack:openstack /etc/placement /var/log/placement

# Copy uwsgi configuration with ownership
COPY --chown=openstack:openstack configs/placement-uwsgi.ini /etc/placement/placement-uwsgi.ini

# Copy WSGI application loader
COPY --chmod=755 scripts/placement-wsgi.py /usr/local/bin/placement-wsgi.py

# Copy entrypoint scripts with permissions
COPY --chmod=755 scripts/placement-entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 8778

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
