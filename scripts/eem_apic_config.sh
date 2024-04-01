#!/bin/sh

# This script integrate EEM with APIC.

# This script requires the oc command being installed in your environment
# This script requires the jq utility being installed in your environment
# This script requires the apic command being installed in your environment


if [ ! command -v oc &> /dev/null ]; then echo "oc could not be found"; exit 1; fi;
if [ ! command -v jq &> /dev/null ]; then echo "jq could not be found"; exit 1; fi;
if [ ! command -v apic &> /dev/null ]; then echo "apic could not be found"; exit 1; fi;
###################
# INPUT VARIABLES #
###################
starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

#assumptions on the name od the file
read_config_file "${scriptdir}cp4i.properties"

read_config_file "${scriptdir}scripts/eem.custom.properties"

if [ ! -d ${EEM_GEN_CUSTOMDIR}config ]; then
    mkdir -p ${EEM_GEN_CUSTOMDIR}config
fi
if [ ! -d ${EEM_GEN_CUSTOMDIR}script ]; then
    mkdir -p ${EEM_GEN_CUSTOMDIR}script
fi
generate_files $EEM_TMPL_CUSTOMDIR $EEM_GEN_CUSTOMDIR false


#MY_APIC_INSTANCE_NAME='apic'
#MY_APIC_PROJECT='apic'
#APIC_REALM='admin/default-idp-1'
#MY_EEM_PROJECT='event'
#MY_EEM_INSTANCE_NAME='eem-demo'

#part eg registration
#MY_EGW_INSTANCE_NAME='eg-demo'


APIC_MGMT_SERVER=$(oc get route "${MY_APIC_INSTANCE_NAME}-mgmt-platform-api" -n $MY_APIC_PROJECT -o jsonpath="{.spec.host}")
APIC_ADMIN_PWD=$(oc get secret "${MY_APIC_INSTANCE_NAME}-mgmt-admin-pass" -n $MY_APIC_PROJECT -o jsonpath="{.data.password}"| base64 -d)

APIC_JWKS_URL=$(oc get apiconnectcluster $MY_APIC_INSTANCE_NAME -n $MY_APIC_PROJECT -ojsonpath='{.status.endpoints[?(@.name=="jwksUrl")].uri}')
APIC_PLATFORM_API=$(oc get apiconnectcluster $MY_APIC_INSTANCE_NAME -n $MY_APIC_PROJECT -ojsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}' | cut -b 9- | cut -d/ -f1)
echo -n | openssl s_client -connect $APIC_PLATFORM_API:443 -servername $APIC_PLATFORM_API -showcerts | openssl x509 > ${EEM_GEN_CUSTOMDIR}script/${MY_APIC_INSTANCE_NAME}-platform-api.pem
oc create secret generic ${MY_APIC_INSTANCE_NAME}-cpd --from-file=ca.crt=${EEM_GEN_CUSTOMDIR}script/${MY_APIC_INSTANCE_NAME}-platform-api.pem -n ${MY_EEM_PROJECT}
oc get EventEndpointManagement ${MY_EEM_INSTANCE_NAME} -n ${MY_EEM_PROJECT} -o json \
  | jq --arg MY_APIC_INSTANCE_NAME $MY_APIC_INSTANCE_NAME \
       --arg APIC_JWKS_URL $APIC_JWKS_URL \
  '.spec.manager.apic.jwks += {"endpoint": ($APIC_JWKS_URL)} | 
  .spec.manager.apic += {"clientSubjectDN":"CN=ingress-ca"} | 
  .spec.manager.tls += {"trustedCertificates":[{"certificate":"ca.crt","secretName":($MY_APIC_INSTANCE_NAME + "-cpd")}]}' \
  | oc apply -f -
oc get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -n ${MY_APIC_PROJECT} -o jsonpath="{.data.ca\.crt}" | base64 -D > ${EEM_GEN_CUSTOMDIR}script/${MY_APIC_INSTANCE_NAME}-ca.pem
oc get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -n ${MY_APIC_PROJECT} -o jsonpath="{.data.tls\.crt}" | base64 -D > ${EEM_GEN_CUSTOMDIR}script/${MY_APIC_INSTANCE_NAME}-tls-crt.pem
oc get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -n ${MY_APIC_PROJECT} -o jsonpath="{.data.tls\.key}" | base64 -D > ${EEM_GEN_CUSTOMDIR}script/${MY_APIC_INSTANCE_NAME}-tls-key.pem
APIC_MGMT_SERVER=$(oc get route "${MY_APIC_INSTANCE_NAME}-mgmt-platform-api" -n $MY_APIC_PROJECT -o jsonpath="{.spec.host}")
APIC_ADMIN_PWD=$(oc get secret "${MY_APIC_INSTANCE_NAME}-mgmt-admin-pass" -n $MY_APIC_PROJECT -o jsonpath="{.data.password}"| base64 -d)
#################
# LOGIN TO APIC #
#################
echo "Login to APIC with CMC Admin User..."
apic client-creds:clear
apic login --server $APIC_MGMT_SERVER --realm $APIC_REALM -u $APIC_ADMIN_USER -p $APIC_ADMIN_PWD



### Create keystore
cat ${EEM_GEN_CUSTOMDIR}script/$MY_APIC_INSTANCE_NAME-tls-crt.pem ${EEM_GEN_CUSTOMDIR}script/$MY_APIC_INSTANCE_NAME-tls-key.pem > ${EEM_GEN_CUSTOMDIR}script/$MY_APIC_INSTANCE_NAME-tls-combined.pem
APIC_CERT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ${EEM_GEN_CUSTOMDIR}script/$MY_APIC_INSTANCE_NAME-tls-combined.pem)
( echo "cat <<EOF" ; cat ${EEM_GEN_CUSTOMDIR}config/template-eem-apic-keystore.json ;) | \
    MY_APIC_INSTANCE_NAME=${MY_APIC_INSTANCE_NAME} \
    APIC_CERT=${APIC_CERT} \
    sh > ${EEM_GEN_CUSTOMDIR}script/eem-apic-keystore.json
apic keystores:create --server $APIC_MGMT_SERVER --org $APIC_ADMIN_ORG --format json ${EEM_GEN_CUSTOMDIR}script/eem-apic-keystore.json
### Create Truststore
APIC_CERT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ${EEM_GEN_CUSTOMDIR}script/$MY_APIC_INSTANCE_NAME-ca.pem)
( echo "cat <<EOF" ; cat ${EEM_GEN_CUSTOMDIR}config/template-eem-apic-truststore.json ;) | \
    MY_APIC_INSTANCE_NAME=${MY_APIC_INSTANCE_NAME} \
    APIC_CERT=${APIC_CERT} \
    sh > ${EEM_GEN_CUSTOMDIR}script/eem-apic-truststore.json
apic truststores:create --server $APIC_MGMT_SERVER --org $APIC_ADMIN_ORG --format json ${EEM_GEN_CUSTOMDIR}script/eem-apic-truststore.json
### Create TLS-Client-Profile
KEYSTORE_URL=$(apic keystores:get eem-keystore --server $APIC_MGMT_SERVER --org $APIC_ADMIN_ORG | awk '{print$3}')
TRUSTSTORE_URL=$(apic truststores:get eem-truststore --server $APIC_MGMT_SERVER --org $APIC_ADMIN_ORG | awk '{print$3}')
( echo "cat <<EOF" ; cat ${EEM_GEN_CUSTOMDIR}config/template-eem-apic-tls-client-profile.json ;) | \
    KEYSTORE_URL=${KEYSTORE_URL} \
    TRUSTSTORE_URL=${TRUSTSTORE_URL} \
    sh > ${EEM_GEN_CUSTOMDIR}script/eem-apic-tls-client-profile.json
apic tls-client-profiles:create --server $APIC_MGMT_SERVER --org $APIC_ADMIN_ORG --format json ${EEM_GEN_CUSTOMDIR}script/eem-apic-tls-client-profile.json




### Register the event gateway
EEM_MANAGER_APIC_HOST=$(oc get route $MY_EEM_INSTANCE_NAME-ibm-eem-apic -n $MY_EEM_PROJECT --template='{{ .spec.host }}')
EEM_GATEWAY_RT_HOST=$(oc get route $MY_EGW_INSTANCE_NAME-ibm-egw-rt -n $MY_EEM_PROJECT --template='{{ .spec.host }}')

MY_APIC_INSTANCE_NAME_TLS_CLIENT_PROFILE_URL=$(apic tls-client-profiles:list-all --server $APIC_MGMT_SERVER --org $APIC_ADMIN_ORG  | grep eem-tls-client-profile | awk '{print$2}')
DEFAULT_TLS_SERVER_PROFILE_URL=$(apic tls-server-profiles:list-all --server $APIC_MGMT_SERVER --org $APIC_ADMIN_ORG | grep tls-server-profile-default | awk '{print$2}')
# Get event-gateway service integration_url
INTEGRATION_URL=$(apic integrations:get event-gateway --subcollection gateway-service --server $APIC_MGMT_SERVER --format json --fields url | awk '{print$3}')
( echo "cat <<EOF" ; cat ${EEM_GEN_CUSTOMDIR}config/template-eem-apic-event-gateway.json ;) | \
    EEM_MANAGER_APIC_HOST=${EEM_MANAGER_APIC_HOST} \
    EEM_GATEWAY_RT_HOST=${EEM_GATEWAY_RT_HOST} \
    MY_APIC_INSTANCE_NAME_TLS_CLIENT_PROFILE_URL=${MY_APIC_INSTANCE_NAME_TLS_CLIENT_PROFILE_URL} \
    DEFAULT_TLS_SERVER_PROFILE_URL=${DEFAULT_TLS_SERVER_PROFILE_URL} \
    INTEGRATION_URL=${INTEGRATION_URL} \
    sh > ${EEM_GEN_CUSTOMDIR}script/eem-apic-event-gateway.json
apic gateway-services:create --server $APIC_MGMT_SERVER --availability-zone $APIC_AVAILABILITY_ZONE --org $APIC_ADMIN_ORG --format json ${EEM_GEN_CUSTOMDIR}script/eem-apic-event-gateway.json
#


#rm -f Integration.json
echo "Event Endpoint Manager has been registered with APIC."