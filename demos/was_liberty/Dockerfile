FROM icr.io/appcafe/websphere-liberty:24.0.0.5-kernel-java17-openj9-ubi

COPY --chown=1001:0 /src/main/liberty/config /config

RUN features.sh

COPY --chown=1001:0 target/*.war /config/apps

RUN configure.sh
