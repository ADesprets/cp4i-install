#!/bin/bash

# function to print message if debug is set to 1
function decho() {
  if [ $ADEBUG -eq 1 ]; then
    mylog info "$@"
  fi
}

################################################
# Create mail server configuration
# @param mail_server_ip: IP of the mail server, example: 
# @param mail_server_ip: Port of the mail server, example: 2525
# function
CreateMailServer () {

local mail_server_ip=$1
local mail_server_port=$2

mylog info "Creating Mail Server $mail_server_ip:$mail_server_port"

decho "Check if Mail Server already exists"

mailServerUrl=$(curl -sk "https://$EP_API/api/orgs/admin/mail-servers"\
 -H "Accept: application/json"\
 --compressed\
 -H "authorization: Bearer $cmToken"\
 -H "content-type: application/json"\
 -H "Connection: keep-alive"\
 --data "{\"title\":\"GeneratedEMailServer\",\"name\":\"generatedemailserver\",\"host\":\"$SMTP_SERVER\",\"port\":$SMTP_SERVERPORT,\"credentials\":{\"username\":\"$SMTP_USERNAME\",\"password\":\"$SMTP_PASSWORD\"}}" | jq .url );

mylog info "mailServerUrl: $mailServerUrl"

exit 1

echo ---------
echo "set MailServer"
echo ---------

setReplyTo=$(curl -sk "https://$EP_API/api/cloud/settings"\
 -X PUT\
 -H "Accept: application/json"\
 -H "authorization: Bearer $cmToken" \
 -H "content-type: application/json"\
 --data "{\"mail_server_url\":$mailServerUrl,\"email_sender\":{\"name\":\"APIC Administrator\",\"address\":\"$ADMIN_EMAIL\"}}");

}

################################################################################################
# Start of the script main entry
# main

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
configdir="${scriptdir}config/"
libdir="${scriptdir}../../../"

# load helper functions
. "${libdir}"lib.sh

read_config_file "${configdir}apic.properties"

# Calculate the various routes for APIC components
# API Manager URL
EP_API=$(oc get route "${my_cp_apic_instance_name}-mgmt-platform-api" -n ${my_apic_project} -o jsonpath="{.spec.host}")
echo "EP_API: ${EP_API}"
# gwv6-gateway-manager
EP_GWD=$(oc get route "${my_cp_apic_instance_name}-gw-gateway-manager" -n ${my_apic_project} -o jsonpath="{.spec.host}")
echo "EP_GWD: ${EP_GWD}"
# gwv6-gateway
EP_GW=$(oc get route "${my_cp_apic_instance_name}-gw-gateway" -n ${my_apic_project} -o jsonpath="{.spec.host}")
echo "EP_GW: ${EP_GW}"
# analytics-ai-endpoint
EP_AI=$(oc get route "${my_cp_apic_instance_name}-a7s-ai-endpoint" -n ${my_apic_project} -o jsonpath="{.spec.host}")
echo "EP_AI: ${EP_AI}"
# portal-portal-director
EP_PADMIN=$(oc get route "${my_cp_apic_instance_name}-ptl-portal-director" -n ${my_apic_project} -o jsonpath="{.spec.host}")
echo "EP_PADMIN: ${EP_PADMIN}"
# portal-portal-web
EP_PORTAL=$(oc get route "${my_cp_apic_instance_name}-ptl-portal-web" -n ${my_apic_project} -o jsonpath="{.spec.host}")
echo "EP_PORTAL: ${EP_PORTAL}"
# Zen
EP_ZEN=$(oc get route cpd -n ${my_apic_project} -o jsonpath="{.spec.host}")
echo "EP_ZEN: ${EP_ZEN}"
# Cloud pak administration console
EP_CPADM=$(oc -n kube-public get cm ibmcloud-cluster-info -o jsonpath='{.data.cluster_address}')
echo "EP_CPADM: ${EP_CPADM}"

# Common service namespace
CS_PROJECT=$(oc get commonservice -A -o jsonpath='{..namespace}')
echo "CS_PROJECT: ${CS_PROJECT}"
# Cloud pak admin uid
CP_ADMIN_UID=$(oc get secret -n "${CS_PROJECT}" platform-auth-idp-credentials -o=jsonpath='{.data.admin_username}' | base64 --decode)
echo "CP_ADMIN_UID: ${CP_ADMIN_UID}"
# Cloud pak admin password
CP_ADMIN_PASSWORD=$(oc get secret -n "${CS_PROJECT}" platform-auth-idp-credentials -o=jsonpath='{.data.admin_password}' | base64 --decode)
echo "CP_ADMIN_PASSWORD: ${CP_ADMIN_PASSWORD}"

IAM_TOKEN=$(curl -kfs -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -d "grant_type=password&username=${CP_ADMIN_UID}&password=${CP_ADMIN_PASSWORD}&scope=openid" "https://${EP_CPADM}"/v1/auth/identitytoken | jq -r .access_token)
echo "IAM_TOKEN: ${IAM_TOKEN}"
ZEN_TOKEN=$(curl -kfs https://"${EP_ZEN}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)
echo "ZEN_TOKEN: ${ZEN_TOKEN}"

APIC_PROJECT=$(oc get apiconnectcluster -A -o jsonpath='{..namespace}')
echo "APIC_PROJECT: ${APIC_PROJECT}"

APIC_INSTANCE=$(oc get apiconnectcluster -n "${NAMESPACE}" -o=jsonpath='{.items[0].metadata.name}')
echo "APIC_INSTANCE: ${APIC_INSTANCE}"

PLATFORM_API_URL=$(oc get apiconnectcluster -n "${APIC_PROJECT}" "${APIC_INSTANCE}" -o=jsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}')
echo "PLATFORM_API_URL: ${PLATFORM_API_URL}"
oc cp -n "${APIC_PROJECT}" "$(oc get po -n "${APIC_PROJECT}" -l app.kubernetes.io/name=client-downloads-server,app.kubernetes.io/part-of="${APIC_INSTANCE}" -o=jsonpath='{.items[0].metadata.name}')":dist/toolkit-linux.tgz toolkit-linux.tgz
tar -xf toolkit-linux.tgz  && mv apic-slim apic

TOOLKIT_CREDS_URL="${PLATFORM_API_URL}/cloud/settings/toolkit-credentials"
echo "TOOLKIT_CREDS_URL: ${TOOLKIT_CREDS_URL}"

echo "Downloading apic config json file"
curl -ks "${TOOLKIT_CREDS_URL}" -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -o creds.json
yes | apic client-creds:set creds.json
[[ -e creds.json ]] && rm creds.json

APIC_APIKEY=$(curl -ks --fail -X POST "${PLATFORM_API_URL}"/cloud/api-keys -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -d '{"client_type":"toolkit","description":"Tookit API key"}' | jq -r .api_key)
echo "APIC_APIKEY: ${APIC_APIKEY}"
APIM_ENDPOINT=$(oc -n "${APIC_PROJECT}" get mgmt "${APIC_INSTANCE}-mgmt" -o jsonpath='{.status.zenRoute}')
echo "APIM_ENDPOINT: ${APIM_ENDPOINT}"

./apic login --context admin --server https://"${APIM_ENDPOINT}" --sso --apiKey "${APIC_APIKEY}"


exit 1







# admin ORG
ADMIN_ORG_NAME='admin'
API_MANAGER_LUR='api-manager-lur'

echo "Test if change password is necessary" 

# Need to better manage client_id/client_secret

cmToken=$(curl -k "https://$EP_API/api/token" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 --data-binary '{"username":"admin","password":"$APIC_CMC_ADMIN_PASSWORD","realm":"admin/default-idp-1","client_id":"caa87d9a-8cd7-4686-8b6e-ee2cdc5ee267","client_secret":"3ecff363-7eb3-44be-9e07-6d4386c48b0b","grant_type":"password"}')

decho "cmToken: $cmToken"

if [ $(echo $cmToken | jq .status ) = "401" ] ; then
  decho "Error with login -> $cmToken"
  echo "Probably don't need to change password"

  elif [ $(echo $cmToken | jq .access_token) != "null" ]
    then
      echo "Try to Change password"
      access_token=$(echo $cmToken | jq .access_token | sed -e s/\"//g);

      decho ">>> login response: $cmToken"
      decho ">>> access token: $access_token"

      curl -kv "https://$EP_API/api/me" \
        -X PUT \
        -H "Authorization: Bearer $access_token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        --data-binary "{\"email\":\"$ADMIN_EMAIL\"}" 

      curl -kv "https://$EP_API/api/me/change-password" \
        -H "Authorization: Bearer $access_token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        --data-binary "{\"current_password\":\"7iron-hide\",\"password\":\"$ADMIN_PASSWORD\"}" 
fi

echo "EP_API: $EP_API"

cmToken=$(curl -sk  "https://$EP_API/api/token" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 --data-binary "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\",\"realm\":\"admin/default-idp-1\",\"client_id\":\"3c60c74b-6a9f-4916-8ff2-95467e939db4\",\"client_secret\":\"d490558d-1d86-4e09-86cd-d88d48961161\",\"grant_type\":\"password\"}" |  jq .access_token | sed -e s/\"//g  )

retVal=$?
if [ $retVal -ne 0 ] || [ -z "$cmToken" ] || [ "$cmToken" = "null" ]; then
    	echo "Error with login -> $retVal"
	exit 1
fi

decho "Cloud Manager access token: $cmToken"

CreateMailServer "${SMTP_SERVER}" "${SMTP_SERVERPORT}"

exit 1

echo Get integration Endpoint

integration_url=$(curl -sk  "https://$EP_API/api/cloud/integrations/gateway-service/datapower-api-gateway" -H "Authorization: Bearer $cmToken" -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: en-GB,en-US;q=0.9,en;q=0.8'  -H 'Accept: application/json'  -H 'Connection: keep-alive' --compressed | jq .url | sed -e s/\"//g)

retVal=$?

echo "integration_url: $integration_url"


if [ $retVal -ne 0 ] || [ -z "$integration_url" ] || [ "$integration_url" = "null" ]; then
    	echo "Error with integration_url -> $retVal"
	exit 1
fi

# orgUrl=$(curl -sk "https://$EP_API/api/cloud/orgs" \
#  -H "Authorization: Bearer $cmToken" \
#  -H 'Accept: application/json' \
#  --compressed | jq .results[0].url | sed -e s/\"//g);

# orgList=$(curl -sk "https://$EP_API/api/cloud/orgs" \
#  -H "Authorization: Bearer $cmToken" \
#  -H 'Accept: application/json' \
#  --compressed)

decho "orgList: $orgList"

# userregistriesList=$(curl -sk "$orgUrl/user-registries" \
#  -H "Authorization: Bearer $cmToken" \
#  -H 'Accept: application/json' \
#  --compressed)

# userrList=$(curl -sk "https://$EP_API/api/user-registries/$ADMIN_ORG_NAME/$API_MANAGER_LUR/users" \
#  -H "Authorization: Bearer $cmToken" \
#  -H 'Accept: application/json' \
#  --compressed)

decho "userList: $userrList"


tlsServer=$(curl -sk "https://$EP_API/api/orgs/admin/tls-server-profiles" \
 -H "Authorization: Bearer $cmToken" \
 -H 'Accept: application/json' --compressed | jq .results[0].url  | sed -e s/\"//g);

tlsClientDefault=$(curl -sk "https://$EP_API/api/orgs/admin/tls-client-profiles" \
 -H "Authorization: Bearer $cmToken" \
 -H 'Accept: application/json' --compressed | jq '.results[] | select(.name=="tls-client-profile-default")| .url' | sed -e s/\"//g);

tlsClientAnalytics=$(curl -sk "https://$EP_API/api/orgs/admin/tls-client-profiles" \
 -H "Authorization: Bearer $cmToken" \
 -H 'Accept: application/json' --compressed | jq '.results[] | select(.name=="analytics-client-default")| .url' | sed -e s/\"//g);

echo Create gateway Service

dpUrl=$(curl -sk "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/gateway-services" \
 -H "Authorization: Bearer $cmToken" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 -H 'Connection: keep-alive' \
 --data-binary "{\"name\":\"apigateway-service\",\"title\":\"API Gateway Service\",\"endpoint\":\"https://$EP_GWD\",\"api_endpoint_base\":\"https://$EP_GW\",\"tls_client_profile_url\":\"$tlsClientDefault\",\"gateway_service_type\":\"$ep_gwType\",\"visibility\":{\"type\":\"public\"},\"sni\":[{\"host\":\"*\",\"tls_server_profile_url\":\"$tlsServer\"}],\"integration_url\":\"$integration_url\"}" \
 --compressed | jq .url | sed -e s/\"//g);

echo Set gateway Service as default for catalogs

setGWdefault=$(curl -sk --request PUT "https://$EP_API/api/cloud/settings" \
  -H "Authorization: Bearer $cmToken" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Connection: keep-alive' \
  --data "{\"gateway_service_default_urls\": [\"$dpUrl\"]}");

decho $setGWdefault

echo Create Analytics Service

analytUrl=$(curl -sk "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/analytics-services" \
 -H "Authorization: Bearer $cmToken"\
 -H 'Content-Type: application/json'\
 -H 'Accept: application/json'\
 -H 'Connection: keep-alive'\
 --data-binary "{\"title\":\"API Analytics Service\",\"name\":\"analytics-service\",\"endpoint\":\"https://$EP_AI\"}" \
 --compressed | jq .url | sed -e s/\"//g);

decho "analytUrl: $analytUrl"

echo Associate Analytics Service with Gateway

analytGwy=$(curl -sk -X PATCH \
  "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/gateway-services/apigateway-service" \
 -H 'Accept: application/json' \
 -H "Authorization: Bearer $cmToken"\
 -H 'Cache-Control: no-cache' \
 -H 'Content-Type: application/json' \
 --data-binary "{\"analytics_service_url\":	\"$analytUrl\" }");

decho "analytGwy: $analytGwy"


echo "Create Portal Service"

createPortal=$(curl -sk "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/portal-services"\
 -H "Accept: application/json"\
 -H "authorization: Bearer $cmToken"\
 -H "content-type: application/json"\
 --data "{\"title\":\"API Portal Service\",\"name\":\"portal-service\",\"endpoint\":\"https://$EP_PADMIN\",\"web_endpoint_base\":\"https://$EP_PORTAL\",\"visibility\":{\"group_urls\":null,\"org_urls\":null,\"type\":\"public\"}}");

decho "createPortal: $createPortal"

echo Create user : ${ORG_USERNAME} 

userOrg=$(curl -sk --request POST "https://$EP_API/api/user-registries/admin/api-manager-lur/users" \
 -H 'Accept: application/json' \
 -H 'Content-Type: application/json' \
 -H "authorization: Bearer $cmToken" \
--data "{\"type\":\"user\",\"api_version\":\"2.0.0\",\"name\":\"$ORG_USERNAME\",\"title\":\"$ORG_USERNAME\",\"state\":\"enabled\",\"identity_provider\": \"default-idp-2\",\"email\":\"$ORG_USEREMAIL\",\"first_name\":\"$ORG_USERNAME\",\"last_name\":\"consumer\",\"username\":\"$ORG_USERNAME\",\"password\":\"$ORG_PASSWORD\"}");

decho "Result of user creation : $userOrg"

echo Retrieve user : ${ORG_USERNAME} 

userUrl=$(curl -sk "https://$EP_API/api/user-registries/$ADMIN_ORG_NAME/$API_MANAGER_LUR/users/$ORG_USERNAME" \
 -H "Authorization: Bearer $cmToken" \
 -H 'Accept: application/json' --compressed | jq .url  | sed -e s/\"//g);

decho "userUrl: $userUrl"

echo Create Org : ${PROVIDER_ORG} 

lowercaseOrg=$(echo "$PROVIDER_ORG" | awk '{print tolower($0)}')

createOrg=$(curl -sk --request POST "https://$EP_API/api/cloud/orgs" \
 -H 'Accept: application/json' \
 -H 'Content-Type: application/json' \
 -H "authorization: Bearer $cmToken" \
--data "{\"name\":\"$lowercaseOrg\",\"title\":\"$PROVIDER_ORG\",\"summary\":\"$PROVIDER_ORG Organization\",\"org_type\":\"provider\",\"state\":\"enabled\",\"owner_url\":\"$userUrl\"}");

decho "createOrg: $createOrg"

echo "--------------- Endpoint ---------------------"
echo " Cloud manager : https://$MGMT_ADMIN_EP.$STACK_HOST (admin/$ADMIN_PASSWORD)"
echo " API manager : https://$MGMT_API_EP.$STACK_HOST ($ORG_USERNAME/$ORG_PASSWORD)"
echo "----------------------------------------------"

duration=$SECONDS
ending=$(date);
echo "------------------------------------"
echo "start: $starting - end: $ending"
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
echo "------------------------------------"

