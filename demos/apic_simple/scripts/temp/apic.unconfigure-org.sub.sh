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

pwd
. ../resources/apic.properties

# Check if connexion to cluster is ok
gi=$(kubectl get nodes)
if [ $? -ne 0 ]; then
  exit 1
fi

echo --------
echo '-- Set local properties'
echo --------
# Platform REST API endpoint for admin and provider APIs
# API Manager URL
EP_API=$MGMT_API_EP.$STACK_HOST
# portal-portal-web
EP_PORTAL=$PORTAL_UI_EP.$STACK_HOST

echo $EP_API

amToken=$(curl -sk  "https://$EP_API/api/token" \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json' \
 --data-binary "{\"username\":\"$ORG_USERNAME\",\"password\":\"$ORG_PASSWORD\",\"realm\":\"provider/default-idp-2\",\"client_id\":\"caa87d9a-8cd7-4686-8b6e-ee2cdc5ee267\",\"client_secret\":\"3ecff363-7eb3-44be-9e07-6d4386c48b0b\",\"grant_type\":\"password\"}" | jq .access_token | sed -e s/\"//g  )

retVal=$?
if [ $retVal -ne 0 ] || [ -z "$amToken" ] || [ "$amToken" = "null" ]; then
        echo "Error with login -> $retVal"
        exit 1
fi

echo --------
echo "Manager access token: $amToken"
echo --------

echo --------
echo "Delete catalogs"
echo --------

catalog_name=("prod" "uat" "qa")

for index in ${!catalog_name[@]}
    do
        echo "Delete Catalog: "${catalog_name[$index]}" in org $PROVIDER_ORG";

        res=$(curl -sk -X DELETE "https://$EP_API/api/catalogs/$PROVIDER_ORG/${catalog_name[$index]}" \
        -H "Authorization: Bearer $amToken" \
        -H 'Accept: application/json' \
        -H 'Connection: keep-alive' \
        --compressed | jq .url | sed -e s/\"//g);

echo "Delete Catalog  result: $res"

#        res=$(curl -sk -X PUT "$catURL/settings" \
#         -H "Authorization: Bearer $amToken" \
#         -H 'accept: application/json' \
#         -H 'content-type: application/json' \
#         -H 'Connection: keep-alive' \
#         --data-binary "{\"portal\": {\"endpoint\": \"https://$EP_PORTAL/$PROVIDER_ORG/${catalog_name[$index]}\",\"portal_service_url\": \"$serviceCatURL\", \"type\": \"drupal\"},\"application_lifecycle\": {} }" | jq .portal.endpoint);

#        echo "Portal endpoint for: "${catalog_summary[$index]}": $res"

    done

duration=$SECONDS
ending=$(date);
echo "------------------------------------"
echo "start: $starting - end: $ending"
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
echo "------------------------------------"
