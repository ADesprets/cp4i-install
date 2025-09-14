################################################
# Create IBM Event streams instance
function create_es() {
  local lf_tracelevel=3
	trace_in $lf_tracelevel create_es

  local lf_in_cr_name="$1"
  local lf_in_source_directory="$2"
  local lf_in_target_directory="$3"
  local lf_in_yaml_file="$4"
  local lf_in_namespace="$5"

  local lf_source_relative_path=$(echo "${lf_in_source_directory#"$PROVISION_SCRIPTDIR"}")
  local lf_target_relative_path=$(echo "${lf_in_target_directory#"$MY_WORKINGDIR"}") 
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$lf_source_relative_path\"|\"$lf_target_relative_path\"|\"$5\"|\"$6\"|"

  if [[ $# -ne 5 ]]; then
    mylog error "You have to provide 5 arguments: resource, source directory, destination directory, yaml file and namespace"
    trace_out $lf_tracelevel create_es
    exit 1
  fi
    
  # ibm-eventstreams
  if $MY_ES; then

    # Creating Event Streams instance

    export VAR_ES_INSTANCE_NAME=$lf_in_cr_name
    export VAR_ES_NAMESPACE=$lf_in_namespace
    create_operand_instance "EventStreams" "${lf_in_cr_name}" "${lf_in_source_directory}" "${lf_in_target_directory}" "${lf_in_yaml_file}" "${lf_in_namespace}" "{.status.phase}" "Ready"

    # Creating Event Streams Service Account associated with the ES instance to enable monitoring
    $MY_CLUSTER_COMMAND -n $VAR_ES_NAMESPACE adm policy add-cluster-role-to-user cluster-monitoring-view -z ${VAR_ES_SERVICE_ACCOUNT_NAME}
   
    # unset exported needed variables
    #unset VAR_ES_NAMESPACE
  fi

  trace_out $lf_tracelevel create_es
}

#####################################
# Create kafka topics
function create_kafka_topics () {
  local lf_tracelevel=3
	trace_in $lf_tracelevel create_kafka_topics

  local lf_in_source_directory="$1"
  local lf_in_target_directory="$2"

  local lf_source_relative_path=$(echo "${lf_in_source_directory#"$PROVISION_SCRIPTDIR"}")
  local lf_target_relative_path=$(echo "${lf_in_target_directory#"$MY_WORKINGDIR"}") 
  decho $lf_tracelevel "Parameters:\"$lf_source_relative_path\"|\"$lf_target_relative_path\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments: source directory and destination directory"
    trace_out $lf_tracelevel create_kafka_topics
    exit 1
  fi
    
  mylog info "Creating topics" 0
  topic_names=("connect-configs" "connect-offsets" "connect-status" "tp1" "orders" "cancellations" "doors" "stock" "customers" "sensors")
  topic_spec_names=("connect-configs" "connect-offsets" "connect-status" "MY.TP1" "LH.ORDERS" "LH.CANCELLATIONS" "LH.DOORS" "LH.STOCK" "LH.CUSTOMERS" "LH.SENSORS")
  topic_partitions=(1 1 1 1 3 3 1 2 3 2)
  topic_replicas=(3 3 3 3 3 3 1 1 3 1)
  for index in ${!topic_names[@]}
  do
      mylog info "Create topic: name: ${topic_names[$index]}, spec: ${topic_spec_names[$index]}, partitions: ${topic_ 0partitions[$index]}, replicas: ${topic_replicas[$index]}, es_instance: ${VAR_ES_INSTANCE_NAME}, project: ${VAR_ES_NAMESPACE}"
      # Need to make those variables visible to the envsubst command used in lib.sh
      export VAR_ES_TOPIC_NAME=${topic_names[$index]}
      export VAR_ES_SPEC_TOPIC_NAME=${topic_spec_names[$index]}
      export VAR_ES_SPEC_TOPIC_PARTITION=${topic_partitions[$index]}
      export VAR_ES_SPEC_TOPIC_REPLICA=${topic_replicas[$index]}
  
      # CRD described at https://ibm.github.io/event-automation/es/reference/api-reference-es/
      create_oc_resource "KafkaTopic" "${VAR_ES_TOPIC_NAME}" "${lf_in_source_directory}" "${lf_in_target_directory}" "topic.yaml" "$VAR_ES_NAMESPACE"
  done
      
  trace_out $lf_tracelevel create_kafka_topics
}

#####################################
# Create kafka users
function create_kafka_users () {
  local lf_tracelevel=3
	trace_in $lf_tracelevel create_kafka_users

  local lf_in_source_directory="$1"
  local lf_in_target_directory="$2"

  local lf_source_relative_path=$(echo "${lf_in_source_directory#"$PROVISION_SCRIPTDIR"}")
  local lf_target_relative_path=$(echo "${lf_in_target_directory#"$MY_WORKINGDIR"}") 
  decho $lf_tracelevel "Parameters:\"$lf_source_relative_path\"|\"$lf_target_relative_path\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments: source directory and destination directory"
    trace_out $lf_tracelevel create_kafka_topics
    exit 1
  fi

  # Creation of a Kafka user
  create_oc_resource "KafkaUser" "es-admin" "${lf_in_source_directory}" "${lf_in_target_directory}" "es-admin-user.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "es-all-access" "${lf_in_source_directory}" "${lf_in_target_directory}" "es-all-access-user.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "kafka-connect-credentials" "${lf_in_source_directory}" "${lf_in_target_directory}" "kafka-connect-credentials.yaml" "$VAR_ES_NAMESPACE"

  create_oc_resource "KafkaUser" "kafka-user1" "${lf_in_source_directory}" "${lf_in_target_directory}" "kafka-user1.yaml" "$VAR_ES_NAMESPACE"

  trace_out $lf_tracelevel create_kafka_users
}

#####################################
# Create kafka connector 
function create_kafka_connector () {
 	local lf_tracelevel=3
	trace_in $lf_tracelevel create_kafka_connector

  local lf_in_source_directory="$1"
  local lf_in_target_directory="$2"

  local lf_source_relative_path=$(echo "${lf_in_source_directory#"$PROVISION_SCRIPTDIR"}")
  local lf_target_relative_path=$(echo "${lf_in_target_directory#"$MY_WORKINGDIR"}") 
  decho $lf_tracelevel "Parameters:\"$lf_source_relative_path\"|\"$lf_target_relative_path\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments: source directory and destination directory"
    trace_out $lf_tracelevel create_kafka_connector
    exit 1
  fi

  # Create KafkaConnect and KafkaConnector in $ES_APPS_PROJECT project
  mylog info "Create Kafka Connect for datagen, and MQ connectors" 0
   
  create_oc_resource "KafkaConnect" "${VAR_ES_KAFKA_CONNECT_INSTANCE_NAME}" "${lf_in_source_directory}" "${lf_in_target_directory}" "KConnect.yaml" "$VAR_ES_NAMESPACE"
  # TODO check for the TLS configuration: https://ibm.github.io/event-automation/es/connecting/mq/#configuration-options
  
  mylog info "Create Kafka Connectors for datagen and MQ connectors" 0
  create_oc_resource "KafkaConnector" "datagen" "${lf_in_source_directory}" "${lf_in_target_directory}" "KConnector_datagen.yaml" "$VAR_ES_NAMESPACE"

  trace_out $lf_tracelevel create_kafka_connector
}

#####################################
# Create Evenstreams instance with topics and users and connectors
# @param 1: dir: the source directory example: "${subscriptionsdir}"
# @param 2: dir: the target directory example: "${workingdir}apic/"
# @param 3: namespace
function create_eventstreams_instance () {
  local lf_tracelevel=3
	trace_in $lf_tracelevel create_eventstreams_instance

  local lf_in_cr_name="$1"
  local lf_in_source_directory="$2"
  local lf_in_target_directory="$3"
  local lf_in_namespace="$4"

  local lf_source_relative_path=$(echo "${lf_in_source_directory#"$PROVISION_SCRIPTDIR"}")
  local lf_target_relative_path=$(echo "${lf_in_target_directory#"$MY_WORKINGDIR"}") 
  decho $lf_tracelevel "Parameters:\"$1\"|\"$lf_source_relative_path\"|\"$lf_target_relative_path\"|\"$3\"|"

  if [[ $# -ne 4 ]]; then
    mylog error "You have to provide 4 arguments: resource, source directory, destination directory and namespace"
    trace_out $lf_tracelevel create_eventstreams_instance
    exit 1
  fi
  
  # we surcharge the environment variables with the ones from the script
  export VAR_ES_NAMESPACE="$lf_in_namespace"

  check_directory_exist_create "${lf_in_target_directory}"

  # Create namespace 
  create_project "$VAR_ES_NAMESPACE" "$VAR_ES_NAMESPACE project" "For Esventstreams customisation" "${lf_in_source_directory}" "${lf_in_target_directory}"
  add_ibm_entitlement $VAR_ES_NAMESPACE

  create_es "${lf_in_cr_name}" "${lf_in_source_directory}" "${lf_in_target_directory}" "ES-Capability.yaml" "$VAR_ES_NAMESPACE"

  create_kafka_topics "${lf_in_source_directory}" "${lf_in_target_directory}"

  create_kafka_users "${lf_in_source_directory}" "${lf_in_target_directory}"

  create_kafka_connector "${lf_in_source_directory}" "${lf_in_target_directory}"

  trace_out $lf_tracelevel create_eventstreams_instance
}

#####################################
# run all
function es_run_all () {
  local lf_tracelevel=3
	trace_in $lf_tracelevel es_run_all

  # Create Event Streams instances
  create_eventstreams_instance "${VAR_ES_INSTANCE_NAME1}" "${sc_component_tmpl_dir}" "${VAR_ES_WORKINGDIR1}" "${VAR_ES_NAMESPACE1}"
  create_eventstreams_instance "${VAR_ES_INSTANCE_NAME2}" "${sc_component_tmpl_dir}" "${VAR_ES_WORKINGDIR2}" "${VAR_ES_NAMESPACE2}"

  # Start producers

  es_display_access_info
  
  trace_out $lf_tracelevel es_run_all
}

################################################
# Display information to access Eventstreams
function es_display_access_info() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel es_display_access_info

  mylog info "==== Displaying Access Info to ES." 0

  local lf_bookmarks_file="${VAR_ES_WORKINGDIR}es_mm2_bookmarks.html"

  # Initialisation of the bookmark
  echo ${BOOKMARK_PROLOGUE} > ${lf_bookmarks_file}

  # Event Streams
  local lf_index lf_es_ui_url lf_es_admin_url lf_es_apicurioregistry_url lf_es_restproducer_url lf_es_bootstrap_urls lf_es_admin_pwd

  local lf_var_namesapces=("VAR_ES_NAMESPACE1" "VAR_ES_NAMESPACE2" "VAR_ES_NAMESPACE3")

  
  for lf_index in {1..3}; do
    local lf_es_namespace_string="VAR_ES_NAMESPACE$lf_index"
    local lf_es_namespace=${!lf_es_namespace_string}
    local lf_es_ui_url=$($MY_CLUSTER_COMMAND -n $lf_es_namespace get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Streams Management UI endpoint: ${lf_es_ui_url}" 0
    echo  "<DT><A HREF=${lf_es_ui_url}>Event Streams Management UI</A>" >> ${lf_bookmarks_file}
    lf_es_admin_url=$($MY_CLUSTER_COMMAND -n $lf_es_namespace get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "Event Streams Management admin endpoint: ${lf_es_admin_url}" 0
    lf_es_apicurioregistry_url=$($MY_CLUSTER_COMMAND -n $lf_es_namespace get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="apicurioregistry")].uri}')
    mylog info "Event Streams Management apicurio registry endpoint: ${lf_es_apicurioregistry_url}" 0
    lf_es_restproducer_url=$($MY_CLUSTER_COMMAND -n $lf_es_namespace get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="restproducer")].uri}')
    mylog info "Event Streams Management REST Producer endpoint: ${lf_es_restproducer_url}" 0
    lf_es_bootstrap_urls=$($MY_CLUSTER_COMMAND -n $lf_es_namespace get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.kafkaListeners[*].bootstrapServers}')
    mylog info "Event Streams Bootstraps servers endpoints: ${lf_es_bootstrap_urls}" 0
    lf_es_admin_pwd=$($MY_CLUSTER_COMMAND -n $lf_es_namespace get secret es-admin -o jsonpath={.data.password} | base64 -d)
    mylog info "Event Streams UI Credentials: es-admin/${lf_es_admin_pwd}" 0
    local lf_es_admin_url=$($MY_CLUSTER_COMMAND -n $lf_es_namespace get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "Event Streams Management admin endpoint: ${lf_es_admin_url}" 0
    echo  "<DT><A HREF=${lf_es_admin_url}>Event Streams Management Admin</A>" >> ${lf_bookmarks_file}
    echo
  done

  echo ${BOOKMARK_EPILOGUE} >> ${lf_bookmarks_file}

  trace_out $lf_tracelevel es_display_access_info
}

################################################
# initialisation
function es_init() {
  local lf_tracelevel=2
	trace_in $lf_tracelevel es_init

  export VAR_ES_WORKINGDIR="${MY_WORKINGDIR}DEMOS/ES_MM2/"
  check_directory_exist_create "${VAR_ES_WORKINGDIR}"

  # tmpl directory
  sc_component_tmpl_dir="${sc_component_script_dir}../tmpl/"
  trace_out $lf_tracelevel es_init
}

################################################
# main function
# Main logic
function main() {
  local lf_starting_date=$(date)
  local lf_satrting_date_in_seconds=$(date +%s)
  mylog info "==== Start: es_mm2 demo (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

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

  local lf_ending_date=$(date)
  local lf_ending_date_in_seconds=$(date +%s)
  local lf_duration=$((lf_ending_date_in_seconds - lf_satrting_date_in_seconds))
  mylog info "==== End: es_mm2 demo  of CP4I Components (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $(($lf_duration / 60)) minutes and $(($lf_duration % 60)) seconds]." 0

  exit 0
}

################################################################################################
# Start of the script main entry
################################################################################################
# other example: ./es.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./es.config.sh --all
################################################################################################

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

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/es_mm2.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load resources files
. "${sc_provision_constant_properties_file}"

# load resources files
. "${sc_provision_variable_properties_file}"

# Load component variables
. "${sc_component_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

es_init

#trap 'es_display_access_info' EXIT

######################################################
# main entry
######################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi