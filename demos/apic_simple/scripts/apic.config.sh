#!/bin/bash

################################################
# Create mail server configuration
# @param mail_server_ip: IP of the mail server, example: 
# @param mail_server_ip: Port of the mail server, example: 2525
function create_mail_server() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}  
  local mail_server_ip=$1
  local mail_server_port=$2

  mailServerUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/mail-servers/generatedemailserver?fields=url" \
  -H "Accept: application/json" \
  --compressed \
  -H "authorization: Bearer $access_token" \
  -H "content-type: application/json" \
  -H "Connection: keep-alive")

  # TODO If exist alors change it with properties

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

  trace_out $lf_tracelevel ${FUNCNAME[0]}  
}

################################################
# Create an organisation owned by a specific user
# @param org_name: The name of the organisation. It allows upper cases, the id will be lowered, but the orignal value will be used elsewhere (title, summary)
# @param org_owner_id: The id of the owner of the organisation, it is used for his firstname and lastname
# @param org_owner_pwd: The password of the owner of the organisation
# @param org_owner_email: The email of the owner of the organisation
function create_org() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}  

  local org_name=$1
  local org_owner_id=$2
  local org_owner_pwd=$3
  local org_owner_email=$4

  # userRegistryUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/user-registries" \
  #   -H "Authorization: Bearer $access_token" \
  #   -H 'Accept: application/json' \
  #   --compressed)

  # first create owner of organisation

  userUrl=$(curl -sk "${PLATFORM_API_URL}api/user-registries/admin/api-manager-lur/users/$org_owner_id?fields=url" \
    -H "Accept: application/json" \
    --compressed \
    -H "Authorization: Bearer $access_token" \
    -H "Content-type: application/json")
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

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create the topology (check if needed for cp4i installation)
function create_topology() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_integration_url=$1

  # should increase idempotence
  mylog info "Create gateway Service"

  decho $lf_tracelevel "Interact with Cloud Manager: curl -sk \"${PLATFORM_API_URL}api/orgs/admin/tls-server-profiles\"  -H \"Authorization: Bearer <access_token>\"  -H 'Accept: application/json'"
  tlsServer=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/tls-server-profiles" \
   -H "Authorization: Bearer $access_token" \
   -H 'Accept: application/json' --compressed | jq .results[0].url  | sed -e s/\"//g);
  decho $lf_tracelevel "tlsServer: $tlsServer"
  
  tlsClientDefault=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/tls-client-profiles" \
   -H "Authorization: Bearer $access_token" \
   -H 'Accept: application/json' --compressed | jq '.results[] | select(.name=="tls-client-profile-default")| .url' | sed -e s/\"//g);
  decho $lf_tracelevel "tlsClientDefault: $tlsClientDefault"
  
  #TODO  : use and in select : select(.integration_type=="gateway_service" --and .name=="datapower-api-gateway")| .url'
  integration_url=$(curl -sk "${PLATFORM_API_URL}api/cloud/integrations" \
   -H "Authorization: Bearer $access_token" \
   -H 'Accept: application/json' --compressed | jq -r '.results[] | select(.integration_type=="gateway_service" and .name=="datapower-api-gateway")| .url');
  decho $lf_tracelevel "integration_url: $integration_url"
  
  mylog info "{\"name\":\"apigateway-service\",\"title\":\"API Gateway Service\",\"endpoint\":\"https://$EP_GWD\",\"api_endpoint_base\":\"https://$EP_GW\",\"tls_client_profile_url\":\"$tlsClientDefault\",\"gateway_service_type\":\"$ep_gwType\",\"visibility\":{\"type\":\"public\"},\"sni\":[{\"host\":\"*\",\"tls_server_profile_url\":\"$tlsServer\"}],\"integration_url\":\"${integration_url}\"}"

  dpUrl=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/availability-zones/availability-zone-default/gateway-services" \
  -H "Authorization: Bearer $access_token" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Connection: keep-alive' \
  --data-binary "{\"name\":\"apigateway-service\",\"title\":\"API Gateway Service\",\"endpoint\":\"https://$EP_GWD\",\"api_endpoint_base\":\"https://$EP_GW\",\"tls_client_profile_url\":\"$tlsClientDefault\",\"gateway_service_type\":\"$ep_gwType\",\"visibility\":{\"type\":\"public\"},\"sni\":[{\"host\":\"*\",\"tls_server_profile_url\":\"$tlsServer\"}],\"integration_url\":\"${integration_url}\"}" \
  --compressed | jq .url | sed -e s/\"//g);

  decho $lf_tracelevel "dpUrl: $dpUrl"

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

  decho $lf_tracelevel "analytUrl: $analytUrl"

  mylog info "Associate Analytics Service with Gateway"

  analytGwy=$(curl -sk -X PATCH \
    "${PLATFORM_API_URL}api/orgs/admin/availability-zones/availability-zone-default/gateway-services/apigateway-service" \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $access_token"\
  -H 'Cache-Control: no-cache' \
  -H 'Content-Type: application/json' \
  --data-binary "{\"analytics_service_url\":	\"$analytUrl\" }");

  decho $lf_tracelevel "analytGwy: $analytGwy"

  mylog info "Create Portal Service"

  createPortal=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/availability-zones/availability-zone-default/portal-services"\
  -H "Accept: application/json"\
  -H "authorization: Bearer $access_token"\
  -H "content-type: application/json"\
  --data "{\"title\":\"API Portal Service\",\"name\":\"portal-service\",\"endpoint\":\"https://$EP_PADMIN\",\"web_endpoint_base\":\"https://$EP_PORTAL\",\"visibility\":{\"group_urls\":null,\"org_urls\":null,\"type\":\"public\"}}");

  decho $lf_tracelevel "createPortal: $createPortal"

  trace_out $lf_tracelevel ${FUNCNAME[0]} 
}

################################################
# Create a catalog in an organisation
# catalogs specifications of the 3 catalogs are hard coded
# @param org_name: The name of the organisation.
function create_catalog() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local org_name=$(echo "$1" | awk '{print tolower($0)}')

# decho $lf_tracelevel "url: ${PLATFORM_API_URL}api/orgs/$org_name/catalogs and token: $amToken"

# Hard coded values
catalog_title=("Prod" "UAT" "QA")
catalog_name=("prod" "uat" "qa")
catalog_summary=("Production" "UAT" "Quality and Acceptance")

  decho $lf_tracelevel "Interact with API Manager: curl -sk -X GET \"${PLATFORM_API_URL}api/orgs/$org_name/portal-services?fields=url\" -H \"Authorization: Bearer <amToken>\" -H 'accept: application/json' -H 'content-type: application/json' -H 'Connection: keep-alive'"
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

      # TODO Check if we can skip this action if already done
      mylog info "Create the portal site in Drupal for: "${catalog_summary[$index]}"";
      res=$(curl -sk -X PUT "$catURL/settings" \
       -H "Authorization: Bearer $amToken" \
       -H 'accept: application/json' \
       -H 'content-type: application/json' \
       -H 'Connection: keep-alive' \
       --data-binary "{\"portal\": {\"endpoint\": \"https://$EP_PORTAL/$org_name/${catalog_name[$index]}\",\"portal_service_url\": \"$portalServiceURL\", \"type\": \"drupal\"},\"application_lifecycle\": {} }" | jq .portal.endpoint);
      # mylog info "Portal endpoint for: "${catalog_summary[$index]}": $res"
    done
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create resources
# @param lf_integration_url
function create_apic_resources() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_cm_token=$1
  local lf_am_token=$2
  local org=$3
  
  # Check if already created
  decho $lf_tracelevel "curl -sk \"${PLATFORM_API_URL}api/user-registries/admin/url_registry?fields=url\" -H \"Authorization: Bearer cmtoken\" -H 'Accept: application/json'"
  local registryURLfakeAPI=$(curl -sk "${PLATFORM_API_URL}api/user-registries/admin/url_registry?fields=url" -H "Authorization: Bearer $lf_cm_token" -H 'Accept: application/json')
  decho $lf_tracelevel "registryURLfakeAPI: $registryURLfakeAPI"
  if [ $(echo $registryURLfakeAPI | jq .status ) = "404" ] || [ -z "$registryURLfakeAPI" ] || [ "$registryURLfakeAPI" = "null" ]; then
    mylog info "Create URL Fake Authentication URL registry."
    # get integration url for (UserRegistry Subcollection), needed for the user registry creation
    export APIC_INTEGRATION_URL=$(curl -sk --fail "${PLATFORM_API_URL}api/cloud/integrations/user-registry/authurl?fields=url" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H 'Connection: keep-alive' \
    -H "Authorization: Bearer $lf_cm_token" | jq -r .url)
    # get the gateway route in order to provide the endpoint of the fake URL authentication api which should be published
    gtw_url=$($MY_CLUSTER_COMMAND -n ${apic_project} get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].status.endpoints[?(@.name=="gateway")].uri}')
    export APIC_EP_GTW=${gtw_url}
    adapt_file ${MY_APIC_SIMPLE_DEMODIR}resources/ ${MY_APIC_WORKINGDIR}resources/ AuthenticationURL_Registry_res.json

    decho $lf_tracelevel "curl -sk \"${PLATFORM_API_URL}api/orgs/admin/user-registries\" -H 'accept: application/json' -H \"authorization: Bearer cm_token\" -H 'content-type: application/json' -H \"Connection: keep-alive\" --compressed --data-binary \"@${MY_APIC_WORKINGDIR}resources/AuthenticationURL_Registry_res.json\""
    registryURLfakeAPI=$(curl -sk "${PLATFORM_API_URL}api/orgs/admin/user-registries" \
      -H 'accept: application/json' \
      -H "authorization: Bearer $lf_cm_token" \
      -H 'content-type: application/json' \
      -H "Connection: keep-alive" \
      --compressed \
      --data-binary "@${MY_APIC_WORKINGDIR}resources/AuthenticationURL_Registry_res.json")
  else
    mylog info "URL Fake Authentication URL registry already exists, do not load it."
  fi

  # Get the url of the url registry in org
  # TODO : process null case
  lf_org=$APIC_PROVIDER_ORG
  lf_urlregistryname=url_registry
  lf_apicpath=api/user-registries/$lf_org/$lf_urlregistryname?fields=url
  decho $lf_tracelevel "curl -sk \"${PLATFORM_API_URL}${lf_apicpath}\" -H \"Authorization: Bearer $lf_am_token\" -H 'Accept: application/json' | jq -r .url"
  local sandboxURLRegistries=$(curl -sk "${PLATFORM_API_URL}${lf_apicpath}" -H "Authorization: Bearer $lf_am_token" -H 'Accept: application/json' | jq -r .url )
  decho $lf_tracelevel "sandboxURLRegistries: $sandboxURLRegistries"

  # Check if the registry has already been added
  lf_apicpath="api/catalogs/$org/$catalog/configured-api-user-registries?fields=user_registry_url"
  local sandboxCfgedRegistries=$(curl -sk "${PLATFORM_API_URL}${lf_apicpath}" -H "Authorization: Bearer $lf_am_token" -H 'Accept: application/json' | jq --arg ur "$sandboxCfgedRegistries" '.results[].user_registry_url | select(. == "$ur")')
  decho $lf_tracelevel "sandboxCfgedRegistries: $sandboxCfgedRegistries"

  export APIC_URL_REGISTRY=${sandboxURLRegistries}

  # Add it if not already added TODO if
  if [ 2 -gt 3 ]; then
    lf_apicpath=api/catalogs/$org/$catalog/configured-api-user-registries
    adapt_file ${MY_APIC_SIMPLE_DEMODIR}resources/ ${MY_APIC_WORKINGDIR}resources/ ConfiguredUserRegistry_res.json
    curl -sk "${PLATFORM_API_URL}${lf_apicpath}" \
      -H 'accept: application/json' \
      -H "authorization: Bearer $lf_am_token" \
      -H 'content-type: application/json' \
      -H "Connection: keep-alive" \
      --compressed \
      --data-binary "@${MY_APIC_WORKINGDIR}resources/ConfiguredUserRegistry_res.json"
  fi

  # Check if the oauth provider has already been added
  lf_org=admin
  lf_oauthprovidername=nativeprovider
  lf_apicpath=api/orgs/$lf_org/oauth-providers/$lf_oauthprovidername?fields=url
  
  local oauthProviderURL=$(curl -sk "${PLATFORM_API_URL}${lf_apicpath}" -H "Authorization: Bearer $lf_cm_token" -H 'Accept: application/json')
  if [ $(echo $oauthProviderURL | jq .status ) = "404" ] || [ -z "$oauthProviderURL" ] || [ "$oauthProviderURL" = "null" ]; then
    lf_apicpath=api/orgs/${lf_org}?fields=url
    admin_url=$(curl -sk "${PLATFORM_API_URL}${lf_apicpath}" -H "Authorization: Bearer $lf_cm_token" -H 'Accept: application/json' | jq -r .)
    export APIC_URL_REGISTRY_NAME=$lf_urlregistryname
    export APIC_ADMIN_URL=$admin_url
    adapt_file ${MY_APIC_SIMPLE_DEMODIR}resources/ ${MY_APIC_WORKINGDIR}resources/ NativeOAuthProvider_res.json
    lf_apicpath=api/orgs/$lf_org/oauth-providers
    oauthProvider=$(curl -sk "${PLATFORM_API_URL}${lf_apicpath}" \
      -H 'accept: application/json' \
      -H "authorization: Bearer $lf_cm_token" \
      -H 'content-type: application/json' \
      -H "Connection: keep-alive" \
      --compressed \
      --data-binary "@${MY_APIC_WORKINGDIR}resources/NativeOAuthProvider_res.json" | jq .url)
    decho $lf_tracelevel "oauthProvider: $oauthProvider"
  fi

  # Get the url of the oauth provider in org
  lf_org=APIC_PROVIDER_ORG
  lf_apicpath=api/orgs/$lf_org/oauth-providers/$lf_oauthprovidername?fields=url
  local oauthProviderURL=$(curl -sk "${PLATFORM_API_URL}${lf_apicpath}" -H "Authorization: Bearer $lf_am_token" -H 'Accept: application/json' | jq -r .url )
  decho $lf_tracelevel "oauthProviderURL: $oauthProviderURL"

  # Check if the oauth provider has already been added
  lf_apicpath="api/catalogs/$org/$catalog/configured-oauth-providers?fields=user_registry_url"
  local sandboxCfoauthProviderURL=$(curl -sk "${PLATFORM_API_URL}${lf_apicpath}" -H "Authorization: Bearer $lf_am_token" -H 'Accept: application/json' | jq --arg ur "$oauthProviderURL" '.results[].user_registry_url | select(. == "$ur")')
  decho $lf_tracelevel "sandboxCfoauthProviderURL: $sandboxCfoauthProviderURL"

  # Add it if not already added TODO if, important for idempotence  (hard coded for now)
  if [ 2 -gt 3 ]; then
    lf_org=APIC_PROVIDER_ORG
    lf_apicpath=api/catalogs/$org/$catalog/configured-oauth-providers
    export APIC_OAUTH_PROVIDER=$oauthProviderURL
    adapt_file ${MY_APIC_SIMPLE_DEMODIR}resources/ ${MY_APIC_WORKINGDIR}resources/ ConfiguredOAuthProvider_res.json
    curl -sk "${PLATFORM_API_URL}${lf_apicpath}" \
      -H 'accept: application/json' \
      -H "authorization: Bearer $lf_am_token" \
      -H 'content-type: application/json' \
      -H "Connection: keep-alive" \
      --compressed \
      --data-binary "@${MY_APIC_WORKINGDIR}resources/ConfiguredOAuthProvider_res.json"
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}


################################################
# Configure the AI Agent for VS Code extension
# Check if it can be done at cloud or org level ?
# @param .
function configureAIAgent() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # Configure the AI Agent for VS Code extension with watsonx.ai settings
  # host, credential (token) and project


  trace_out $lf_tracelevel ${FUNCNAME[0]}
}


################################################
# Load an API
# @param org_name: The name of the organisation.
function load_apis () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local platform_api_url=$1
  local apic_provider_org=$2
  local token=$3

# First set the variables needed to adapt each file

# Definition of all the API, the order is important betwen the two arrays
api_names=("ping-api" "ibm-sample-order-api" "stock" "fakeauthenticationurl" "takeoff" "landings" "taxi-locator" "taxi-messaging" "swaggerpetstoreopenapi-3-0" "swagger-petstore" "httpbin" "SIM Swap")
api_files=("ping-api_1.0.0.json" "ibm-sample-order-api_1.0.0.json" "stock_1.0.0.json" "fakeauthenticationurl_1.0.0.json" "takeoff_1.0.0.json" "landings_2.0.0.json" "taxi-locator_1.0.0.json" "taxi-messaging_1.0.0.json" "swaggerpetstoreopenapi-3-0_1.0.11.json" "swagger-petstore_1.0.6.json" "httpbin-1.0.0.json" "SIM_Swap-1.0.0.json")

for index in ${!api_names[@]}
  do
    adapt_file ${MY_APIC_SIMPLE_DEMODIR}resources/ ${MY_APIC_WORKINGDIR}resources/ ${api_files[$index]}
    decho $lf_tracelevel "curl -sk \"${platform_api_url}api/orgs/${apic_provider_org}/drafts/draft-apis/${api_names[$index]}?fields=url\" -H \"Authorization: Bearer <token>\" -H 'Accept: application/json'"
    local api_uri_result=$(curl -sk "${platform_api_url}api/orgs/${apic_provider_org}/drafts/draft-apis/${api_names[$index]}?fields=url" -H "Authorization: Bearer $token" -H 'Accept: application/json' | jq -r .total_results)
    if [[ $api_uri_result -eq 0 ]]; then
      mylog info "Load ${api_names[$index]} API as a draft"
      local api_content=`cat ${MY_APIC_WORKINGDIR}resources/${api_files[$index]}`;
      draftAPI=$(curl -sk "https://${EP_APIC_MGR}/api/orgs/${apic_provider_org}/drafts/draft-apis?gateway_type=datapower-api-gateway&api_type=rest" \
        -H 'accept: application/json' \
        -H "authorization: Bearer $token" \
        -H 'content-type: application/json' \
        -H "Connection: keep-alive" \
        --compressed \
        --data "{\"draft_api\":$api_content}" );
      mylog info $draftAPI;
    else
      mylog info "${api_names[$index]} API already exists, do not load it."
    fi
  done
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}


################################################
# Init APIC variables
function init_apic_variables() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # Retrieve the various routes for APIC components
  # API Manager URL
  EP_API=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-mgmt-platform-api" -o jsonpath="{.spec.host}")
  decho $lf_tracelevel "EP_API: $EP_API"
  # gwv6-gateway-manager
  EP_GWD=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-gwv6-gateway-manager" -o jsonpath="{.spec.host}")
  decho $lf_tracelevel "EP_GWD: $EP_GWD"
  # gwv6-gateway
  EP_GW=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-gwv6-gateway" -o jsonpath="{.spec.host}")
  decho $lf_tracelevel "EP_GW: $EP_GW"
  # analytics-ai-endpoint
  EP_AI=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-a7s-ai-endpoint" -o jsonpath="{.spec.host}")
  decho $lf_tracelevel "EP_AI: $EP_AI"
  # portal-portal-director
  EP_PADMIN=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-ptl-portal-director" -o jsonpath="{.spec.host}")
  decho $lf_tracelevel "EP_PADMIN: $EP_PADMIN"
  # portal-portal-web
  EP_PORTAL=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-ptl-portal-web" -o jsonpath="{.spec.host}")
  decho $lf_tracelevel "EP_PORTAL: $EP_PORTAL"
  # Zen
  if EP_ZEN=$($MY_CLUSTER_COMMAND -n ${apic_project} get route cpd -o jsonpath="{.spec.host}" 2> /dev/null ); then
    mylog info "EP_PORTAL: $EP_ZEN"
    decho $lf_tracelevel "EP_ZEN: $EP_ZEN"
  fi
  EP_APIC_MGR=$($MY_CLUSTER_COMMAND -n ${apic_project} get route "${APIC_INSTANCE_NAME}-mgmt-api-manager" -o jsonpath="{.spec.host}")
  decho $lf_tracelevel "EP_APIC_MGR: $EP_APIC_MGR"
  
  # APIC Gateway admin password - TODO Not used here ?
  if APIC_GTW_PASSWORD_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret ${APIC_INSTANCE_NAME}-gw-admin -o=jsonpath='{.data.password}' 2> /dev/null ); then
    APIC_GTW_PASSWORD=$(echo $APIC_GTW_PASSWORD_B64 | base64 --decode)
  fi

  # APIC Cloud Manager admin password
  mylog info "With APIC V12 there is a change on the user password the default value is 7iron-hide that need to be changed at first login." 1>&2
  mylog info "For compatibilty reason, I'm going to use the secret apic-mgmt-admin-pass that needs to be updated when you change the value." 1>&2
  
  if CM_ADMIN_UID_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret apic-mgmt-admin-pass -o=jsonpath='{.data.email}' 2> /dev/null ); then
    CM_ADMIN_UID=$(echo $CM_ADMIN_UID_B64 | base64 --decode)
    decho $lf_tracelevel "CM_ADMIN_UID: $CM_ADMIN_UID"
  fi

  if CM_ADMIN_PASSWORD_B64=$($MY_CLUSTER_COMMAND -n ${apic_project} get secret apic-mgmt-admin-pass -o=jsonpath='{.data.password}' 2> /dev/null ); then
    CM_ADMIN_PASSWORD=$(echo $CM_ADMIN_PASSWORD_B64 | base64 --decode)
    decho $lf_tracelevel "CM_ADMIN_PASSWORD: $CM_ADMIN_PASSWORD"
  fi
  decho $lf_tracelevel "curl -kfs -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -d \"grant_type=password&username=${CM_ADMIN_UID}&password=${CM_ADMIN_PASSWORD}&scope=openid\" \"https://${EP_API}/v1/auth/identitytoken\" | jq -r .access_token"
  IAM_TOKEN=$(curl -kfs -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' -d "grant_type=password&username=${CM_ADMIN_UID}&password=${CM_ADMIN_PASSWORD}&scope=openid" "https://${EP_API}/v1/auth/identitytoken" | jq -r .access_token)
  mylog warn "IAM_TOKEN: $IAM_TOKEN" 1>&2
  # if [ -z "$IAM_TOKEN" ] || [ "$IAM_TOKEN" = "null" ]; then
    # mylog error "Cannot retrieve IAM_TOKEN"
    # exit 1
  # fi

  ZEN_TOKEN=$(curl -kfs https://"${EP_ZEN}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)
  mylog warn "ZEN_TOKEN: $ZEN_TOKEN" 1>&2
  # CM_APIC_TOKEN=$(curl -kfs https://"${EP_API}"/v1/preauth/validateAuth -H "username: ${CP_ADMIN_UID}" -H "iam-token: ${IAM_TOKEN}" | jq -r .accessToken)
  CM_APIC_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImEzMzk1NTc3LTI4NGItNDAwNC04ZGQzLTk2YzJlNDkzODkyMiJ9.eyJqdGkiOiIxMWYxNjFiNy0wZjQzLTQxY2QtOTZhYS1jOTI0NThiODE2OTQiLCJuYW1lc3BhY2UiOiIxNTZhY2VjYy02MDIzLTQzMmUtOWRiMC1lN2Q3YjJlNDc5MGE6YTg2ODAzYjQtMWIyYS00YTMxLTk2NTMtMDE3YzExMGU1MGI1OjVjMGMwOThhLTMzMGEtNGUzOC1hYTRkLTkzZWM5OTQ3OGNmOCIsImF1ZCI6Ii9hcGkvY2xvdWQvcmVnaXN0cmF0aW9ucy9lZGIwZGNhNi02YjdlLTRmYTUtYTBkNy04NzE3YWUxMzgyODkiLCJzdWIiOiIvYXBpL3VzZXItcmVnaXN0cmllcy8xNTZhY2VjYy02MDIzLTQzMmUtOWRiMC1lN2Q3YjJlNDc5MGEvYTg2ODAzYjQtMWIyYS00YTMxLTk2NTMtMDE3YzExMGU1MGI1L3VzZXJzLzVjMGMwOThhLTMzMGEtNGUzOC1hYTRkLTkzZWM5OTQ3OGNmOCIsImlzcyI6IklCTSBBUEkgQ29ubmVjdCIsImV4cCI6MTc2ODU5NzY3OCwiaWF0IjoxNzY4NTY4ODc4LCJncmFudF90eXBlIjoicGFzc3dvcmQiLCJ1c2VyX3JlZ2lzdHJ5X3VybCI6Ii9hcGkvdXNlci1yZWdpc3RyaWVzLzE1NmFjZWNjLTYwMjMtNDMyZS05ZGIwLWU3ZDdiMmU0NzkwYS9hODY4MDNiNC0xYjJhLTRhMzEtOTY1My0wMTdjMTEwZTUwYjUiLCJyZWFsbSI6ImFkbWluL2RlZmF1bHQtaWRwLTEiLCJ1c2VybmFtZSI6ImFkbWluIiwiaWRfdG9rZW4iOiJleUpoYkdjaU9pSlNVekkxTmlJc0luUjVjQ0k2SWtwWFZDSXNJbXRwWkNJNkltTmpZbVF5TkdObUxUaGlNakl0TkRoalpTMWlZVFV6TFdRM05URTBZbU5tWWpFMFppSjkuZXlKbWFYSnpkRjl1WVcxbElqb2lRMnh2ZFdRaUxDSnNZWE4wWDI1aGJXVWlPaUpQZDI1bGNpSXNJblZ6WlhKdVlXMWxJam9pWVdSdGFXNGlMQ0psYldGcGJDSTZJbUZrYldsdVFHRndhV052Ym01bFkzUXVabklpTENKcFlYUWlPakUzTmpnMU5qZzROemg5Lml2SkdfcFpJYW9vY0JIZmtrcEVKTFkzZm9ETUg5Z1QtdFdBZ2NyY0E0dTJGUWtxZU5ueEZVUlRpUE4tdXFHU1RVWGt4THlwOEpDcWFoNlNMUk84eFlLWFV6WXo2NVVZNlI5OTJxUE1LT3FCcm8xeUFMTms1Unc3clUwS1RrMmU1MFVXeUtJRTJtZlBrbmlnS0xQZUZpRmp4RTZka2xfVHEwLWltRE5nUUI0VWhyeWlia1Mwcm1xRE4ybnUzVDd4R25BN2tpTnB3b0VIRTI3M3pabnRNODFnTWxmV0tiX0hxeTRwXzQwNlFSN0dxUGcwLWpFT0xSTHJzOWtFRWhoNEVBOEE1ZTZqMU91c0d2cFJmdnRFcFp0MVNqU3pwMjJ2elJncU5jOENpWEdCX0F3TlNSc3JQazF2UVRWZHdyeTBJTU9Oazh3bHBZWmp6dnlRSnJWWl9GUSIsInNjb3BlcyI6WyJjbG91ZDp2aWV3IiwiY2xvdWQ6bWFuYWdlIiwicHJvdmlkZXItb3JnOnZpZXciLCJwcm92aWRlci1vcmc6bWFuYWdlIiwib3JnOnZpZXciLCJvcmc6bWFuYWdlIiwicHJvZHVjdC1kcmFmdHM6dmlldyIsInByb2R1Y3QtZHJhZnRzOmVkaXQiLCJhcGktZHJhZnRzOnZpZXciLCJhcGktZHJhZnRzOmVkaXQiLCJjaGlsZDp2aWV3IiwiY2hpbGQ6Y3JlYXRlIiwiY2hpbGQ6bWFuYWdlIiwicHJvZHVjdDp2aWV3IiwicHJvZHVjdDpzdGFnZSIsInByb2R1Y3Q6bWFuYWdlIiwicHJvamVjdDp2aWV3IiwicHJvamVjdDptYW5hZ2UiLCJhcHByb3ZhbDp2aWV3IiwiYXBwcm92YWw6bWFuYWdlIiwiYXBpLWFuYWx5dGljczp2aWV3IiwiYXBpLWFuYWx5dGljczptYW5hZ2UiLCJjb25zdW1lci1vcmc6dmlldyIsImNvbnN1bWVyLW9yZzptYW5hZ2UiLCJhcHA6dmlldzphbGwiLCJhcHA6bWFuYWdlOmFsbCIsIm15OnZpZXciLCJteTptYW5hZ2UiLCJhcGk6c3RhZ2UiLCJhcGk6bWFuYWdlIiwid2ViaG9vazp2aWV3Il19.mKVKOzqe1ZcHHGTQig3t_mYr1S8OW1ygwXChykTAiBaLnWRe8dsyt58Y9TymICLP_a69ll9x50TlAQztBiRHQLIECJXSeVLbnU4isYQPFvlpHmN2Rol25JBMT8tHQ9N6m3JRCucqdSoBCkCUl432XowRKK1e4-9BR7nE-F7AFy242zEvBSlC9QUK3f-y_w9fhYfaBpcQ75ZmPtIYfPDD3vVmO46Ap64X6v6sVhjMJ1XhxwQlXep17inO1hc-mHbwNFfXsmQPIxfN6mvkYMKC8113uXrwgoDtV0QaSB87BanajkFmargyePnEmXyVwplyORmikCDZUw7NDt6Auha9GQ"
  mylog warn "CM_APIC_TOKEN: $CM_APIC_TOKEN" 1>&2
  
  # APIC_NAMESPACE=$($MY_CLUSTER_COMMAND get apiconnectcluster -A -o jsonpath='{..namespace}')
  APIC_INSTANCE=$($MY_CLUSTER_COMMAND -n "${apic_project}" get managementcluster -o=jsonpath='{.items[0].metadata.name}')
  decho $lf_tracelevel "APIC_INSTANCE: $APIC_INSTANCE"
  
  PLATFORM_API_URL=$($MY_CLUSTER_COMMAND -n "${apic_project}" get managementcluster "${APIC_INSTANCE}" -o=jsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}')
  decho $lf_tracelevel "PLATFORM_API_URL: $PLATFORM_API_URL"

  trace_out $lf_tracelevel ${FUNCNAME[0]}
 
}

################################################
# Download toolkit
# @param
function download_tools () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}
  # APIC_NAMESPACE=$($MY_CLUSTER_COMMAND get apiconnectcluster -A -o jsonpath='{..namespace}')
  local apic_instance=$($MY_CLUSTER_COMMAND -n "${apic_project}" get apiconnectcluster -o=jsonpath='{.items[0].metadata.name}')
  local lf_file2download
  local toolkit_creds_url
  
  case "${MY_PLATFORM}" in
    linux)
      lf_file2download="toolkit-linux.tgz"
      lf_unzip_command="sudo tar -xzf"
      lf_target_dir=/usr/local/bin
      ;;
    windows)
      lf_file2download="toolkit-windows.zip"
      lf_unzip_command="unzip";;
    mac)
      lf_file2download="toolkit-mac.zip"
      lf_unzip_command="unzip";;
  esac

  pushd "${MY_APIC_WORKINGDIR}resources"
  if test ! -e "${MY_APIC_WORKINGDIR}resources/${lf_file2download}";then
  	mylog info "Downloading toolkit for $MY_PLATFORM platform" 1>&2
    apic_mgmt_client_downloads_server_pod="$($MY_CLUSTER_COMMAND -n ${apic_project} get po -l app.kubernetes.io/name=client-downloads-server,app.kubernetes.io/part-of=${apic_instance} -o=jsonpath='{.items[0].metadata.name}')"
    # SB]20240207 using absolute path generate the following error on windows : error: one of src or dest must be a local file specification
    #             use pushd and popd for relative path
    $MY_CLUSTER_COMMAND cp -n "${apic_project}" "${apic_mgmt_client_downloads_server_pod}:dist/${lf_file2download}" ${lf_file2download}
    $lf_unzip_command ${lf_file2download} -C $lf_target_dir # && mv apic-slim apic
    rm $lf_file2download
  else 
  	mylog info "$MY_PLATFORM toolkit already downloaded" 1>&2
  fi
  popd

  toolkit_creds_url="${PLATFORM_API_URL}api/cloud/settings/toolkit-credentials"
  mylog info "To set the credential run the cmd apic client-creds:set <creds.json file>" 1>&2

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create Cloud Manager token (its name is access_token)
function create_cm_token(){
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  APIC_CRED=$($MY_CLUSTER_COMMAND -n "${apic_project}" get secret ${APIC_INSTANCE_NAME}-mgmt-cli-cred -o jsonpath='{.data.credential\.json}' | base64 --decode)
  APIC_APIKEY=$(curl -ks --fail -X POST "${PLATFORM_API_URL}"cloud/api-keys -H "Authorization: Bearer ${ZEN_TOKEN}" -H "Accept: application/json" -H "Content-Type: application/json" -d '{"client_type":"toolkit","description":"Tookit API key"}' | jq -r .api_key)
  decho $lf_tracelevel "APIC_APIKEY: ${APIC_APIKEY}"
  
  # The goal is to get the apikey defined in the realm provider/common-services, get the credentials for the toolkit, then use the token endpoint to get an oauth token for Cloud Manager from API Key
  TOOLKIT_CLIENT_ID=$(echo ${APIC_CRED} | jq -r .id)
  TOOLKIT_CLIENT_SECRET=$(echo ${APIC_CRED} | jq -r .secret)
  mylog info "Creating ${MY_APIC_WORKINGDIR}resources/creds.json" 1>&2
  echo "{\"username\": \"admin\", \"password\": \"$APIC_CM_ADMIN_PASSWORD\", \"realm\": \"admin/default-idp-1\", \"client_id\": \"$TOOLKIT_CLIENT_ID\", \"client_secret\": \"$TOOLKIT_CLIENT_SECRET\", \"grant_type\": \"password\"}" > "${MY_APIC_WORKINGDIR}resources/creds.json"
  
  cmToken=$(curl -ks -X POST "${PLATFORM_API_URL}api/token" \
   -H 'Content-Type: application/json' \
   -H 'Accept: application/json' \
   --data-binary "@${MY_APIC_WORKINGDIR}resources/creds.json")
  
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
  # hard coded toto
  access_token="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImEzMzk1NTc3LTI4NGItNDAwNC04ZGQzLTk2YzJlNDkzODkyMiJ9.eyJqdGkiOiIxMWYxNjFiNy0wZjQzLTQxY2QtOTZhYS1jOTI0NThiODE2OTQiLCJuYW1lc3BhY2UiOiIxNTZhY2VjYy02MDIzLTQzMmUtOWRiMC1lN2Q3YjJlNDc5MGE6YTg2ODAzYjQtMWIyYS00YTMxLTk2NTMtMDE3YzExMGU1MGI1OjVjMGMwOThhLTMzMGEtNGUzOC1hYTRkLTkzZWM5OTQ3OGNmOCIsImF1ZCI6Ii9hcGkvY2xvdWQvcmVnaXN0cmF0aW9ucy9lZGIwZGNhNi02YjdlLTRmYTUtYTBkNy04NzE3YWUxMzgyODkiLCJzdWIiOiIvYXBpL3VzZXItcmVnaXN0cmllcy8xNTZhY2VjYy02MDIzLTQzMmUtOWRiMC1lN2Q3YjJlNDc5MGEvYTg2ODAzYjQtMWIyYS00YTMxLTk2NTMtMDE3YzExMGU1MGI1L3VzZXJzLzVjMGMwOThhLTMzMGEtNGUzOC1hYTRkLTkzZWM5OTQ3OGNmOCIsImlzcyI6IklCTSBBUEkgQ29ubmVjdCIsImV4cCI6MTc2ODU5NzY3OCwiaWF0IjoxNzY4NTY4ODc4LCJncmFudF90eXBlIjoicGFzc3dvcmQiLCJ1c2VyX3JlZ2lzdHJ5X3VybCI6Ii9hcGkvdXNlci1yZWdpc3RyaWVzLzE1NmFjZWNjLTYwMjMtNDMyZS05ZGIwLWU3ZDdiMmU0NzkwYS9hODY4MDNiNC0xYjJhLTRhMzEtOTY1My0wMTdjMTEwZTUwYjUiLCJyZWFsbSI6ImFkbWluL2RlZmF1bHQtaWRwLTEiLCJ1c2VybmFtZSI6ImFkbWluIiwiaWRfdG9rZW4iOiJleUpoYkdjaU9pSlNVekkxTmlJc0luUjVjQ0k2SWtwWFZDSXNJbXRwWkNJNkltTmpZbVF5TkdObUxUaGlNakl0TkRoalpTMWlZVFV6TFdRM05URTBZbU5tWWpFMFppSjkuZXlKbWFYSnpkRjl1WVcxbElqb2lRMnh2ZFdRaUxDSnNZWE4wWDI1aGJXVWlPaUpQZDI1bGNpSXNJblZ6WlhKdVlXMWxJam9pWVdSdGFXNGlMQ0psYldGcGJDSTZJbUZrYldsdVFHRndhV052Ym01bFkzUXVabklpTENKcFlYUWlPakUzTmpnMU5qZzROemg5Lml2SkdfcFpJYW9vY0JIZmtrcEVKTFkzZm9ETUg5Z1QtdFdBZ2NyY0E0dTJGUWtxZU5ueEZVUlRpUE4tdXFHU1RVWGt4THlwOEpDcWFoNlNMUk84eFlLWFV6WXo2NVVZNlI5OTJxUE1LT3FCcm8xeUFMTms1Unc3clUwS1RrMmU1MFVXeUtJRTJtZlBrbmlnS0xQZUZpRmp4RTZka2xfVHEwLWltRE5nUUI0VWhyeWlia1Mwcm1xRE4ybnUzVDd4R25BN2tpTnB3b0VIRTI3M3pabnRNODFnTWxmV0tiX0hxeTRwXzQwNlFSN0dxUGcwLWpFT0xSTHJzOWtFRWhoNEVBOEE1ZTZqMU91c0d2cFJmdnRFcFp0MVNqU3pwMjJ2elJncU5jOENpWEdCX0F3TlNSc3JQazF2UVRWZHdyeTBJTU9Oazh3bHBZWmp6dnlRSnJWWl9GUSIsInNjb3BlcyI6WyJjbG91ZDp2aWV3IiwiY2xvdWQ6bWFuYWdlIiwicHJvdmlkZXItb3JnOnZpZXciLCJwcm92aWRlci1vcmc6bWFuYWdlIiwib3JnOnZpZXciLCJvcmc6bWFuYWdlIiwicHJvZHVjdC1kcmFmdHM6dmlldyIsInByb2R1Y3QtZHJhZnRzOmVkaXQiLCJhcGktZHJhZnRzOnZpZXciLCJhcGktZHJhZnRzOmVkaXQiLCJjaGlsZDp2aWV3IiwiY2hpbGQ6Y3JlYXRlIiwiY2hpbGQ6bWFuYWdlIiwicHJvZHVjdDp2aWV3IiwicHJvZHVjdDpzdGFnZSIsInByb2R1Y3Q6bWFuYWdlIiwicHJvamVjdDp2aWV3IiwicHJvamVjdDptYW5hZ2UiLCJhcHByb3ZhbDp2aWV3IiwiYXBwcm92YWw6bWFuYWdlIiwiYXBpLWFuYWx5dGljczp2aWV3IiwiYXBpLWFuYWx5dGljczptYW5hZ2UiLCJjb25zdW1lci1vcmc6dmlldyIsImNvbnN1bWVyLW9yZzptYW5hZ2UiLCJhcHA6dmlldzphbGwiLCJhcHA6bWFuYWdlOmFsbCIsIm15OnZpZXciLCJteTptYW5hZ2UiLCJhcGk6c3RhZ2UiLCJhcGk6bWFuYWdlIiwid2ViaG9vazp2aWV3Il19.mKVKOzqe1ZcHHGTQig3t_mYr1S8OW1ygwXChykTAiBaLnWRe8dsyt58Y9TymICLP_a69ll9x50TlAQztBiRHQLIECJXSeVLbnU4isYQPFvlpHmN2Rol25JBMT8tHQ9N6m3JRCucqdSoBCkCUl432XowRKK1e4-9BR7nE-F7AFy242zEvBSlC9QUK3f-y_w9fhYfaBpcQ75ZmPtIYfPDD3vVmO46Ap64X6v6sVhjMJ1XhxwQlXep17inO1hc-mHbwNFfXsmQPIxfN6mvkYMKC8113uXrwgoDtV0QaSB87BanajkFmargyePnEmXyVwplyORmikCDZUw7NDt6Auha9GQ"
  decho $lf_tracelevel "access_token: ${access_token}"

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create API Manager token for the org 
# todo : think about params
function create_am_token(){
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # get token for the API Manager for 
  amToken=$(curl -sk --fail -X POST "${PLATFORM_API_URL}api/token" \
   -H 'Content-Type: application/json' \
   -H 'Accept: application/json' \
   --data-binary "{\"username\":\"$APIC_ORG1_USERNAME\",\"password\":\"$APIC_ORG1_PASSWORD\",\"realm\":\"provider/default-idp-2\",\"client_id\":\"$TOOLKIT_CLIENT_ID\",\"client_secret\":\"$TOOLKIT_CLIENT_SECRET\",\"grant_type\":\"password\"}" |  jq .access_token | sed -e s/\"//g  )
  
  decho $lf_tracelevel "amToken: $amToken"
  # TODO Not sure the use of $? is good, this is the result of the sed command
  retVal=$?
  if [ $retVal -ne 0 ] || [ -z "$amToken" ] || [ "$amToken" = "null" ]; then
    mylog error "Error with login -> $retVal" 1>&2
    exit 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# run all
function apic_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  SECONDS=0
  local lf_starting_date=$(date);
  
  # TODO Cannot work the variable for mail ns is not ready at that time, quick fix below
  VAR_MAIL_NAMESPACE='mail'
  
  # Get ClusterIP for the mail server if MailHog
  # TODO check error, if not there, ...
  export MY_MAIL_SERVER_HOST_IP=$($MY_CLUSTER_COMMAND -n ${VAR_MAIL_NAMESPACE} get svc/mail-service -o jsonpath='{.spec.clusterIP}')
  decho $lf_tracelevel "To configure the mail server the clusterIP is ${MY_MAIL_SERVER_HOST_IP}"
  
  # Will create both directories needed later
  adapt_file ${MY_APIC_SIMPLE_DEMODIR}properties/ ${MY_APIC_WORKINGDIR}properties/ apic.properties
  adapt_file ${MY_APIC_SIMPLE_DEMODIR}resources/ ${MY_APIC_WORKINGDIR}resources/ web-mgmt.cfg
  
  read_config_file "${MY_APIC_WORKINGDIR}properties/apic.properties"
  
  # Init APIC variables
  init_apic_variables
  
  # Download toolkit/designer+loopback+toolkit
  # download_tools toto
  
  # Create Cloud Manager token
  create_cm_token
  
  TOOLKIT_CREDS_URL="${PLATFORM_API_URL}api/cloud/settings/toolkit-credentials"
  
  # always download the credential.json
  # if test ! -e "~/.apiconnect/config-apim";then
  mylog info "Downloading apic config json file" 1>&2
  curl -ks "${TOOLKIT_CREDS_URL}" -H "Authorization: Bearer ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -o "${MY_APIC_WORKINGDIR}resources/fullcreds.json"
  
  # Get ClusterIP of the mail service
  create_mail_server "${APIC_SMTP_SERVER}" "${APIC_SMTP_SERVER_PORT}"
  
  # TODO Add idempotence
  create_topology $integration_url
  
  create_org "${APIC_PROVIDER_ORG}" "${APIC_ORG1_USERNAME}" "${APIC_ORG1_PASSWORD}" "${APIC_ORG1_USER_EMAIL}"
  
  # Create API Manager token
  create_am_token
  
  create_catalog "${APIC_PROVIDER_ORG}"
  
  create_apic_resources $access_token $amToken $APIC_PROVIDER_ORG

  # Push API into draft
  apic_provider_org_lower=$(echo "$APIC_PROVIDER_ORG" | awk '{print tolower($0)}')

  load_apis $PLATFORM_API_URL $apic_provider_org_lower $amToken


  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
    
  mylog info "==== Customisation of apic (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}
################################################
# initialisation
function apic_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# main function
# Main logic
function main() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    return 1
  fi

  # Main script logic
  local lf_calls=""  # Initialize calls variable
  local lf_key

  while [[ $# -gt 0 ]]; do
    lf_key="$1"
    case $lf_key in
      --all)
        shift
        ;;
      --call)
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          lf_calls+="$1 "  # Accumulate all arguments after --call
          shift
        done
        ;;
      *)
        mylog error "Invalid option '$1'. Use --all or --call function_name parameters, function_name parameters, ...."
        trace_out $lf_tracelevel ${FUNCNAME[0]}
        return 1
        ;;
      esac
  done
  #lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces
  lf_calls=$(echo "$lf_calls" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')
  
  # Call processing function if --call was used
  case $lf_key in
    --all) apic_run_all "$@";;
    --call) if [[ -n $lf_calls ]]; then
              process_calls "$lf_calls"
            else
              mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
              trace_out $lf_tracelevel ${FUNCNAME[0]}
              return 1
            fi;;
    esac

  trace_out $lf_tracelevel ${FUNCNAME[0]}
  exit 0
}

################################################
# Start of the script main entry
################################################
# other example: ./apic.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./apic.config.sh --all
################################################

# SB] getting the path of this script independently from using it directly or calling it from another script
# sc_component_script_dir="$( cd "$( dirname "$0" )" && pwd )/": this statement returns the calling script path

# Voir aussi comment on peut utiliser l'option suivante (trouvée dans un sript de Dale Lane)
# allow this script to be run from other locations, despite the
# relative file paths used in it
#OPTION# if [[ $BASH_SOURCE = */* ]]; then
#OPTION#   cd -- "${BASH_SOURCE%/*}/" || exit
#OPTION# fi

# the following script returns the absolute path of this script independently from using it directly or calling it from another script
sc_component_script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"
export MY_APIC_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/apic.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load properties files
. "${sc_provision_constant_properties_file}"

# load properties files
. "${sc_provision_variable_properties_file}"

# Load mq variables
. "${sc_component_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

apic_init

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi