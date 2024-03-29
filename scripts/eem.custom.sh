################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

#assumptions on the name od the file
read_config_file "${scriptdir}cp4i.properties"

read_config_file "${scriptdir}scripts/eem.custom.properties"

# Creation de Topics
SECONDS=0

## --------------

mylog info "getting eem host using: oc get route -n $MY_EEM_PROJECT ${MY_EEM_INSTANCE_NAME}-ibm-eem-admin -ojsonpath='https://{.spec.host}'"
export eem_api_host=$(oc get route -n $MY_EEM_PROJECT ${MY_EEM_INSTANCE_NAME}-ibm-eem-admin -ojsonpath='https://{.spec.host}')
export es_boostrap_svc=${MY_ES_INSTANCE_NAME}-kafka-bootstrap.${MY_ES_PROJECT}.svc

mylog info "es bootstrap used: ${es_boostrap_svc}"


export es_certificate=$(oc get secret $MY_ES_INSTANCE_NAME-cluster-ca-cert -o jsonpath='{.data.ca\.crt}'| base64 -d | awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}')
export es_user_pwd=$(oc get secret es-all-access -n $MY_ES_PROJECT -ojsonpath='{.data.password}' | base64 -d)


#cd ${scriptdir}working

#oc extract secret/${MY_ES_INSTANCE_NAME}-cluster-ca-cert -n ${ES_NAMESPACE} --keys=ca.crt --confirm
#es_certificate=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ca.crt)

# export es_certificate=$(oc get secret $MY_ES_INSTANCE_NAME-cluster-ca-cert -o jsonpath='{.data.ca\.crt}'| base64 -d)
#echo $ES_CERTIFICATE
#printf "%s\\n" "$ES_CERTIFICATE"

mylog info "ES credentials retrieved"

if [ ! -d ${EEM_GEN_CUSTOMDIR}config ]; then
    mkdir -p ${EEM_GEN_CUSTOMDIR}config
fi
if [ ! -d ${EEM_GEN_CUSTOMDIR}script ]; then
    mkdir -p ${EEM_GEN_CUSTOMDIR}script
fi
generate_files $EEM_TMPL_CUSTOMDIR $EEM_GEN_CUSTOMDIR false

envsubst < "${EEM_GEN_CUSTOMDIR}config/eem-es-cluster.json" > ${EEM_GEN_CUSTOMDIR}config/gen-eem-es-cluster.json

mylog info "registering cluster "
#@${EEM_GEN_CUSTOMDIR}config/eem-es-cluster.json
 eem_response=$(curl -X POST -sk \
     --dump-header eem-api-header \
     -H 'Accept: application/json' \
     -H 'Content-Type: application/json' \
     -H "Authorization: Bearer ${eem_at}" \
     --data "@${EEM_GEN_CUSTOMDIR}config/gen-eem-es-cluster.json" \
     --output ${EEM_GEN_CUSTOMDIR}script/eem-resp-new-cluster.json \
     --write-out '%{response_code}' \
     $eem_api_host/eem/clusters)

mylog info "response curl: ${eem_response}"
if [ $eem_response -eq 200 ]; then
  clusterId=$(jq .id ${EEM_GEN_CUSTOMDIR}script/eem-resp-new-cluster.json)
  mylog info "clusterId: $clusterId"
fi 

if [ $eem_response -eq 409 ]; then
   eem_response=$(curl -sk \
     --dump-header eem-api-header \
     -H 'Accept: application/json' \
     -H 'Content-Type: application/json' \
     -H "Authorization: Bearer ${eem_at}" \
     --output ${EEM_GEN_CUSTOMDIR}script/eem-resp-kafka-clusters.json \
     --write-out '%{response_code}' \
     $eem_api_host/eem/clusters)
    clusterId=$(jq '.[] | select(.["name"] | contains ("'$MY_ES_INSTANCE_NAME'")) | .id' ${EEM_GEN_CUSTOMDIR}script/eem-resp-kafka-clusters.json)
    mylog info "clusterId: $clusterId"
fi

mylog info "response curl: ${eem_response}"

if [ $eem_response -ne 200 ]; then
  mylog error "cluster registration failed"
  exit 1
fi 

#clusterId=$(jq .id ${EEM_GEN_CUSTOMDIR}script/eem-response-data.json)
topics=("CANCELLATIONS" "CUSTOMERS.NEW" "DOOR.BADGEIN" "ORDERS.NEW")

for topic in "${topics[@]}"
do
    eem_response=$(curl -X POST -s -k \
          --dump-header eem-api-header \
          -H 'Accept: application/json' \
          -H 'Content-Type: application/json' \
          -H "Authorization: Bearer ${eem_at}" \
          --data "$(cat ${EEM_GEN_CUSTOMDIR}config/10-eem-eventsource-$topic.json | jq ".clusterId |= ${clusterId}")" \
          --output ${EEM_GEN_CUSTOMDIR}script/eem-response-data.json \
          --write-out '%{response_code}' \
          $eem_api_host/eem/eventsources)

     if [ $eem_response -eq 200 ]; then
       mv ${EEM_GEN_CUSTOMDIR}script/eem-response-data.json ${EEM_GEN_CUSTOMDIR}script/eem-response-data-$topic.json
       mylog info "topic $topic added in EEM"
      fi
     if [ $eem_response -eq 409 ]; then
       mylog info "topic $topic already configured in EEM"
      fi
     #eventSourceId=$(jq .id ${EEM_GEN_CUSTOMDIR}script/eem-response-data-$topic.json)
done

#publication of the topic to the event gateway
topicOptions=("DOOR.BADGEIN" "CUSTOMERS.NEW" "ORDERS.NEW")

for topicoption in "${topicOptions[@]}"
do
    eventSourceId=$(jq .id ${EEM_GEN_CUSTOMDIR}script/eem-response-data-$topicoption.json)
    #mylog info "gw name ${MY_EGW_INSTANCE_NAME}"
    option_data=$(cat ${EEM_GEN_CUSTOMDIR}config/10-eem-option-$topicoption.json | jq '.eventSourceId |= '${eventSourceId}'' | jq '.gatewayGroups[] |= "'${MY_EGW_INSTANCE_NAME}'"')
    #mylog info "topic option $topicoption : ${option_data}"
    eem_response=$(curl -X POST -s -k \
          --dump-header eem-api-header \
          -H 'Accept: application/json' \
          -H 'Content-Type: application/json' \
          -H "Authorization: Bearer $eem_at" \
          --data "${option_data}" \
          --output ${EEM_GEN_CUSTOMDIR}script/eem-rsp-option.json \
          --write-out '%{response_code}' \
          $eem_api_host/eem/options)

    if [ $eem_response -eq 200 ]; then
       mv ${EEM_GEN_CUSTOMDIR}script/eem-rsp-option.json ${EEM_GEN_CUSTOMDIR}script/eem-rsp-option-$topicoption.json
       mylog info "option for topic $topicoption configured in EEM"
      fi
    if [ $eem_response -eq 409 ]; then
       mylog info "option for topic $topic already configured in EEM"
    fi  
done




mylog info "EEM configured."

## --------------

duration=$SECONDS
mylog info "Creation of the Kafka Topics took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2


