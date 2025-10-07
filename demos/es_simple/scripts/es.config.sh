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

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create kafka topics
function create_kafka_topics () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_source_directory="${MY_ES_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_ES_WORKINGDIR}resources/"

  # Creation of the Topics used for taxi demo
  mylog info "Creating topics"
  topic_names=("connect-configs" "connect-offsets" "connect-status" "toolbox.stater" "demo-flight-takeoffs" "demo-door-badgein " "demo-cancellations " "demo-customers-new " "demo-orders-new " "demo-sensor-readings " "demo-stock-movement " "demo-orders-online " "demo-stock-nostock " "demo-product-returns " "demo-product-reviews " "demo-transactions " "demo-orders-abandoned" "orders" "doors" "stock")
  topic_spec_names=("connect-configs" "connect-offsets" "connect-status" "TOOLBOX.STATER" "FLIGHT.TAKEOFFS" "DOOR.BADGEIN " "CANCELLATIONS " "CUSTOMERS.NEW " "ORDERS.NEW " "SENSOR.READINGS " "STOCK.MOVEMENT " "ORDERS.ONLINE " "STOCK.NOSTOCK " "PRODUCT.RETURNS " "PRODUCT.REVIEWS " "TRANSACTIONS " "ORDERS.ABANDONED " "LH.ORDERS" "LH.DOORS" "LH.STOCK")
  topic_partitions=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 3 3 1 2)
  topic_replicas=(3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 1 1)
  for index in ${!topic_names[@]}
  do
      mylog info "Create topic: name: ${topic_names[$index]}, spec: ${topic_spec_names[$index]}, partitions: ${topic_partitions[$index]}, replicas: ${topic_replicas[$index]}, es_instance: ${VAR_ES_INSTANCE_NAME}, project: ${VAR_ES_NAMESPACE}"
      # Need to make those variables visible to the envsubst command used in lib.sh
      export VAR_ES_TOPIC_NAME=${topic_names[$index]}
      export VAR_ES_SPEC_TOPIC_NAME=${topic_spec_names[$index]}
      export VAR_ES_SPEC_TOPIC_PARTITION=${topic_partitions[$index]}
      export VAR_ES_SPEC_TOPIC_REPLICA=${topic_replicas[$index]}
  
      # CRD described at https://ibm.github.io/event-automation/es/reference/api-reference-es/
      create_oc_resource "KafkaTopic" "${VAR_ES_TOPIC_NAME}" "${lf_source_directory}" "${lf_target_directory}" "topic.yaml" "$VAR_ES_NAMESPACE"
  done
      
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create kafka users
function create_kafka_users () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_source_directory="${MY_ES_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_ES_WORKINGDIR}resources/"

  # Creation of a Kafka user
  create_oc_resource "KafkaUser" "es-admin" "${lf_source_directory}" "${lf_target_directory}" "es-admin-user.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "es-all-access" "${lf_source_directory}" "${lf_target_directory}" "es-all-access-user.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "kafka-connect-credentials" "${lf_source_directory}" "${lf_target_directory}" "kafka-connect-credentials.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "kafka-user1" "${lf_source_directory}" "${lf_target_directory}" "kafka-user1.yaml" "$VAR_ES_NAMESPACE"

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create kafka connector 
function create_kafka_connector () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_source_directory="${MY_ES_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_ES_WORKINGDIR}resources/"

  # Create KafkaConnect and KafkaConnector in $ES_APPS_PROJECT project
  mylog info " for datagen, and MQ connectors" 0

  # Need to position a few variables for the source connector, for now hard coded, could be defined as parameters
  export VAR_CHL_UC="ORDERSCHL"
  export VAR_QMGR_LC="orders"  
  export VAR_ES_MQ_SOURCE="PAYMT.REQ.CPY"
  export VAR_ES_TOPIC_DEST="LH.ORDERS"
  export VAR_QMGR_CONNECTION_HOST=""
  # for example cp4i-mq-orders-server
  export VAR_MQ_ORDERS_TLS_SECRET="${VAR_MQ_NAMESPACE}-mq-${VAR_QMGR_LC}-server"

  # Will exit if the secret does not exist
  local lf_jks_secret_name="${VAR_MQ_NAMESPACE}-mq-store-root-secret"
  if check_resource_exist secret $lf_jks_secret_name $VAR_MQ_NAMESPACE true; then
    local lf_store_password=$(oc -n "${VAR_MQ_NAMESPACE}" get secret "$lf_jks_secret_name" -o jsonpath='{.data.password}' | base64 --decode)
    export VAR_ES_MQ_SOURCE_STORE_PASSWORD=${lf_store_password}
  fi
  
  create_oc_resource "KafkaConnect" "${VAR_ES_KAFKA_CONNECT_INSTANCE_NAME}" "${lf_source_directory}" "${MY_ES_WORKINGDIR}" "KConnect.yaml" "$VAR_ES_NAMESPACE"
  export VAR_MQ_ORDERS_TLS_SECRET=${VAR_MQ_NAMESPACE}-mq-${VAR_QMGR_LC}-server
  # TODO check for the TLS configuration: https://ibm.github.io/event-automation/es/connecting/mq/#configuration-options
  
  mylog info "Create Kafka Connectors for datagen and MQ connectors"
  create_oc_resource "KafkaConnector" "datagen" "${lf_source_directory}" "${lf_target_directory}" "KConnector_datagen.yaml" "$VAR_ES_NAMESPACE"

  # create_oc_resource "KafkaConnector" "mq-sink" "${lf_source_directory}" "${lf_target_directory}" "KConnector_MQ_sink.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaConnector" "mq-source" "${lf_source_directory}" "${lf_target_directory}" "KConnector_MQ_source.yaml" "$VAR_ES_NAMESPACE"
  unset $VAR_ES_MQ_SOURCE_STORE_PASSWORD

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# run all
function es_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  SECONDS=0
  local lf_starting_date=$(date);

  check_directory_exist_create "${MY_ES_WORKINGDIR}"

  # Create namespace 
  create_project "$VAR_ES_NAMESPACE" "$VAR_ES_NAMESPACE project" "For Event Streams customisation" "${MY_RESOURCESDIR}" "${MY_ES_WORKINGDIR}"

  create_es

  create_kafka_topics

  create_kafka_users

  create_kafka_connector

  local lf_ending_date=$(date)
    
  mylog info "==== Customisation of es [ended : $lf_ending_date and took : $SECONDS seconds]." 0

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}


################################################
# initialisation
function es_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ${FUNCNAME[0]}
  
  sc_tmpl_dir="${sc_component_script_dir}../tmpl/"
  
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
    --all) es_run_all "$@";;
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