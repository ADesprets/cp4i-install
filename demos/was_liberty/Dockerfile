FROM icr.io/appcafe/websphere-liberty:26.0.0.6-kernel-java25-openj9-ubi-minimal

COPY --chown=1001:0 /src/main/liberty/config /config

RUN features.sh

COPY --chown=1001:0 target/*.war /config/apps

RUN configure.sh
