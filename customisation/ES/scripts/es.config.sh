################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
configdir="${scriptdir}../config/"
mainscriptdir="${scriptdir}../../../"

# load helper functions
. "${mainscriptdir}"lib.sh

read_config_file "${mainscriptdir}cp4i.properties"
read_config_file "${configdir}es.properties"

# Creation de Topics
SECONDS=0

topic_names=("demo-flight-takeoffs" "demo-weather-armonk" "demo-weather-hursley" "demo-weather-northharbour" "demo-weather-paris" "demo-weather-southbank" "demo-stock-apple" "demo-stock-google" "demo-stock-ibm" "demo-stock-microsoft" "demo-stock-salesforce")
topic_spec_names=("FLIGHT.TAKEOFFS" "WEATHER.ARMONK" "WEATHER.HURSLEY" "WEATHER.NORTHHARBOUR" "WEATHER.PARIS" "WEATHER.SOUTHBANK" "STOCK.APPLE" "STOCK.GOOGLE" "STOCK.IBM" "STOCK.MICROSOFT" "STOCK.SALESFORCE")

for index in ${!topic_names[@]}
do
    # need to make those variables visible to the envsubst command used in lib.sh
    export es_topic_name=${topic_names[$index]}
    export es_spec_topic_name=${topic_spec_names[$index]}

    check_create_oc_yaml "KafkaTopic" "${es_topic_name}" "${configdir}generic-topic.yaml" $es_project
    # check_resource_availability "KafkaTopic" "${es_topic_name}" $es_project
    # wait_for_oc_state KafkaTopic "${es_topic_name}" "Ready" '.status.phase' $es_project
done

# Create Kafka user
check_create_oc_yaml "KafkaUser" "${es_topic_name}" "${configdir}user.yaml" $es_project

duration=$SECONDS
mylog info "Creation of the Kafka Topics took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2