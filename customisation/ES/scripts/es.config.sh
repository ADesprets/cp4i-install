################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

#assumptions on the name of the file
read_config_file "${scriptdir}cp4i.properties"

read_config_file "${ES_GEN_CUSTOMDIR}scripts/es.properties"

# Creation of the Topics used for taxi demo
SECONDS=0

topic_names=("connect-configs" "connect-offsets" "connect-status" "toolbox.stater" "demo-flight-takeoffs" "demo-weather-armonk" "demo-weather-hursley" "demo-weather-northharbour" "demo-weather-paris" "demo-weather-southbank" "demo-stock-apple" "demo-stock-google" "demo-stock-ibm" "demo-stock-microsoft" "demo-stock-salesforce" "orders" "cancellations" "doors" "stock" "customers" "sensors")
topic_spec_names=("connect-configs" "connect-offsets" "connect-status" "TOOLBOX.STATER" "FLIGHT.TAKEOFFS" "WEATHER.ARMONK" "WEATHER.HURSLEY" "WEATHER.NORTHHARBOUR" "WEATHER.PARIS" "WEATHER.SOUTHBANK" "STOCK.APPLE" "STOCK.GOOGLE" "STOCK.IBM" "STOCK.MICROSOFT" "STOCK.SALESFORCE" "LH.ORDERS" "LH.CANCELLATIONS" "LH.DOORS" "LH.STOCK" "LH.CUSTOMERS" "LH.SENSORS")
topic_partitions=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 3 3 1 2 3 2)
topic_replicas=(3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 1 1 3 1)
for index in ${!topic_names[@]}
do
    mylog info "topic name: ${topic_names[$index]}, topic spec name: ${topic_spec_names[$index]}, partitions: ${topic_partitions[$index]}, replicas: ${topic_replicas[$index]}, es_instance: ${es_instance}"
    # need to make those variables visible to the envsubst command used in lib.sh
    export es_topic_name=${topic_names[$index]}
    export es_spec_topic_name=${topic_spec_names[$index]}
    export es_spec_topic_partition=${topic_partitions[$index]}
    export es_spec_topic_replica=${topic_replicas[$index]}

    # CRD described at https://ibm.github.io/event-automation/es/reference/api-reference-es/
#    check_create_oc_yaml "KafkaTopic" "${es_topic_name}" "${ES_GEN_CUSTOMDIR}config/topic.yaml" $es_project
    # check_resource_availability "KafkaTopic" "${es_topic_name}" $es_project
    # wait_for_state KafkaTopic "${es_topic_name}" "Ready" '.status.phase' $es_project
done

# Creation of a Kafka user
check_create_oc_yaml "KafkaUser" "${es_topic_name}" "${ES_GEN_CUSTOMDIR}config/es-admin-user.yaml" $es_project
check_create_oc_yaml "KafkaUser" "${es_topic_name}" "${ES_GEN_CUSTOMDIR}config/es-all-access-user.yaml" $es_project
check_create_oc_yaml "KafkaUser" "${es_topic_name}" "${ES_GEN_CUSTOMDIR}config/kafka-connect-credentials.yaml" $es_project
check_create_oc_yaml "KafkaUser" "${es_topic_name}" "${ES_GEN_CUSTOMDIR}config/kafka-user1.yaml" $es_project

# TODO Wanted to separate things for best practice, but not done yet
# https://github.com/IBM/kafka-connect-loosehangerjeans-source/tree/main
# Creation of the namespace for the kafka producers to separate them from product namespace
# create_namespace $ES_APPS_PROJECT
# Creation of the namespace for the event streams cluster destination in the MM2 demo
# create_namespace $ES_DESTINATION

# Create KafkaConnect and KafkaConnector in $ES_APPS_PROJECT project
mylog info "Create Kafka Connect for datagen"
# check_create_oc_yaml "KafkaConnect" "datagen-host" "${ES_GEN_CUSTOMDIR}config/KConnect_datagen.yaml" $es_project

# mylog info "Create Kafka Connector for datagen"
check_create_oc_yaml "KafkaConnector" "datagen" "${ES_GEN_CUSTOMDIR}config/KConnector_datagen.yaml" $es_project

duration=$SECONDS
mylog info "Configuration for EventStreams took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2