#!/bin/bash

# name: 
# requirement :
#         - jq ( wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 )
#         - curl
#
# Comment :
# - update apic.properties
# - For local test create file : user_password.txt with password of your apic connection

echo "Start: `date`"
starting=$(date);
SECONDS=0

if ! command -v jq &> /dev/null
then
    echo "jq could not be found in PATH"
    echo "retrieve it and add in it in the PATH"
    echo "example for linux :  wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
    exit
fi

pwd
. $PWD/apic.properties

echo --------
echo '-- Set local properties'
echo --------
# Platform REST API endpoint for admin and provider APIs
#export EP_API=api.iks-553468-103ddb1cc6249867b4ed037d4a50c9fb-0000.eu-de.containers.appdomain.cloud
# API Manager URL
EP_API=$MGMT_API_EP.${STACK_HOST}
# gwv6-gateway-manager
EP_GWD=$GWY_ADMIN_EP.${STACK_HOST}
# gwv6-gateway
EP_GW=$GWY_EP.${STACK_HOST}
# analytics-ai-endpoint
EP_AI=$A7S_INGESTION_EP.${STACK_HOST}
# analytics-ac-endpoint
EP_AC=$A7S_CLIENT_EP.${STACK_HOST}
# portal-portal-director
EP_PADMIN=$PORTAL_ADMIN_EP.${STACK_HOST}
# portal-portal-web
EP_PORTAL=$PORTAL_UI_EP.${STACK_HOST}

# admin ORG
ADMIN_ORG_NAME='admin'
API_MANAGER_LUR='api-manager-lur'
echo --------


echo --------
echo Get Cloud Manager access token
echo --------

echo "EP_API: $EP_API"

cmToken=$(curl -sk  "https://$EP_API/api/token" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 --data-binary "{\"username\":\"admin\",\"password\":\"$apic_admin_password\",\"realm\":\"admin/default-idp-1\",\"client_id\":\"caa87d9a-8cd7-4686-8b6e-ee2cdc5ee267\",\"client_secret\":\"3ecff363-7eb3-44be-9e07-6d4386c48b0b\",\"grant_type\":\"password\"}" |  jq .access_token | sed -e s/\"//g  )

retVal=$?
if [ $retVal -ne 0 ] || [ -z "$cmToken" ] || [ "$cmToken" = "null" ]; then
    	echo "Error with login -> $retVal"
	exit 1
fi

echo --------
echo "Cloud Manager access token: $cmToken"
echo --------

echo --------
echo "Get integration Endpoint"
echo --------

integration_url=$(curl -sk  "https://$EP_API/api/cloud/integrations/gateway-service/datapower-api-gateway" -H "Authorization: Bearer $cmToken" -H 'Accept-Encoding: gzip, deflate, br' -H 'Accept-Language: en-GB,en-US;q=0.9,en;q=0.8'  -H 'Accept: application/json'  -H 'Connection: keep-alive' --compressed | jq .url | sed -e s/\"//g)

retVal=$?

echo --------
echo "integration_url: $integration_url"
echo --------

if [ $retVal -ne 0 ] || [ -z "$integration_url" ] || [ "$integration_url" = "null" ]; then
    	echo "Error with integration_url -> $retVal"
	exit 1
fi

orgUrl=$(curl -sk "https://$EP_API/api/cloud/orgs/admin" \
 -H "Authorization: Bearer $cmToken" \
 -H 'Accept: application/json' \
 --compressed | jq .results[0].url | sed -e s/\"//g);

orgList=$(curl -sk "https://$EP_API/api/cloud/orgs" \
 -H "Authorization: Bearer $cmToken" \
 -H 'Accept: application/json' \
 --compressed)

#echo "orgList: $orgList"

echo ---------
echo "Delete Org $PROVIDER_ORG"
echo ---------

newOrg=$(echo "$PROVIDER_ORG" | awk '{print tolower($0)}')

orgCLEAR=$(curl -sk --request DELETE "https://$EP_API/api/orgs/$newOrg" -H "Accept: application/json" -H "authorization: Bearer $cmToken");

echo $orgCLEAR;

echo ---------
echo "Delete User $ORG_USERNAME"
echo ---------

lowercaseuserOrg=$(echo "$ORG_USERNAME" | awk '{print tolower($0)}')

userCLEAR=$(curl -sk --request DELETE "https://$EP_API/api/user-registries/admin/api-manager-lur/users/$lowercaseuserOrg" -H "Accept: application/json" -H "authorization: Bearer $cmToken");

echo $userCLEAR;

echo ---------
echo "Unset Analytic Service for Gateway"
echo ---------

analytGwy=$(curl -sk -X PATCH \
   "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/gateway-services/apigateway-service" \
 -H 'Accept: application/json' \
 -H "Authorization: Bearer $cmToken"\
 -H 'Cache-Control: no-cache' \
 -H 'Content-Type: application/json' \
 --data-binary "{\"analytics_service_url\":	null }");

echo "$analytGwy"

echo ---------
echo "Delete Analytic Service"
echo ---------

analytClear=$(curl -sk --request DELETE "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/analytics-services/analytics-service" -H "Accept: application/json" -H "authorization: Bearer $cmToken");

echo $analytClear;

echo ---------
echo "Delete Portal Service"
echo ---------

portalClear=$(curl -sk --request DELETE "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/portal-services/portal-service" -H "Accept: application/json" -H "authorization: Bearer $cmToken" );

echo $portalClear;

echo ---------
echo "Unset gateway Service as default for catalogs"
echo ---------

unsetGWdefault=$(curl -sk --request PUT "https://$EP_API/api/cloud/settings" \
  -H "Authorization: Bearer $cmToken" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'Connection: keep-alive' \
  --data "{\"gateway_service_default_urls\": [] }" );

echo $unsetGWdefault

echo ---------
echo Delete gateway Service
echo ---------

gwyClear=$(curl -sk --request DELETE "https://$EP_API/api/orgs/admin/availability-zones/availability-zone-default/gateway-services/apigateway-service" -H "Accept: application/json" -H "authorization: Bearer $cmToken");

echo $gwyClear;

echo ---------
echo "unset MailServer"
echo ---------

unsetMailServer=$(curl -sk "https://$EP_API/api/cloud/settings"\
 -X PUT\
 -H "Accept: application/json"\
 -H "authorization: Bearer $cmToken" \
 -H "content-type: application/json"\
 --data "{\"mail_server_url\":null}");

echo "unsetMailServer: $unsetMailServer";

echo ---------
echo "Delete mail Server"
echo ---------

smtpClear=$(curl -sk --request DELETE "https://$EP_API/api/orgs/admin/mail-servers?confirm=admin" -H "Accept: application/json" -H "authorization: Bearer $cmToken");
echo $smtpClear;

duration=$SECONDS
ending=$(date);
echo "------------------------------------"
echo "start: $starting - end: $ending"
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
echo "------------------------------------"
