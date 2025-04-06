# Use Bitnami OpenLDAP as the base image
#FROM bitnami/openldap:2.6.8
FROM docker.io/bitnami/openldap:2.6.8

# Switch to root user to modify permissions
USER 0

# Remove capabilities from slapd
RUN setcap -r /opt/bitnami/openldap/sbin/slapd

# Switch back to non-root user (default for Bitnami)
USER 1001

#
#FROM docker.io/bitnami/openldap:2.6.8
#
## Instead of removing all capabilities, just remove dangerous ones
#USER 0
#RUN setcap -r /opt/bitnami/openldap/sbin/slapd && \
#    setcap 'cap_net_bind_service=+ep' /opt/bitnami/openldap/sbin/slapd
#USER 1001
#


#FROM docker.io/bitnami/openldap:2.6.8
#
#USER 0
## Instead of removing all capabilities, keep essential ones
#RUN setcap 'cap_net_bind_service=+ep' /opt/bitnami/openldap/sbin/slapd && \
#    chown -R 1001:1001 /bitnami/openldap && \
#    chmod -R g+rwX /bitnami/openldap
#USER 1001


#FROM docker.io/bitnami/openldap:2.6.8
#
## Switch to a user ID within your cluster's range
#USER 1000850000
#
## No capability changes needed since we'll use the container's default

#FROM docker.io/bitnami/openldap:2.6.8
#
#USER 0
## Pre-create configuration files
#RUN mkdir -p /opt/bitnami/openldap/share && \
#    touch /opt/bitnami/openldap/share/slapd.ldif && \
#    chown -R 1001:1001 /opt/bitnami/openldap/share && \
#    chmod -R g+rwX /opt/bitnami/openldap/share
#USER 1001