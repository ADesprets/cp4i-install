#!/bin/bash
sc_cases_list="ibm-integration-platform-navigator ibm-integration-asset-repository ibm-apiconnect ibm-appconnect ibm-mq ibm-eventstreams ibm-eventendpointmanagement ibm-datapower-operator ibm-aspera-hsts-operator ibm-cp-common-services"
for sc_case in $sc_cases_list
do 
  sc_version=$($MY_CLUSTER_COMMAND ibm-pak list -o json | jq  --arg case "$sc_case" '.[] | select (.name == $case ) | .latestVersion' 2> /dev/null) 
  echo "latestversion: $sc_case=$sc_version"
done