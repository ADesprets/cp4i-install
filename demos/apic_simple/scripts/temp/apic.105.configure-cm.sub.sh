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
function CreateMailServer() {
  local mail_server_ip=$1
  local mail_server_port=$2

  mailServerUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/mail-servers/generatedemailserver?fields=url" \
  -H "Accept: application/json" \
  --compressed \
  -H "authorization: Bearer $access_token" \
  -H "content-type: application/json" \
  -H "Connection: keep-alive")

  if [ $(echo $mailServerUrl | jq .status ) = "404" ] || [ -z "$mailServerUrl" ] || [ "$mailServerUrl" = "null" ]; then
    mylog wait "Creating mail server"
    mailServerUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/mail-servers" \
    -H "Accept: application/json" \
    --compressed \
    -H "authorization: Bearer $access_token" \
    -H "content-type: application/json" \
    -H "Connection: keep-alive" \
    --data "{\"title\":\"GeneratedEMailServer\",\"name\":\"generatedemailserver\",\"host\":\"$mail_server_ip\",\"port\":$mail_server_port,\"credentials\":{\"username\":\"$APIC_SMTP_USERNAME\",\"password\":\"$APIC_SMTP_PASSWORD\"}}" | jq .url );
    # mylog info "mailServerUrl: $mailServerUrl"
  else
    mylog info "Mail Server generatedemailserver already exists, use it."
  fi

  # No check needed, it is a modification (PUT)
  setReplyTo=$(curl -sk "${PLATFORM_API_URL}api/cloud/settings"\
  -X PUT\
  -H "Accept: application/json"\
  -H "authorization: Bearer $access_token" \
  -H "content-type: application/json"\
  --data "{\"mail_server_url\":$mailServerUrl,\"email_sender\":{\"name\":\"APIC Administrator\",\"address\":\"$APIC_ADMIN_EMAIL\"}}");
}

################################################
# Create an organisation owned by a specific user
# @param org_name: The name of the organisation. It allows upper cases, the id will be lowered, but the orignal value will be used elsewhere (title, summary)
# @param org_owner_id: The id of the owner of the organisation, it is used for his firstname and lastname
# @param org_owner_pwd: The password of the owner of the organisation
# @param org_owner_email: The email of the owner of the organisation
function CreateOrg() {
  local org_name=$1
  local org_owner_id=$2
  local org_owner_pwd=$3
  local org_owner_email=$4

  # userRegistryUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/user-registries" \
  #   -H "Authorization: Bearer $access_token" \
  #   -H 'Accept: application/json' \
  #   --compressed)

  userUrl=$(curl -sk "${PLATFORM_API_URL}api/user-registries/admin/api-manager-lur/users/$org_owner_id?fields=url" \
    -H "Accept: application/json" \
    --compressed \
    -H "Authorization: Bearer $access_token" \
    -H "Content-type: application/json")
  # mylog info "userUrl: $userUrl"
  if [ $(echo $userUrl | jq .status ) = "404" ] || [ -z "$userUrl" ] || [ "$userUrl" = "null" ]; then
  # Create owner of the organisation in the LUR of the admin organisation (We use the default-idp-2 identity provider valid for CP4I)
  # if ! curl -sk "${PLATFORM_API_URL}api/user-registries/admin/api-manager-lur/users/$org_owner_id?fields=url" -H "Authorization: Bearer $access_token" -H 'Accept: application/json' > /dev/null 2>&1; then
    mylog info "Creating $org_owner_id owner of the $org_name organisation"
    userUrl=$(curl -sk "${PLATFORM_API_URL}api/user-registries/admin/api-manager-lur/users" \
    -H "Accept: application/json" \
    --compressed \
    -H "Authorization: Bearer $access_token" \
    -H "Content-type: application/json" \
    -H "Connection: keep-alive" \
    --data "{\"type\":\"user\",\"api_version\":\"2.0.0\",\"name\":\"$org_owner_id\",\"title\":\"$org_owner_id\",\"state\":\"enabled\",\"identity_provider\": \"default-idp-2\",\"email\":\"$org_owner_email\",\"first_name\":\"$org_owner_id\",\"last_name\":\"$org_owner_id\",\"username\":\"$org_owner_id\",\"password\":\"$org_owner_pwd\"}" | jq .url  | sed -e s/\"//g)
  else
    mylog info "userUrl: $userUrl"
    mylog info "User $org_owner_id already exists, use it."
  fi
  
  lowercaseOrg=$(echo "$org_name" | awk '{print tolower($0)}')
  orgUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/$lowercaseOrg?fields=url" \
    -H "Accept: application/json" \
    --compressed \
    -H "Authorization: Bearer $access_token" \
    -H "Content-type: application/json")
  if [ $(echo $orgUrl | jq .status ) = "404" ] || [ -z "$orgUrl" ] || [ "$orgUrl" = "null" ]; then
  #  if ! curl -sk "${PLATFORM_API_URL}api/orgs/$lowercaseOrg?fields=url" -H "Authorization: Bearer $access_token" -H 'Accept: application/json' > /dev/null 2>&1; then
    mylog wait "Creating $org_name organisation"
    lowercaseOrg=$(echo "$org_name" | awk '{print tolower($0)}')
  
    orgUrl=$(curl -sk --request POST "${PLATFORM_API_URL}api/cloud/orgs" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $access_token" \
      --compressed \
      --data "{\"name\":\"$lowercaseOrg\",\"title\":\"$org_name\",\"summary\":\"$org_name organization\",\"org_type\":\"provider\",\"state\":\"enabled\",\"owner_url\":\"$userUrl\"}" | jq .url  | sed -e s/\"//g)

  #  mylog info "orgUrl: $orgUrl"
  else
    mylog info "$org_name already exists, use it."
  fi

}

################################################
# Create the topology (check if needed for cp4i installation)
function CreateTopology() {
  #should increase idempotence
  mylog info "Create gateway Service"

  # mylog info  "{\"name\":\"apigateway-service\",\"title\":\"API Gateway Service\",\"endpoint\":\"https://$EP_GWD\",\"api_endpoint_base\":\"https://$EP_GW\",\"tls_client_profile_url\":\"$tlsClientDefault\",\"gateway_service_type\":\"$ep_gwType\",\"visibility\":{\"type\":\"public\"},\"sni\":[{\"host\":\"*\",\"tls_server_profile_url\":\"$tlsServer\"}],\"integration_url\":\"$integration_url\"}"

  dpUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/availability-zones/availability-zone-default/gateway-services" \
  -H "Authorization: Bearer $access_token" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Connection: keep-alive' \
  --data-binary "{\"name\":\"apigateway-service\",\"title\":\"API Gateway Service\",\"endpoint\":\"https://$EP_GWD\",\"api_endpoint_base\":\"https://$EP_GW\",\"tls_client_profile_url\":\"$tlsClientDefault\",\"gateway_service_type\":\"$ep_gwType\",\"visibility\":{\"type\":\"public\"},\"sni\":[{\"host\":\"*\",\"tls_server_profile_url\":\"$tlsServer\"}],\"integration_url\":\"$integration_url\"}" \
  --compressed | jq .url | sed -e s/\"//g);

  mylog info "Gateway service already exists, use it."

  mylog info  Set gateway Service as default for catalogs

  setGWdefault=$(curl -sk --request PUT "${PLATFORM_API_URL}api/cloud/settings" \
    -H "Authorization: Bearer $access_token" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H 'Connection: keep-alive' \
    --data "{\"gateway_service_default_urls\": [\"$dpUrl\"]}");

  # mylog info $setGWdefault

  mylog info  Create Analytics Service

  analytUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/availability-zones/availability-zone-default/analytics-services" \
  -H "Authorization: Bearer $access_token"\
  -H 'Content-Type: application/json'\
  -H 'Accept: application/json'\
  -H 'Connection: keep-alive'\
  --data-binary "{\"title\":\"API Analytics Service\",\"name\":\"analytics-service\",\"endpoint\":\"https://$EP_AI\"}" \
  --compressed | jq .url | sed -e s/\"//g);

  # mylog info "analytUrl: $analytUrl"

  mylog info "Associate Analytics Service with Gateway"

  analytGwy=$(curl -sk -X PATCH \
    "${PLATFORM_API_URL}api/orgs/admin/availability-zones/availability-zone-default/gateway-services/apigateway-service" \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $access_token"\
  -H 'Cache-Control: no-cache' \
  -H 'Content-Type: application/json' \
  --data-binary "{\"analytics_service_url\":	\"$analytUrl\" }");

  # mylog info "analytGwy: $analytGwy"

  mylog info "Create Portal Service"

  createPortal=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/availability-zones/availability-zone-default/portal-services"\
  -H "Accept: application/json"\
  -H "authorization: Bearer $access_token"\
  -H "content-type: application/json"\
  --data "{\"title\":\"API Portal Service\",\"name\":\"portal-service\",\"endpoint\":\"https://$EP_PADMIN\",\"web_endpoint_base\":\"https://$EP_PORTAL\",\"visibility\":{\"group_urls\":null,\"org_urls\":null,\"type\":\"public\"}}");

  # mylog info "createPortal: $createPortal"
}

################################################
# Create a catalog in an organisation
# catalogs specifications of the 3 catalogs are hard coded
# @param org_name: The name of the organisation.
function CreateCatalog() {
  local org_name=$(echo "$1" | awk '{print tolower($0)}')

# decho $lf_tracelevel "url: ${PLATFORM_API_URL}api/orgs/$org_name/catalogs and token: $amToken"

# Hard coded values
catalog_title=("Prod" "UAT" "QA")
catalog_name=("prod" "uat" "qa")
catalog_summary=("Production" "UAT" "Quality and Acceptance")

  portalServiceURL=$(curl -sk -X GET "${PLATFORM_API_URL}api/orgs/$org_name/portal-services?fields=url" \
    -H "Authorization: Bearer $amToken" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    -H 'Connection: keep-alive' \
    --compressed | jq .results[0].url | sed -e s/\"//g);

for index in ${!catalog_name[@]}
    do
      catURL=$(curl -sk -X GET "${PLATFORM_API_URL}api/catalogs/$org_name/${catalog_name[$index]}?fields=url" \
        -H "Authorization: Bearer $amToken" \
        -H 'accept: application/json' \
        -H 'content-type: application/json' \
        -H 'Connection: keep-alive' | jq .url | sed -e s/\"//g)
      # decho $lf_tracelevel "Catalog url: $catURL"

      if [ -z "$catURL" ] || [ "$catURL" = "null" ]; then
        mylog wait "Creating Catalog: "${catalog_name[$index]}" ("${catalog_summary[$index]}") in org $org_name";
        catURL=$(curl -sk -X POST "${PLATFORM_API_URL}api/orgs/$org_name/catalogs" \
        -H "Authorization: Bearer $amToken" \
        -H 'accept: application/json' \
        -H 'content-type: application/json' \
        -H 'Connection: keep-alive' \
        --data-binary "{\"name\":\"${catalog_name[$index]}\",\"title\":\"${catalog_title[$index]}\",\"summary\":\"${catalog_summary[$index]}\"}" \
        --compressed | jq .url | sed -e s/\"//g);
        waitn 1
      else
        mylog info "Catalog ${catalog_name[$index]} already exists, use it."
      fi

      # TODO Check if we can skeep this action if already done
      mylog info "Create the portal site in Drupal for: "${catalog_summary[$index]}"";
      res=$(curl -sk -X PUT "$catURL/settings" \
       -H "Authorization: Bearer $amToken" \
       -H 'accept: application/json' \
       -H 'content-type: application/json' \
       -H 'Connection: keep-alive' \
       --data-binary "{\"portal\": {\"endpoint\": \"https://$EP_PORTAL/$org_name/${catalog_name[$index]}\",\"portal_service_url\": \"$portalServiceURL\", \"type\": \"drupal\"},\"application_lifecycle\": {} }" | jq .portal.endpoint);
      mylog info "Portal endpoint for: "${catalog_summary[$index]}": $res"
    done
}

################################################
# Load an API
# @param org_name: The name of the organisation.
function LoadAPI () {
  local platform_api_url=$1
  local apic_provider_org=$2
  local api_name=$3
  local token=$4

  echo "${platform_api_url}api/orgs/$apic_provider_org/drafts/draft-apis/$api_name?fields=url -H \"Authorization: Bearer $token\" -H 'Accept: application/json'"
  pingAPI=$(curl -sk "${platform_api_url}api/orgs/$apic_provider_org/drafts/draft-apis/$api_name?fields=url" -H "Authorization: Bearer $token" -H 'Accept: application/json' > /dev/null 2>&1)
  echo "pingAPI: $pingAPI"
  if [ -z "$pingAPI" ] || [ "$pingAPI" = "null" ]; then
  # if ! curl -sk "${platform_api_url}api/orgs/$apic_provider_org/drafts/draft-apis/$api_name?fields=url" -H "Authorization: Bearer $amToken" -H 'Accept: application/json' > /dev/null 2>&1; then
    # draftAPICLEAR=$(curl -sk --request DELETE "${platform_api_url}api/orgs/$apic_provider_org/drafts/draft-apis/pingapi?confirm=$APIC_PROVIDER_ORG" -H "Accept: application/json" -H "authorization: Bearer $amToken");
    mylog info "Load test API (Ping API) as a draft"
    api=`cat ${configdir}apis/ping-api_1.0.0.json`;
    draftAPI=$(curl -sk "${platform_api_url}api/orgs/${apic_provider_org}/drafts/draft-apis?api_type=rest"\
      -H 'accept: application/json' \
      -H "authorization: Bearer $token" \
      -H 'content-type: application/json' \
      -H "Connection: keep-alive" \
      -- compressed \
      --data "{\"draft_api\":$api}" );
    mylog info $draftAPI;
  else
    mylog info "$api_name already exists, do not load it."
  fi
}

function Get_APIC_Infos() {
  # Retrieve the various routes for APIC components
  # API Manager URL
  EP_API=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-mgmt-platform-api" -o jsonpath="{.spec.host}")
  mylog info "API Manager URL. EP_API: ${EP_API}"
  
  # gwv6-gateway-manager
  EP_GWD=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-gw-gateway-manager" -o jsonpath="{.spec.host}")
  mylog info "EP_GWD: ${EP_GWD}"
  
  # gwv6-gateway
  EP_GW=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-gw-gateway" -o jsonpath="{.spec.host}")
  mylog info "Gateway v6. EP_GW: ${EP_GW}"
  
  # analytics-ai-endpoint
  EP_AI=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-a7s-ai-endpoint" -o jsonpath="{.spec.host}")
  mylog info "Analytics AI Endpoint. EP_AI: ${EP_AI}"
  
  # portal-portal-director
  EP_PADMIN=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-ptl-portal-director" -o jsonpath="{.spec.host}")
  mylog info "Portal Director. EP_PADMIN: ${EP_PADMIN}"
  
  # portal-portal-web
  EP_PORTAL=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-ptl-portal-web" -o jsonpath="{.spec.host}")
  mylog info "Portal Web. EP_PORTAL: $EP_PORTAL"
  
  # Zen
  if EP_ZEN=$($MY_CLUSTER_COMMAND -n ${apic_project} get route cpd -o jsonpath="{.spec.host}" 2> /dev/null ); then
    mylog info "Zen. EP_ZEN: $EP_ZEN"
  fi
  
  # Cloud pak administration console
  EP_CPADM=$($MY_CLUSTER_COMMAND -n kube-public get cm ibmcloud-cluster-info -o jsonpath='{.data.cluster_address}')
  mylog info "Cloudpak admin console. EP_CPADM: ${EP_CPADM}"
  
  # APIC Gateway admin password
  if APIC_GTW_PASSWORD_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret ${APIC_INSTANCE_NAME}-gw-admin -o=jsonpath='{.data.password}' 2> /dev/null ); then
    APIC_GTW_PASSWORD=$(echo $APIC_GTW_PASSWORD_B64 | base64 --decode)
    mylog info "APIC Gateway admin password. APIC_GTW_PASSWORD: $APIC_GTW_PASSWORD"
  fi

  # APIC Cloud Manager admin email
  if APIC_CM_ADMIN_EMAIL_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret ${APIC_INSTANCE_NAME}-mgmt-admin-pass -o=jsonpath='{.data.email}' 2> /dev/null ); then
    APIC_CM_ADMIN_EMAIL=$(echo $APIC_CM_ADMIN_EMAIL_B64 | base64 --decode)
    mylog info "APIC Cloud admin email. APIC_CM_ADMIN_EMAIL: ${APIC_CM_ADMIN_EMAIL}"
  fi
  
  # APIC Cloud Manager admin password
  if APIC_CM_ADMIN_PASSWORD_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret ${APIC_INSTANCE_NAME}-mgmt-admin-pass -o=jsonpath='{.data.password}' 2> /dev/null ); then
    APIC_CM_ADMIN_PASSWORD=$(echo $APIC_CM_ADMIN_PASSWORD_B64 | base64 --decode)
    mylog info "APIC Cloud Manager admin password. APIC_CM_ADMIN_PASSWORD: $APIC_CM_ADMIN_PASSWORD"
  fi
  
  # Common service namespace
  CS_NAMESPACE=$($MY_CLUSTER_COMMAND -n $MY_OPENSHIFT_OPERATORS get CommonServices $MY_COMMONSERVICES_INSTANCE_NAME -o jsonpath='{.spec.servicesNamespace}') 
  mylog info "Common service namespace. CS_NAMESPACE: $CS_NAMESPACE"
  
  # Cloud pak admin uid
  CP_ADMIN_UID=$($MY_CLUSTER_COMMAND -n "${CS_NAMESPACE}" get secret platform-auth-idp-credentials -o=jsonpath='{.data.admin_username}' | base64 --decode)
  mylog info "Cloud pak admin uid. CP_ADMIN_UID: $CP_ADMIN_UID" 1>&2
  
  # Cloud pak admin password
  CP_ADMIN_PASSWORD=$($MY_CLUSTER_COMMAND -n "${CS_NAMESPACE}" get secret platform-auth-idp-credentials -o=jsonpath='{.data.admin_password}' | base64 --decode)
  mylog info "Cloud pak admin password. CP_ADMIN_PASSWORD: ${CP_ADMIN_PASSWORD}"
  
  IAM_TOKEN=$(curl -kfs -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -d "grant_type=password&username=${CP_ADMIN_UID}&password=${CP_ADMIN_PASSWORD}&scope=openid" "https://${EP_CPADM}"/v1/auth/identitytoken | jq -r .access_token)
  mylog info "IAM Token. IAM_TOKEN: $IAM_TOKEN" 1>&2
  ZEN_TOKEN=$(curl -kfs https://"${EP_ZEN}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)
  mylog info "ZEN Token. ZEN_TOKEN: $ZEN_TOKEN" 1>&2
  CM_APIC_TOKEN=$(curl -kfs https://"${EP_API}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)
  mylog info "Cloud Manager apic token. CM_APIC_TOKEN: $CM_APIC_TOKEN" 1>&2
  
  # APIC_NAMESPACE=$($MY_CLUSTER_COMMAND get apiconnectcluster -A -o jsonpath='{..namespace}')
  APIC_INSTANCE=$($MY_CLUSTER_COMMAND -n "${apic_project}" get apiconnectcluster -o=jsonpath='{.items[0].metadata.name}')
  mylog info "APIC Project and APIC Instance. APIC_NAMESPACE/APIC_INSTANCE: ${apic_project}/${APIC_INSTANCE_NAME}"
  
  PLATFORM_API_URL=$($MY_CLUSTER_COMMAND -n "${apic_project}" get apiconnectcluster "${APIC_INSTANCE_NAME}" -o=jsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}')
  mylog info "APIC Platform URL. PLATFORM_API_URL: ${PLATFORM_API_URL}"
  
  if test ! -e "toolkit-linux.tgz";then
  	mylog info "Downloading toolkit" 1>&2
    $MY_CLUSTER_COMMAND -n "${apic_project}" cp "$($MY_CLUSTER_COMMAND -n "${apic_project}" get po -l app.kubernetes.io/name=client-downloads-server,app.kubernetes.io/part-of="${APIC_INSTANCE}" -o=jsonpath='{.items[0].metadata.name}')":dist/toolkit-linux.tgz toolkit-linux.tgz
    tar -xf toolkit-linux.tgz  && sudo mv apic-slim /usr/local/bin/apic
  fi
  
  APIC_CRED=$($MY_CLUSTER_COMMAND -n "${apic_project}" get secret ${APIC_INSTANCE_NAME}-mgmt-cli-cred  -o jsonpath='{.data.credential\.json}' | base64 --decode)
  mylog info "APIC Credentials. APIC_CRED: ${APIC_CRED}"
  
  APIC_APIKEY=$(curl -ks --fail -X POST "${PLATFORM_API_URL}"cloud/api-keys -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -d '{"client_type":"toolkit","description":"Tookit API key"}' | jq -r .api_key)
  decho $lf_tracelevel "APIC Key. APIC_APIKEY: ${APIC_APIKEY}"
  
  APIM_ENDPOINT=$($MY_CLUSTER_COMMAND -n "${apic_project}" get mgmt "${APIC_INSTANCE_NAME}-mgmt" -o jsonpath='{.status.zenRoute}')
  mylog info "APIC Management Endpoint. APIM_ENDPOINT: ${APIM_ENDPOINT}"
  
  # ./apic login --context admin --server https://"${APIM_ENDPOINT}" --sso --apiKey "${APIC_APIKEY}"
  
  # The goal is to get the apikey defined in the realm provider/common-services, get the credentials for the toolkit, then use the token endpoint to get an oauth token for Cloud Manager from API Key
  # TOOLKIT_CLIENT_ID=$(grep "^toolkit_client_id:" ~/.apiconnect/config-apim | cut -d ':' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  # TOOLKIT_CLIENT_SECRET=$(grep "^toolkit_client_secret:" ~/.apiconnect/config-apim | cut -d ':' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  TOOLKIT_CLIENT_ID=$(echo ${APIC_CRED} | jq -r .id)
  TOOLKIT_CLIENT_SECRET=$(echo ${APIC_CRED} | jq -r .secret)
  
  # cmToken=$(curl -ks --fail -X POST "${PLATFORM_API_URL}token" \
  #  -H 'Content-Type: application/json' \
  #  -H 'Accept: application/json' \
  #  -H "X-Ibm-Client-Id: $TOOLKIT_CLIENT_ID" \
  #  -H "X-Ibm-Client-Secret: $TOOLKIT_CLIENT_SECRET" \
  #  --data-binary  "{\"api_key\":\"$APIC_APIKEY\",\"client_id\":\"$TOOLKIT_CLIENT_ID\",\"client_secret\":\"$TOOLKIT_CLIENT_SECRET\",\"grant_type\":\"api_key\"}")
  
  echo "{\"username\": \"admin\", \"password\": \"$APIC_CM_ADMIN_PASSWORD\", \"realm\": \"admin/default-idp-1\", \"client_id\": \"$TOOLKIT_CLIENT_ID\", \"client_secret\": \"$TOOLKIT_CLIENT_SECRET\", \"grant_type\": \"password\"}" > "${MY_WORKINGDIR}creds.json"
  
  cmToken=$(curl -ks -X POST "${PLATFORM_API_URL}api/token" \
   -H 'Content-Type: application/json' \
   -H 'Accept: application/json' \
   --data-binary "@${MY_WORKINGDIR}creds.json")
  
  # mylog info "cmToken: ${cmToken}"
  # decho $lf_tracelevel "cmToken: $cmToken"

  if [ $(echo $cmToken | jq .status ) = "401" ] ; then
    mylog error "Error with login -> $cmToken"
    mylog warning "Probably don't need to change password"
  elif [ $(echo $cmToken | jq .access_token) != "null" ]
    then
      # echo "Try to Change password"
      access_token=$(echo $cmToken | jq .access_token | sed -e s/\"//g);
      apicme=$(curl -ks "${PLATFORM_API_URL}api/me" \
        -X PUT \
        -H "Authorization: Bearer $access_token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        --data-binary "{\"email\":\"$APIC_ADMIN_EMAIL\"}" | jq 'del(.url)')
      mylog info $apicme
  
  #      curl -kv "${PLATFORM_API_URL}api/me/change-password" \
  #        -H "Authorization: Bearer $access_token" \
  #        -H 'Content-Type: application/json' \
  #        -H 'Accept: application/json' \
  #        --data-binary "{\"current_password\":\"7iron-hide\",\"password\":\"$apic_admin_password\"}" 
  fi
  
  # mylog info "access_token: ${access_token}"
  
  TOOLKIT_CREDS_URL="${PLATFORM_API_URL}api/cloud/settings/toolkit-credentials"
  
  # always download the credential.json
  # if test ! -e "~/.apiconnect/config-apim";then
   	mylog info "Downloading apic config json file" 1>&2
   	curl -ks "${TOOLKIT_CREDS_URL}" -H "Authorization: Bearer ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -o creds.json
  	yes | apic client-creds:set creds.json
  # 	[[ -e creds.json ]] && rm creds.json
  # fi  

  tlsServer=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/tls-server-profiles" \
   -H "Authorization: Bearer $access_token" \
   -H 'Accept: application/json' --compressed | jq .results[0].url  | sed -e s/\"//g);
  mylog info  "tlsServer: $tlsServer"
  
  tlsClientDefault=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/tls-client-profiles" \
   -H "Authorization: Bearer $access_token" \
   -H 'Accept: application/json' --compressed | jq '.results[] | select(.name=="tls-client-profile-default")| .url' | sed -e s/\"//g);
  mylog info  "tlsClientDefault: $tlsClientDefault"
  
  integration_url=$(curl -sk "${PLATFORM_API_URL}api/cloud/integrations" \
   -H "Authorization: Bearer $access_token" \
   -H 'Accept: application/json' --compressed | jq -r '.results[] | select(.integration_type=="gateway_service") | select(.name=="datapower-api-gateway")| .url');
  mylog info  "integration_url: $integration_url"

}
################################################################################################
# Start of the script main entry
# main
# This script ineeds to be started in the same directory as this script.

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
configdir="${scriptdir}../resources/"
libdir="${scriptdir}../../../"
MY_WORKINGDIR="${scriptdir}../../../working/"

# load helper functions
. "${libdir}"lib.sh

read_config_file "${scriptdir}apic.properties"

# Get_APIC_Infos
# Retrieve the various routes for APIC components
# API Manager URL
EP_API=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-mgmt-platform-api" -o jsonpath="{.spec.host}")
mylog info "EP_API: ${EP_API}"
# gwv6-gateway-manager
EP_GWD=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-gw-gateway-manager" -o jsonpath="{.spec.host}")
# gwv6-gateway
EP_GW=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-gw-gateway" -o jsonpath="{.spec.host}")
mylog info "EP_GW: ${EP_GW}"
# analytics-ai-endpoint
EP_AI=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-a7s-ai-endpoint" -o jsonpath="{.spec.host}")
# portal-portal-director
EP_PADMIN=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-ptl-portal-director" -o jsonpath="{.spec.host}")
# portal-portal-web
EP_PORTAL=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-ptl-portal-web" -o jsonpath="{.spec.host}")
mylog info "EP_PORTAL: $EP_PORTAL"
# Zen
if EP_ZEN=$($MY_CLUSTER_COMMAND -n ${apic_project} get route cpd -o jsonpath="{.spec.host}" 2> /dev/null ); then
  mylog info "EP_PORTAL: $EP_ZEN"
fi
# Cloud pak administration console
EP_CPADM=$($MY_CLUSTER_COMMAND -n kube-public get cm ibmcloud-cluster-info -o jsonpath='{.data.cluster_address}')
mylog info "EP_CPADM: ${EP_CPADM}"
# APIC Gateway admin password
if APIC_GTW_PASSWORD_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret ${APIC_INSTANCE_NAME}-gw-admin -o=jsonpath='{.data.password}' 2> /dev/null ); then
  APIC_GTW_PASSWORD=$(echo $APIC_GTW_PASSWORD_B64 | base64 --decode)
  mylog info "APIC_GTW_PASSWORD: $APIC_GTW_PASSWORD"
fi

EP_APIC_CM=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-mgmt-admin" -o jsonpath="{.spec.host}")
mylog info "Cloud Manager endpoint: $EP_APIC_CM"
EP_APIC_MGR=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-mgmt-api-manager" -o jsonpath="{.spec.host}")
mylog info "API Manager endpoint: $EP_APIC_MGR"

# APIC Cloud Manager admin password
if APIC_CM_ADMIN_PASSWORD_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret ${APIC_INSTANCE_NAME}-mgmt-admin-pass -o=jsonpath='{.data.password}' 2> /dev/null ); then
  APIC_CM_ADMIN_PASSWORD=$(echo $APIC_CM_ADMIN_PASSWORD_B64 | base64 --decode)
  mylog info "APIC_CM_ADMIN_PASSWORD: $APIC_CM_ADMIN_PASSWORD"
fi
# Common service namespace
CS_NAMESPACE=$($MY_CLUSTER_COMMAND get commonservice -A -o jsonpath='{..namespace}' | awk '{print $1}')
# Cloud pak admin password
CP_ADMIN_PASSWORD=$($MY_CLUSTER_COMMAND -n "${CS_NAMESPACE}" get secret platform-auth-idp-credentials -o=jsonpath='{.data.admin_password}' | base64 --decode)
mylog info "CP_ADMIN_PASSWORD: ${CP_ADMIN_PASSWORD}"

# Cloud pak admin uid (should be admin)
CP_ADMIN_UID=$($MY_CLUSTER_COMMAND -n "${CS_NAMESPACE}" get secret platform-auth-idp-credentials -o=jsonpath='{.data.admin_username}' | base64 --decode)
IAM_TOKEN=$(curl -kfs -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -d "grant_type=password&username=${CP_ADMIN_UID}&password=${CP_ADMIN_PASSWORD}&scope=openid" "https://${EP_CPADM}"/v1/auth/identitytoken | jq -r .access_token)
# mylog warn "IAM_TOKEN: $IAM_TOKEN" 1>&2
ZEN_TOKEN=$(curl -kfs https://"${EP_ZEN}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)
# mylog warn "ZEN_TOKEN: $ZEN_TOKEN" 1>&2
CM_APIC_TOKEN=$(curl -kfs https://"${EP_API}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)
# mylog warn "CM_APIC_TOKEN: $CM_APIC_TOKEN" 1>&2

# APIC_NAMESPACE=$($MY_CLUSTER_COMMAND get apiconnectcluster -A -o jsonpath='{..namespace}')
APIC_INSTANCE=$($MY_CLUSTER_COMMAND -n "${apic_project}" get apiconnectcluster -o=jsonpath='{.items[0].metadata.name}')
mylog info "APIC_NAMESPACE/APIC_INSTANCE: ${apic_project}/${APIC_INSTANCE_NAME}"

PLATFORM_API_URL=$($MY_CLUSTER_COMMAND -n "${apic_project}" get apiconnectcluster "${APIC_INSTANCE_NAME}" -o=jsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}')

if test ! -e "toolkit-linux.tgz";then
	mylog info "Downloading toolkit" 1>&2
  $MY_CLUSTER_COMMAND -n "${apic_project}" cp "$($MY_CLUSTER_COMMAND -n "${apic_project}" get po -l app.kubernetes.io/name=client-downloads-server,app.kubernetes.io/part-of="${APIC_INSTANCE}" -o=jsonpath='{.items[0].metadata.name}')":dist/toolkit-linux.tgz toolkit-linux.tgz
  tar -xf toolkit-linux.tgz  && mv apic-slim apic
fi

APIC_CRED=$($MY_CLUSTER_COMMAND -n "${apic_project}" get secret ${APIC_INSTANCE_NAME}-mgmt-cli-cred  -o jsonpath='{.data.credential\.json}' | base64 --decode)
mylog info "APIC_CRED: ${APIC_CRED}"

APIC_APIKEY=$(curl -ks --fail -X POST "${PLATFORM_API_URL}"cloud/api-keys -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -d '{"client_type":"toolkit","description":"Tookit API key"}' | jq -r .api_key)
decho $lf_tracelevel "APIC_APIKEY: ${APIC_APIKEY}"

# The goal is to get the apikey defined in the realm provider/common-services, get the credentials for the toolkit, then use the token endpoint to get an oauth token for Cloud Manager from API Key
# TOOLKIT_CLIENT_ID=$(grep "^toolkit_client_id:" ~/.apiconnect/config-apim | cut -d ':' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
# TOOLKIT_CLIENT_SECRET=$(grep "^toolkit_client_secret:" ~/.apiconnect/config-apim | cut -d ':' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
TOOLKIT_CLIENT_ID=$(echo ${APIC_CRED} | jq -r .id)
TOOLKIT_CLIENT_SECRET=$(echo ${APIC_CRED} | jq -r .secret)

# cmToken=$(curl -ks --fail -X POST "${PLATFORM_API_URL}token" \
#  -H 'Content-Type: application/json' \
#  -H 'Accept: application/json' \
#  -H "X-Ibm-Client-Id: $TOOLKIT_CLIENT_ID" \
#  -H "X-Ibm-Client-Secret: $TOOLKIT_CLIENT_SECRET" \
#  --data-binary  "{\"api_key\":\"$APIC_APIKEY\",\"client_id\":\"$TOOLKIT_CLIENT_ID\",\"client_secret\":\"$TOOLKIT_CLIENT_SECRET\",\"grant_type\":\"api_key\"}")

echo "{\"username\": \"admin\", \"password\": \"$APIC_CM_ADMIN_PASSWORD\", \"realm\": \"admin/default-idp-1\", \"client_id\": \"$TOOLKIT_CLIENT_ID\", \"client_secret\": \"$TOOLKIT_CLIENT_SECRET\", \"grant_type\": \"password\"}" > "${MY_WORKINGDIR}creds.json"

cmToken=$(curl -ks -X POST "${PLATFORM_API_URL}api/token" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 --data-binary "@${MY_WORKINGDIR}creds.json")

# mylog info "cmToken: ${cmToken}"
# decho $lf_tracelevel "cmToken: $cmToken"

if [ $(echo $cmToken | jq .status ) = "401" ] ; then
  mylog error "Error with login -> $cmToken"
  mylog warning "Probably don't need to change password"
elif [ $(echo $cmToken | jq .access_token) != "null" ]
  then
    # echo "Try to Change password"
    access_token=$(echo $cmToken | jq .access_token | sed -e s/\"//g);

#      curl -kv "${PLATFORM_API_URL}api/me/change-password" \
#        -H "Authorization: Bearer $access_token" \
#        -H 'Content-Type: application/json' \
#        -H 'Accept: application/json' \
#        --data-binary "{\"current_password\":\"7iron-hide\",\"password\":\"$apic_admin_password\"}" 
fi

# mylog info "access_token: ${access_token}"

TOOLKIT_CREDS_URL="${PLATFORM_API_URL}api/cloud/settings/toolkit-credentials"

# always download the credential.json
# if test ! -e "~/.apiconnect/config-apim";then
 	mylog info "Downloading apic config json file" 1>&2
 	curl -ks "${TOOLKIT_CREDS_URL}" -H "Authorization: Bearer ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -o creds.json
	yes | apic client-creds:set creds.json
# 	[[ -e creds.json ]] && rm creds.json
# fi

CreateMailServer "${APIC_SMTP_SERVER}" "${APIC_SMTP_SERVER_PORT}"

tlsServer=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/tls-server-profiles" \
 -H "Authorization: Bearer $access_token" \
 -H 'Accept: application/json' --compressed | jq .results[0].url  | sed -e s/\"//g);
# mylog info  "tlsServer: $tlsServer"

tlsClientDefault=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/tls-client-profiles" \
 -H "Authorization: Bearer $access_token" \
 -H 'Accept: application/json' --compressed | jq '.results[] | select(.name=="tls-client-profile-default")| .url' | sed -e s/\"//g);
# mylog info  "tlsClientDefault: $tlsClientDefault"

integration_url=$(curl -sk "${PLATFORM_API_URL}api/cloud/integrations" \
 -H "Authorization: Bearer $access_token" \
 -H 'Accept: application/json' --compressed | jq -r '.results[] | select(.integration_type=="gateway_service") | select(.name=="datapower-api-gateway")| .url');
# mylog info  "integration_url: $integration_url"

gateway_service="datapower-api-gateway"

CreateTopology

CreateOrg "${APIC_PROVIDER_ORG}" "${APIC_ORG1_USERNAME}" "${APIC_ORG1_PASSWORD}" "${APIC_ORG1_USER_EMAIL}"

# get token for the API Manager for 
amToken=$(curl -sk --fail -X POST "${PLATFORM_API_URL}api/token" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 --data-binary "{\"username\":\"$APIC_ORG1_USERNAME\",\"password\":\"$APIC_ORG1_PASSWORD\",\"realm\":\"provider/default-idp-2\",\"client_id\":\"$TOOLKIT_CLIENT_ID\",\"client_secret\":\"$TOOLKIT_CLIENT_SECRET\",\"grant_type\":\"password\"}" |  jq .access_token | sed -e s/\"//g  )

# decho $lf_tracelevel "amToken: $amToken"
# TODO Not sure the use of $? is good, this is the result of the sed command
retVal=$?
if [ $retVal -ne 0 ] || [ -z "$amToken" ] || [ "$amToken" = "null" ]; then
  mylog error "Error with login -> $retVal" 1>&2
  exit 1
fi

CreateCatalog "${APIC_PROVIDER_ORG}"

# Push API into draft
apic_provider_org1_lower=$(echo "$APIC_PROVIDER_ORG" | awk '{print tolower($0)}')
api_name=ping-api
# TODO Make it a function, to load any API
# LoadAPI $PLATFORM_API_URL $apic_provider_org1_lower $api_name $amToken
# mylog info "${PLATFORM_API_URL}api/orgs/$apic_provider_org1_lower/drafts/draft-apis/$api_name?fields=url -H \"Authorization: Bearer $amToken\" -H 'Accept: application/json'"
pingAPI=$(curl -sk "${PLATFORM_API_URL}api/orgs/$apic_provider_org1_lower/drafts/draft-apis/$api_name?fields=url" -H "Authorization: Bearer $amToken" -H 'Accept: application/json' > /dev/null 2>&1)
# mylog info "pingAPI: $pingAPI"
if [ -z "$pingAPI" ] || [ "$pingAPI" = "null" ]; then
# if ! curl -sk "${PLATFORM_API_URL}api/orgs/$apic_provider_org1_lower/drafts/draft-apis/$api_name?fields=url" -H "Authorization: Bearer $amToken" -H 'Accept: application/json' > /dev/null 2>&1; then
  # draftAPICLEAR=$(curl -sk --request DELETE "${PLATFORM_API_URL}api/orgs/$APIC_PROVIDER_ORG/drafts/draft-apis/pingapi?confirm=$APIC_PROVIDER_ORG" -H "Accept: application/json" -H "authorization: Bearer $amToken");
  mylog info "Load test API (Ping API) as a draft"
  api=`cat ${configdir}apis/ping-api_1.0.0.json`;

  # remove ?gateway_type=datapower-api-gateway&api_type=rest
  draftAPI=$(curl -sk "https://${EP_APIC_MGR}/api/orgs/${apic_provider_org1_lower}/drafts/draft-apis?gateway_type=datapower-api-gateway&api_type=rest" \
    -H 'accept: application/json' \
    -H "authorization: Bearer $amToken" \
    -H 'content-type: application/json' \
    -H "Connection: keep-alive" \
    --compressed \
    --data "{\"draft_api\":$api}" );
  mylog info $draftAPI;
else
  mylog info "$api_name already exists, do not load it."
fi

# Removed analytics-client-default not used anymore

# echo "--------------- Endpoint ---------------------"
# echo " Cloud manager : https://$MGMT_ADMIN_EP.$STACK_HOST (admin/$apic_admin_password)"
# echo " API manager : https://$MGMT_API_EP.$STACK_HOST ($ORG_USERNAME/$ORG_PASSWORD)"
# echo "----------------------------------------------"

duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2