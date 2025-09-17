################################################
# Create IBM Event streams instance
function create_es() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_es

  # ibm-eventstreams
  if $MY_ES; then

    # Creating Event Streams instance
    create_operand_instance "EventStreams" "${VAR_ES_INSTANCE_NAME}" "${sc_tmpl_dir}" "${MY_ES_WORKINGDIR}" "ES-Capability.yaml" "$VAR_ES_NAMESPACE" "{.status.phase}" "Ready"

    # Creating Event Streams Service Account associated with the ES instance to enable monitoring
    $MY_CLUSTER_COMMAND -n $VAR_ES_NAMESPACE adm policy add-cluster-role-to-user cluster-monitoring-view -z ${VAR_ES_SERVICE_ACCOUNT_NAME}
   
    # unset exported needed variables
    #unset VAR_ES_NAMESPACE
  fi

  trace_out $lf_tracelevel create_es
}

################################################
# Create kafka topics
function create_kafka_topics () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_kafka_topics

  local lf_source_directory="${MY_ES_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_ES_WORKINGDIR}resources/"

  # Creation of the Topics used for taxi demo
  mylog info "Creating topics" 0
  topic_names=("connect-configs" "connect-offsets" "connect-status" "toolbox.stater" "demo-flight-takeoffs" "demo-weather-armonk" "demo-weather-hursley" "demo-weather-northharbour" "demo-weather-paris" "demo-weather-southbank" "demo-stock-apple" "demo-stock-google" "demo-stock-ibm" "demo-stock-microsoft" "demo-stock-salesforce" "orders" "cancellations" "doors" "stock" "customers" "sensors" "online-orders" "nostock")
  topic_spec_names=("connect-configs" "connect-offsets" "connect-status" "TOOLBOX.STATER" "FLIGHT.TAKEOFFS" "WEATHER.ARMONK" "WEATHER.HURSLEY" "WEATHER.NORTHHARBOUR" "WEATHER.PARIS" "WEATHER.SOUTHBANK" "STOCK.APPLE" "STOCK.GOOGLE" "STOCK.IBM" "STOCK.MICROSOFT" "STOCK.SALESFORCE" "LH.ORDERS" "LH.CANCELLATIONS" "LH.DOORS" "LH.STOCK" "LH.CUSTOMERS" "LH.SENSORS" "ORDERS.ONLINE" "STOCK.NOSTOCK")
  topic_partitions=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 3 3 1 2 3 2 1 1)
  topic_replicas=(3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 1 1 3 1 1 1)
  for index in ${!topic_names[@]}
  do
      mylog info "Create topic: name: ${topic_names[$index]}, spec: ${topic_spec_names[$index]}, partitions: ${topic_partitions[$index]}, replicas: ${topic_replicas[$index]}, es_instance: ${VAR_ES_INSTANCE_NAME}, project: ${VAR_ES_NAMESPACE}" 0
      # Need to make those variables visible to the envsubst command used in lib.sh
      export VAR_ES_TOPIC_NAME=${topic_names[$index]}
      export VAR_ES_SPEC_TOPIC_NAME=${topic_spec_names[$index]}
      export VAR_ES_SPEC_TOPIC_PARTITION=${topic_partitions[$index]}
      export VAR_ES_SPEC_TOPIC_REPLICA=${topic_replicas[$index]}
  
      # CRD described at https://ibm.github.io/event-automation/es/reference/api-reference-es/
      create_oc_resource "KafkaTopic" "${VAR_ES_TOPIC_NAME}" "${lf_source_directory}" "${lf_target_directory}" "topic.yaml" "$VAR_ES_NAMESPACE"
  done
      
  trace_out $lf_tracelevel create_kafka_topics
}

################################################
# Create kafka users
function create_kafka_users () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_kafka_users

  local lf_source_directory="${MY_ES_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_ES_WORKINGDIR}resources/"

  # Creation of a Kafka user
  create_oc_resource "KafkaUser" "es-admin" "${lf_source_directory}" "${lf_target_directory}" "es-admin-user.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "es-all-access" "${lf_source_directory}" "${lf_target_directory}" "es-all-access-user.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "kafka-connect-credentials" "${lf_source_directory}" "${lf_target_directory}" "kafka-connect-credentials.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "kafka-user1" "${lf_source_directory}" "${lf_target_directory}" "kafka-user1.yaml" "$VAR_ES_NAMESPACE"

  trace_out $lf_tracelevel create_kafka_users
}

################################################
# Create kafka connector 
function create_kafka_connector () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel create_kafka_connector

  local lf_source_directory="${MY_ES_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_ES_WORKINGDIR}resources/"

  # Create KafkaConnect and KafkaConnector in $ES_APPS_PROJECT project
  mylog info "Create Kafka Connect for datagen, and MQ connectors" 0
   
  create_oc_resource "KafkaConnect" "${VAR_ES_KAFKA_CONNECT_INSTANCE_NAME}" "${lf_source_directory}" "${MY_ES_WORKINGDIR}" "KConnect.yaml" "$VAR_ES_NAMESPACE"
  # TODO check for the TLS configuration: https://ibm.github.io/event-automation/es/connecting/mq/#configuration-options
  
  mylog info "Create Kafka Connectors for datagen and MQ connectors" 0
  create_oc_resource "KafkaConnector" "datagen" "${lf_source_directory}" "${lf_target_directory}" "KConnector_datagen.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaConnector" "mq-sink" "${lf_source_directory}" "${lf_target_directory}" "KConnector_MQ_sink.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaConnector" "mq-source" "${lf_source_directory}" "${lf_target_directory}" "KConnector_MQ_source.yaml" "$VAR_ES_NAMESPACE"

  trace_out $lf_tracelevel create_kafka_connector
}

################################################
# run all
function es_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel es_run_all

  SECONDS=0
  local lf_starting_date=$(date);

  check_directory_exist_create "${MY_ES_WORKINGDIR}"

  # Create namespace 
  create_project "$VAR_ES_NAMESPACE" "$VAR_ES_NAMESPACE project" "For Event Streams customisation" "${MY_RESOURCESDIR}" "${MY_ES_WORKINGDIR}"

  echo "Commented to work on the connector framework, need to uncomment when done"
  # create_es

  # create_kafka_topics

  # create_kafka_users

  create_kafka_connector

  local lf_ending_date=$(date)
    
  mylog info "==== Customisation of es [ended : $lf_ending_date and took : $SECONDS seconds]." 0

  trace_out $lf_tracelevel es_run_all
}


################################################
# initialisation
function es_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel es_init
  
  sc_tmpl_dir="${sc_component_script_dir}../tmpl/"
  
  trace_out $lf_tracelevel es_init
}

################################################
# main function
# Main logic
function main() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel main

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
        trace_out $lf_tracelevel main
        return 1
        ;;
      esac
  done
  #lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces
  lf_calls=$(echo "$lf_calls" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')
  
  # Call processing function if --call was used
  case $lf_key in
    --all) es_run_all "$@";;
    --call) if [[ -n $lf_calls ]]; then
              process_calls "$lf_calls"
            else
              mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
              trace_out $lf_tracelevel main
              return 1
            fi;;
    esac

  trace_out $lf_tracelevel main
  exit 0
}

################################################
# Start of the script main entry
################################################
# other example: ./es.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./es.config.sh --all
#################################

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
export MY_ES_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/es.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load resources files
. "${sc_provision_constant_properties_file}"

# load resources files
. "${sc_provision_variable_properties_file}"

# Load mq variables
. "${sc_component_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

es_init

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi