#!/bin/bash
################################################
# Entrypoint of the IBM MQ stand-alone Web Server container
# Mounted inputs:
#   /config/mqwebuser.xml   : console security (ConfigMap)
#   /mq-certs/*.pem         : CA / server certificates of the queue managers (Secret)
#   /ccdt/<QMGR>.json       : one JSON CCDT per queue manager, file name = queue manager name (ConfigMap)
#   MQWEB_TRUSTSTORE_PWD    : truststore password (Secret, env)
################################################
set -e

export PATH=${MQWEB_HOME}/bin:$PATH
SRV=${MQ_OVERRIDE_DATA_PATH}/web/installations/MQWEBINST/servers/mqweb
TRUSTSTORE=${MQ_OVERRIDE_DATA_PATH}/mq-truststore.p12

# Create the mqweb server once (the data dir lives on the PVC)
# There is no crtmqweb in the stand-alone package: the server dir is created from the samples (as crtmqdir does on a full install)
if [ ! -f "$SRV/server.xml" ]; then
  echo "[entrypoint] Creating mqweb server in ${SRV}"
  mkdir -p "$SRV"
  cp ${MQWEB_HOME}/samp/web/server.xml ${MQWEB_HOME}/samp/web/jvm.options ${MQWEB_HOME}/samp/web/mqwebuser.xml "$SRV/"
fi
# The samples are read-only, setmqweb must be able to update mqwebuser.xml
chmod -R ug+w "${MQ_OVERRIDE_DATA_PATH}/web"

# Overlay the security configuration from the ConfigMap, then the network properties
[ -f /config/mqwebuser.xml ] && cp /config/mqwebuser.xml "$SRV/mqwebuser.xml"
setmqweb properties -k httpHost -v '*'
setmqweb properties -k httpsPort -v 9443

# Rebuild the truststore used to connect to the queue managers (TLS channels)
KEYTOOL=${MQWEB_HOME}/java/jre64/jre/bin/keytool
rm -f "$TRUSTSTORE"
for lf_cert in /mq-certs/*.pem; do
  [ -f "$lf_cert" ] || continue
  echo "[entrypoint] Adding $(basename "$lf_cert") to the truststore"
  "$KEYTOOL" -importcert -noprompt -alias "$(basename "$lf_cert" .pem)" -file "$lf_cert" \
             -keystore "$TRUSTSTORE" -storetype PKCS12 -storepass "${MQWEB_TRUSTSTORE_PWD}"
done
if [ -f "$TRUSTSTORE" ]; then
  setmqweb remote -globalTrustStorePath "$TRUSTSTORE" -globalTrustStorePassword "${MQWEB_TRUSTSTORE_PWD}"
fi

# (Re)register the remote queue managers declared in the CCDT ConfigMap
for lf_ccdt in /ccdt/*.json; do
  [ -f "$lf_ccdt" ] || continue
  lf_qmgr=$(basename "$lf_ccdt" .json)
  echo "[entrypoint] Registering remote queue manager ${lf_qmgr}"
  setmqweb remote -d -uniqueName "${lf_qmgr}" >/dev/null 2>&1 || true
  # ccdtURL must be a plain path (a file:// URL is rejected with MQWB1159E)
  # A failed registration must not prevent the console from starting
  setmqweb remote add -uniqueName "${lf_qmgr}" -qmgrName "${lf_qmgr}" -ccdtURL "${lf_ccdt}" \
    || echo "[entrypoint] WARNING: registration of ${lf_qmgr} failed, check ${lf_ccdt}"
done

strmqweb
# strmqweb backgrounds Liberty: stream the logs to keep the pod alive, and stop the server cleanly on SIGTERM
trap 'echo "[entrypoint] Stopping mqweb server"; endmqweb; kill $lf_tail_pid 2>/dev/null; exit 0' TERM INT
tail -F "$SRV/logs/messages.log" &
lf_tail_pid=$!
wait $lf_tail_pid
