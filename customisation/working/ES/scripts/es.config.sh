################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=/home/saad/Mywork/Git/20240713-cp4i-install/

# load helper functions
. ""lib.sh

mylog info "Customise Event Streams (es.config.sh)"

#assumptions on the name of the file
read_config_file "cp4i.properties"

read_config_file "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/es.properties"

# Creation of the Topics used for taxi demo
SECONDS=0

: <<'END_COMMENT'

topic_names=("connect-configs" "connect-offsets" "connect-status" "toolbox.stater" "demo-flight-takeoffs" "demo-weather-armonk" "demo-weather-hursley" "demo-weather-northharbour" "demo-weather-paris" "demo-weather-southbank" "demo-stock-apple" "demo-stock-google" "demo-stock-ibm" "demo-stock-microsoft" "demo-stock-salesforce" "orders" "cancellations" "doors" "stock" "customers" "sensors")
topic_spec_names=("connect-configs" "connect-offsets" "connect-status" "TOOLBOX.STATER" "FLIGHT.TAKEOFFS" "WEATHER.ARMONK" "WEATHER.HURSLEY" "WEATHER.NORTHHARBOUR" "WEATHER.PARIS" "WEATHER.SOUTHBANK" "STOCK.APPLE" "STOCK.GOOGLE" "STOCK.IBM" "STOCK.MICROSOFT" "STOCK.SALESFORCE" "LH.ORDERS" "LH.CANCELLATIONS" "LH.DOORS" "LH.STOCK" "LH.CUSTOMERS" "LH.SENSORS")
topic_partitions=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 3 3 1 2 3 2)
topic_replicas=(3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 1 1 3 1)
for index in ${!topic_names[@]}
do
    mylog info "topic name: ${topic_names[]}, topic spec name: ${topic_spec_names[]}, partitions: ${topic_partitions[]}, replicas: ${topic_replicas[]}, es_instance: "
    # need to make those variables visible to the envsubst command used in lib.sh
    export es_topic_name=${topic_names[]}
    export es_spec_topic_name=${topic_spec_names[]}
    export es_spec_topic_partition=${topic_partitions[]}
    export es_spec_topic_replica=${topic_replicas[]}

    # CRD described at https://ibm.github.io/event-automation/es/reference/api-reference-es/
#    check_create_oc_yaml "KafkaTopic" "" "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/topic.yaml" 
    # check_resource_availability "KafkaTopic" "" 
    # wait_for_state KafkaTopic "" "Ready" '.status.phase' 
done

# Creation of a Kafka user
check_create_oc_yaml "KafkaUser" "" "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/es-admin-user.yaml" 
check_create_oc_yaml "KafkaUser" "" "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/es-all-access-user.yaml" 
check_create_oc_yaml "KafkaUser" "" "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/kafka-connect-credentials.yaml" 
check_create_oc_yaml "KafkaUser" "" "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/kafka-user1.yaml" 

# TODO Wanted to separate things for best practice, but not done yet
# https://github.com/IBM/kafka-connect-loosehangerjeans-source/tree/main
# Creation of the namespace for the kafka producers to separate them from product namespace
# create_namespace 
# Creation of the namespace for the event streams cluster destination in the MM2 demo
# create_namespace 

END_COMMENT

# Create KafkaConnect and KafkaConnector in  project
mylog info "Create Kafka Connect for datagen"
check_create_oc_yaml "KafkaConnect" "datagen-host" "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/KConnect_datagen.yaml" 

# mylog info "Create Kafka Connector for datagen"
check_create_oc_yaml "KafkaConnector" "datagen" "/home/saad/Mywork/Git/20240713-cp4i-install/customisation/working/ES/config/KConnector_datagen.yaml" 

duration=
mylog info "Configuration for EventStreams took  seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start:  - end: " 1>&2
mylog info "$(( / 60)) minutes and $(( % 60)) seconds elapsed."  1>&2