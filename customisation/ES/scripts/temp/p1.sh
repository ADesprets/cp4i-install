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
check_dependency "apic"
check_dependency "curl"
check_dependency "jq"
check_dependency "keytool"
check_dependency "oc"


# -------------------------------------------------------------------
# cleanup from previous runs
# -------------------------------------------------------------------
rm my.p12


# -------------------------------------------------------------------
# log into apic CLI
# -------------------------------------------------------------------
echo "\n\033[1;33m logging into apic CLI...\033[0m"
CP4I_NAMESPACE=$(oc get zenservice -A -o jsonpath='{..namespace}')

echo "creating IAM token"
CS_HOST=https://$(oc -n kube-public get cm ibmcloud-cluster-info -o jsonpath='{.data.cluster_address}')
IAM_PASSWORD=$(oc get secret -n ibm-common-services platform-auth-idp-credentials -o jsonpath='{..admin_password}' | base64 -d)
IAM_TOKEN=$(curl -k -s -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -d "grant_type=password&username=admin&password=${IAM_PASSWORD}&scope=openid" "${CS_HOST}"/v1/auth/identitytoken | jq -r .access_token)

echo "Cluster host: $CS_HOST"
echo "IAM Password: $IAM_PASSWORD"
echo "IAM token: $IAM_TOKEN"


echo "creating Zen token"
ZEN_HOST=https://$(oc get route -n $CP4I_NAMESPACE cpd -o=jsonpath='{.spec.host}')
ZEN_TOKEN=$(curl -k -s "${ZEN_HOST}"/v1/preauth/validateAuth -H "username: admin" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)

echo "ZEN host: $ZEN_HOST"
echo "ZEN token: $ZEN_TOKEN"

echo "downloading apic config json file"
PLATFORM_API_URL=$(oc get $MANAGER_CR $INSTANCE -n $NAMESPACE -o=jsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}')

echo "PLATFORM API URL: $PLATFORM_API_URL"

TOOLKIT_CREDS_URL="$PLATFORM_API_URL/cloud/settings/toolkit-credentials"
curl -k $TOOLKIT_CREDS_URL -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -o creds.json
yes | apic client-creds:set creds.json

echo "creating apic API key"
APIC_APIKEY=$(curl -k -s -X POST "${PLATFORM_API_URL}"/cloud/api-keys -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -d '{"client_type":"toolkit","description":"Tookit API key"}' | jq -r .api_key)

echo "logging into API manager"
APIM_ENDPOINT=$(oc -n $NAMESPACE get mgmt $INSTANCE -o jsonpath="https://{.status.zenRoute}")
yes n | apic login --context provider --server $APIM_ENDPOINT --sso --apiKey $APIC_APIKEY
rm creds.json


# -------------------------------------------------------------------
# setting up truststore
# -------------------------------------------------------------------
echo "\n\033[1;33m retrieving keystore from APIC and putting into a truststore...\033[0m"
apic keystores:get \
  --server $APIM_ENDPOINT \
  --org admin \
  --format json \
  tls-server-for-gateway-services-default-keystore \
  --output -  | jq -r .public_certificate_entry.pem > gateway.pem
keytool -import -noprompt \
        -alias gatewayca \
        -file gateway.pem \
        -keystore my.p12 -storetype pkcs12 \
        -storepass password
rm gateway.pem


# -------------------------------------------------------------------
# get Event Gateway connection address
# -------------------------------------------------------------------
echo "\n\033[1;33m querying openshift for gateway connection address...\033[0m"
GATEWAY_ROUTE=$(oc get route -n $NAMESPACE -lapp.kubernetes.io/instance=$INSTANCE-egw -lapp.kubernetes.io/name=event-gateway -o name | grep gw-client)
GATEWAY_ADDRESS=$(oc get $GATEWAY_ROUTE -n $NAMESPACE -o jsonpath="{.spec.host}")
echo "gateway address: $GATEWAY_ADDRESS"


# -------------------------------------------------------------------
# outputting results
# -------------------------------------------------------------------
echo "\n\033[1;33m connection properties:\033[0m"
echo "\033[1m  bootstrap.servers=$GATEWAY_ADDRESS:443\033[0m"
echo "\033[1m  ssl.truststore.location=my.p12\033[0m"
echo "\033[1m  ssl.truststore.type=PKCS12\033[0m"
echo "\033[1m  ssl.truststore.password=password\033[0m"
echo "\033[1m  ssl.endpoint.identification.algorithm=\033[0m"
