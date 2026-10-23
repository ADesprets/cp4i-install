FROM icr.io/appcafe/websphere-liberty:26.0.0.6-kernel-java25-openj9-ubi-minimal

COPY --chown=1001:0 /src/main/liberty/config /config

RUN features.sh

COPY --chown=1001:0 target/*.war /config/apps

# Copy PostgreSQL JDBC driver to shared resources (Liberty best practice)
COPY --chown=1001:0 target/*.jar /opt/ibm/wlp/usr/shared/resources

# Copy server.xml with PostgreSQL configuration
COPY --chown=1001:0 resources/server.xml /config/

RUN configure.sh
