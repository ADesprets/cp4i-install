# -------------------------------------------------------------------
# update these to match your Event Endpoint Management instance
# -------------------------------------------------------------------
# MANAGER_CR=eventendpointmanagers.eventendpointmanager.apiconnect.ibm.com
# NAMESPACE=eventendpointmanagement
# INSTANCE=eem
MANAGER_CR=managementclusters.management.apiconnect.ibm.com
NAMESPACE=cp4i
INSTANCE=cp4i-apic-mgmt

echo "\n\033[1;33m getting SSL/TLS details for Event Gateway in...\033[0m"
echo "namespace      : $NAMESPACE"
echo "instance       : $INSTANCE"


# -------------------------------------------------------------------
# verify dependencies are all available
# -------------------------------------------------------------------
echo "\n\033[1;33m checking for script dependencies...\033[0m"
check_dependency () {
  if hash $1 2>/dev/null; then
    echo "verified $1"
  else
    echo "$1 could not be found"
    exit
  fi
}
check_dependency "keytool"
check_dependency "oc"
check_dependency "openssl"


# -------------------------------------------------------------------
# cleanup from previous runs
# -------------------------------------------------------------------
rm my.p12


# -------------------------------------------------------------------
# get Event Gateway connection address
# -------------------------------------------------------------------
echo "\n\033[1;33m querying openshift for gateway connection address...\033[0m"
GATEWAY_ROUTE=$($MY_CLUSTER_COMMAND get route -n $NAMESPACE -lapp.kubernetes.io/instance=$INSTANCE-egw -lapp.kubernetes.io/name=event-gateway -o name | grep gw-client)
GATEWAY_ADDRESS=$($MY_CLUSTER_COMMAND get $GATEWAY_ROUTE -n $NAMESPACE -o jsonpath="{.spec.host}")
echo "gateway address: $GATEWAY_ADDRESS"


# -------------------------------------------------------------------
# setting up truststore
# -------------------------------------------------------------------
echo "\n\033[1;33m putting the certificate presented by the Gateway into a truststore...\033[0m"
echo -n | openssl s_client -connect $GATEWAY_ADDRESS:443 -servername $GATEWAY_ADDRESS -showcerts | openssl x509 > bootstrap.crt
keytool -import -noprompt \
        -alias bootstrapca \
        -file bootstrap.crt \
        -keystore my.p12 -storetype pkcs12 \
        -storepass password
rm bootstrap.crt


# -------------------------------------------------------------------
# outputting results
# -------------------------------------------------------------------
echo "\n\033[1;33m connection properties:\033[0m"
echo "\033[1m  bootstrap.servers=$GATEWAY_ADDRESS:443\033[0m"
echo "\033[1m  ssl.truststore.location=my.p12\033[0m"
echo "\033[1m  ssl.truststore.type=PKCS12\033[0m"
echo "\033[1m  ssl.truststore.password=password\033[0m"
echo "\033[1m  ssl.endpoint.identification.algorithm=\033[0m"
