FROM icr.io/appcafe/open-liberty:kernel-slim-java11-openj9-ubi

COPY --chown=1001:0 src/main/liberty/config /resources/
RUN features.sh
COPY --chown=1001:0 target/guide-openliberty-operator-intro-system.war /resources/apps
RUN configure.sh
