#!/bin/bash

# function to print message if debug is set to 1
function decho() {
  if [ $ADEBUG -eq 1 ]; then
    mylog info "$@"
  fi
}

################################################
# function to create mail server configuration
# @param mail_server_ip: IP of the mail server, example: 
# @param mail_server_ip: Port of the mail server, example: 2525
CreateMailServer() {
  local mail_server_ip=$1
  local mail_server_port=$2

  mailServerUrl=$(curl -sk "https://$EP_API/api/orgs/admin/mail-servers/generatedemailserver?fields=url" \
  -H "Accept: application/json" \
  --compressed \
  -H "authorization: Bearer $access_token" \
  -H "content-type: application/json" \
  -H "Connection: keep-alive")

  if [ -z "$mailServerUrl" ] || [ "$mailServerUrl" = "null" ]; then
    mylog info "Creating mail server"
    mailServerUrl=$(curl -sk "https://$EP_API/api/orgs/admin/mail-servers" \
    -H "Accept: application/json" \
    --compressed \
    -H "authorization: Bearer $access_token" \
    -H "content-type: application/json" \
    -H "Connection: keep-alive" \
    --data "{\"title\":\"GeneratedEMailServer\",\"name\":\"generatedemailserver\",\"host\":\"$mail_server_ip\",\"port\":$mail_server_port,\"credentials\":{\"username\":\"$SMTP_USERNAME\",\"password\":\"$SMTP_PASSWORD\"}}" | jq .url );
    mylog info "mailServerUrl: $mailServerUrl"
  else
    mylog info "Mail Server generatedemailserver already exists, use it."
  fi

  # No check needed, it is a modification (PUT)
  setReplyTo=$(curl -sk "https://$EP_API/api/cloud/settings"\
  -X PUT\
  -H "Accept: application/json"\
  -H "authorization: Bearer $access_token" \
  -H "content-type: application/json"\
  --data "{\"mail_server_url\":$mailServerUrl,\"email_sender\":{\"name\":\"APIC Administrator\",\"address\":\"$ADMIN_EMAIL\"}}");
}

################################################
# function to create an organisation owned a specific user
# @param org_name: The name of the organisation. It allows upper cases, the id will be lowered, but the orignal value will be used elsewhere (title, summary)
# @param org_owner_id: The id of the owner of the organisation, it is used for his firstname and lastname
# @param org_owner_pwd: The password of the owner of the organisation
# @param org_owner_email: The email of the owner of the organisation

CreateOrg() {
  local org_name=$1
  local org_owner_id=$2
  local org_owner_pwd=$3
  local org_owner_email=$4

  # userRegistryUrl=$(curl -sk "https://$EP_API/api/orgs/admin/user-registries" \
  #   -H "Authorization: Bearer $access_token" \
  #   -H 'Accept: application/json' \
  #   --compressed)

  # Create owner user of the organisation in the LUR of the admin organisation (We use the default-idp-2 identity provider)
  userUrl=$(curl -sk "https://$EP_API/api/user-registries/admin/api-manager-lur/users/$org_owner_id?fields=url" \
  -H "Authorization: Bearer $access_token" \
  -H 'Accept: application/json' \
  --compressed | jq .url  | sed -e s/\"//g)

  if [ -z "$userUrl" ] || [ "$userUrl" = "null" ]; then
    mylog info "Creating $org_owner_id owner of the $org_name organisation"
    userUrl=$(curl -sk "https://$EP_API/api/orgs/admin/mail-servers" \
    -H "Accept: application/json" \
    --compressed \
    -H "Authorization: Bearer $access_token" \
    -H "Content-type: application/json" \
    -H "Connection: keep-alive" \
    --data "{\"type\":\"user\",\"api_version\":\"2.0.0\",\"name\":\"$org_owner_id\",\"title\":\"$org_owner_id\",\"state\":\"enabled\",\"identity_provider\": \"default-idp-2\",\"email\":\"$org_owner_email\",\"first_name\":\"$org_owner_id\",\"last_name\":\"consumer\",\"username\":\"$org_owner_id\",\"password\":\"$org_owner_pwd\"}" | jq .url  | sed -e s/\"//g)
  #  mylog info "userUrl: $userUrl"
  else
    mylog info "User org_owner_id already exists, use it."
  fi

  # Create organisation org_name
  lowercaseOrg=$(echo "$org_name" | awk '{print tolower($0)}')
  orgUrl=$(curl -sk "https://$EP_API/api/orgs/$lowercaseOrg?fields=url" \
  -H "Authorization: Bearer $access_token" \
  -H 'Accept: application/json' \
  --compressed | jq .url | sed -e s/\"//g)

  if [ -z "$orgUrl" ] || [ "$orgUrl" = "null" ]; then
    mylog info "Creating $org_name organisation"
    orgUrl=$(curl -sk --request POST "https://$EP_API/api/cloud/orgs" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $access_token" \
  --data "{\"name\":\"$lowercaseOrg\",\"title\":\"$org_name\",\"summary\":\"$org_name Organization\",\"org_type\":\"provider\",\"state\":\"enabled\",\"owner_url\":\"$userUrl\"}" | jq .url  | sed -e s/\"//g)
  #  mylog info "orgUrl: $orgUrl"
  else
    mylog info "$org_name already exists, use it."
  fi

}

################################################
# function to create the topology (not needed for cp4i installation)
CreateTopology() {
  echo Create gateway Service

  dpUrl=$(curl -sk "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/gateway-services" \
  -H "Authorization: Bearer $access_token" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Connection: keep-alive' \
  --data-binary "{\"name\":\"apigateway-service\",\"title\":\"API Gateway Service\",\"endpoint\":\"https://$EP_GWD\",\"api_endpoint_base\":\"https://$EP_GW\",\"tls_client_profile_url\":\"$tlsClientDefault\",\"gateway_service_type\":\"$ep_gwType\",\"visibility\":{\"type\":\"public\"},\"sni\":[{\"host\":\"*\",\"tls_server_profile_url\":\"$tlsServer\"}],\"integration_url\":\"$integration_url\"}" \
  --compressed | jq .url | sed -e s/\"//g);

  echo Set gateway Service as default for catalogs

  setGWdefault=$(curl -sk --request PUT "https://$EP_API/api/cloud/settings" \
    -H "Authorization: Bearer $access_token" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H 'Connection: keep-alive' \
    --data "{\"gateway_service_default_urls\": [\"$dpUrl\"]}");

  decho $setGWdefault

  echo Create Analytics Service

  analytUrl=$(curl -sk "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/analytics-services" \
  -H "Authorization: Bearer $access_token"\
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
  -H "Authorization: Bearer $access_token"\
  -H 'Cache-Control: no-cache' \
  -H 'Content-Type: application/json' \
  --data-binary "{\"analytics_service_url\":	\"$analytUrl\" }");

  decho "analytGwy: $analytGwy"


  echo "Create Portal Service"

  createPortal=$(curl -sk "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/portal-services"\
  -H "Accept: application/json"\
  -H "authorization: Bearer $access_token"\
  -H "content-type: application/json"\
  --data "{\"title\":\"API Portal Service\",\"name\":\"portal-service\",\"endpoint\":\"https://$EP_PADMIN\",\"web_endpoint_base\":\"https://$EP_PORTAL\",\"visibility\":{\"group_urls\":null,\"org_urls\":null,\"type\":\"public\"}}");

  decho "createPortal: $createPortal"
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

# Retrieve the various routes for APIC components
# API Manager URL
EP_API=$(oc get route "${my_cp_apic_instance_name}-mgmt-platform-api" -n ${my_apic_project} -o jsonpath="{.spec.host}")
# gwv6-gateway-manager
EP_GWD=$(oc get route "${my_cp_apic_instance_name}-gw-gateway-manager" -n ${my_apic_project} -o jsonpath="{.spec.host}")
# gwv6-gateway
EP_GW=$(oc get route "${my_cp_apic_instance_name}-gw-gateway" -n ${my_apic_project} -o jsonpath="{.spec.host}")
# analytics-ai-endpoint
EP_AI=$(oc get route "${my_cp_apic_instance_name}-a7s-ai-endpoint" -n ${my_apic_project} -o jsonpath="{.spec.host}")
# portal-portal-director
EP_PADMIN=$(oc get route "${my_cp_apic_instance_name}-ptl-portal-director" -n ${my_apic_project} -o jsonpath="{.spec.host}")
# portal-portal-web
EP_PORTAL=$(oc get route "${my_cp_apic_instance_name}-ptl-portal-web" -n ${my_apic_project} -o jsonpath="{.spec.host}")
# Zen
EP_ZEN=$(oc get route cpd -n ${my_apic_project} -o jsonpath="{.spec.host}")
# Cloud pak administration console
EP_CPADM=$(oc -n kube-public get cm ibmcloud-cluster-info -o jsonpath='{.data.cluster_address}')
decho "EP_CPADM: ${EP_CPADM}"

# Common service namespace
CS_PROJECT=$(oc get commonservice -A -o jsonpath='{..namespace}')
# Cloud pak admin uid
CP_ADMIN_UID=$(oc get secret -n "${CS_PROJECT}" platform-auth-idp-credentials -o=jsonpath='{.data.admin_username}' | base64 --decode)
# Cloud pak admin password
CP_ADMIN_PASSWORD=$(oc get secret -n "${CS_PROJECT}" platform-auth-idp-credentials -o=jsonpath='{.data.admin_password}' | base64 --decode)
decho "CP_ADMIN_PASSWORD: ${CP_ADMIN_PASSWORD}"

IAM_TOKEN=$(curl -kfs -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -d "grant_type=password&username=${CP_ADMIN_UID}&password=${CP_ADMIN_PASSWORD}&scope=openid" "https://${EP_CPADM}"/v1/auth/identitytoken | jq -r .access_token)
ZEN_TOKEN=$(curl -kfs https://"${EP_ZEN}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)

APIC_PROJECT=$(oc get apiconnectcluster -A -o jsonpath='{..namespace}')
APIC_INSTANCE=$(oc get apiconnectcluster -n "${NAMESPACE}" -o=jsonpath='{.items[0].metadata.name}')
decho "APIC_PROJECT/APIC_INSTANCE: ${APIC_PROJECT}/${APIC_INSTANCE}"

PLATFORM_API_URL=$(oc get apiconnectcluster -n "${APIC_PROJECT}" "${APIC_INSTANCE}" -o=jsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}')
decho "PLATFORM_API_URL: ${PLATFORM_API_URL}"

if test ! -e "toolkit-linux.tgz";then
	mylog info "Downloading toolkit" 1>&2
  oc cp -n "${APIC_PROJECT}" "$(oc get po -n "${APIC_PROJECT}" -l app.kubernetes.io/name=client-downloads-server,app.kubernetes.io/part-of="${APIC_INSTANCE}" -o=jsonpath='{.items[0].metadata.name}')":dist/toolkit-linux.tgz toolkit-linux.tgz
  tar -xf toolkit-linux.tgz  && mv apic-slim apic
fi

TOOLKIT_CREDS_URL="${PLATFORM_API_URL}/cloud/settings/toolkit-credentials"

# always download the credential.json
# if test ! -e "~/.apiconnect/config-apim";then
	mylog info "Downloading apic config json file" 1>&2
	curl -ks "${TOOLKIT_CREDS_URL}" -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -o creds.json
	yes | apic client-creds:set creds.json
	[[ -e creds.json ]] && rm creds.json
# fi

APIC_APIKEY=$(curl -ks --fail -X POST "${PLATFORM_API_URL}"/cloud/api-keys -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -d '{"client_type":"toolkit","description":"Tookit API key"}' | jq -r .api_key)
decho "APIC_APIKEY: ${APIC_APIKEY}"

APIM_ENDPOINT=$(oc -n "${APIC_PROJECT}" get mgmt "${APIC_INSTANCE}-mgmt" -o jsonpath='{.status.zenRoute}')
decho "APIM_ENDPOINT: ${APIM_ENDPOINT}"

# ./apic login --context admin --server https://"${APIM_ENDPOINT}" --sso --apiKey "${APIC_APIKEY}"

# The goal is to get the apikey defined in the realm provider/common-services, get the credentials for the toolkit, then use the token endpoint to get an oauth token for Cloud Manager from API Key
TOOLKIT_CLIENT_ID=$(grep "^toolkit_client_id:" ~/.apiconnect/config-apim | cut -d ':' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
TOOLKIT_CLIENT_SECRET=$(grep "^toolkit_client_secret:" ~/.apiconnect/config-apim | cut -d ':' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

cmToken=$(curl -k --fail -X POST "$PLATFORM_API_URL/token" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 -H "X-Ibm-Client-Id: $TOOLKIT_CLIENT_ID" \
 -H "X-Ibm-Client-Secret: $TOOLKIT_CLIENT_SECRET" \
 --data-binary  "{\"api_key\":\"$APIC_APIKEY\",\"client_id\":\"$TOOLKIT_CLIENT_ID\",\"client_secret\":\"$TOOLKIT_CLIENT_SECRET\",\"grant_type\":\"api_key\"}")

if [ $(echo $cmToken | jq .status ) = "401" ] ; then
  decho "Error with login -> $cmToken"
  echo "Probably don't need to change password"

  elif [ $(echo $cmToken | jq .access_token) != "null" ]
    then
      # echo "Try to Change password"
      access_token=$(echo $cmToken | jq .access_token | sed -e s/\"//g);
      apicme=$(curl -k "https://$EP_API/api/me" \
        -X PUT \
        -H "Authorization: Bearer $access_token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        --data-binary "{\"email\":\"$ADMIN_EMAIL\"}" | jq 'del(.url)')
      decho $apicme 

#      curl -kv "https://$EP_API/api/me/change-password" \
#        -H "Authorization: Bearer $access_token" \
#        -H 'Content-Type: application/json' \
#        -H 'Accept: application/json' \
#        --data-binary "{\"current_password\":\"7iron-hide\",\"password\":\"$ADMIN_PASSWORD\"}" 
fi

CreateMailServer "${SMTP_SERVER}" "${SMTP_SERVERPORT}"
CreateOrg "Org1" "org1owner" "Passw0rd!" "org1owner@fr.ibm.com"

exit 1

tlsServer=$(curl -sk "https://$EP_API/api/orgs/admin/tls-server-profiles" \
 -H "Authorization: Bearer $access_token" \
 -H 'Accept: application/json' --compressed | jq .results[0].url  | sed -e s/\"//g);

tlsClientDefault=$(curl -sk "https://$EP_API/api/orgs/admin/tls-client-profiles" \
 -H "Authorization: Bearer $access_token" \
 -H 'Accept: application/json' --compressed | jq '.results[] | select(.name=="tls-client-profile-default")| .url' | sed -e s/\"//g);

tlsClientAnalytics=$(curl -sk "https://$EP_API/api/orgs/admin/tls-client-profiles" \
 -H "Authorization: Bearer $access_token" \
 -H 'Accept: application/json' --compressed | jq '.results[] | select(.name=="analytics-client-default")| .url' | sed -e s/\"//g);

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

