################################################
# Grant cluster monitoring view to the Kafka service account (optional)
function grant_kafka_monitoring() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  if $MY_CONFLUENT; then
    mylog info "Granting cluster-monitoring-view to Confluent service account in ${VAR_CONFLUENT_NAMESPACE}" 1>&2
    $MY_CLUSTER_COMMAND -n "${VAR_CONFLUENT_NAMESPACE}" adm policy add-cluster-role-to-user cluster-monitoring-view \
      -z "kafka" 2>/dev/null || true
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create kafka topics
function create_kafka_topics () {
  local lf_tracelevel=4
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_source_directory="${MY_CONFLUENT_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_CONFLUENT_WORKINGDIR}resources/"

  # Creation of the Topics used for taxi demo
  mylog info "Creating topics"
  topic_names=("connect-configs" "connect-offsets" "connect-status" "toolbox.stater" "demo-flight-takeoffs" "demo-door-badgein " "demo-cancellations " "demo-customers-new " "demo-orders-new " "demo-sensor-readings " "demo-stock-movement " "demo-orders-online " "demo-stock-nostock " "demo-product-returns " "demo-product-reviews " "demo-transactions " "demo-orders-abandoned" "orders" "doors" "stock")
  topic_spec_names=("connect-configs" "connect-offsets" "connect-status" "TOOLBOX.STATER" "FLIGHT.TAKEOFFS" "DOOR.BADGEIN " "CANCELLATIONS " "CUSTOMERS.NEW " "ORDERS.NEW " "SENSOR.READINGS " "STOCK.MOVEMENT " "ORDERS.ONLINE " "STOCK.NOSTOCK " "PRODUCT.RETURNS " "PRODUCT.REVIEWS " "TRANSACTIONS " "ORDERS.ABANDONED " "LH.ORDERS" "LH.DOORS" "LH.STOCK")
  topic_partitions=(1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 3 3 1 2)
  topic_replicas=(3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 1 1)
  for index in ${!topic_names[@]}
  do
      mylog info "Create topic: name: ${topic_names[$index]}, spec: ${topic_spec_names[$index]}, partitions: ${topic_partitions[$index]}, replicas: ${topic_replicas[$index]}, es_instance: ${VAR_CONFLUENT_INSTANCE_NAME}, project: ${VAR_ES_NAMESPACE}"
      # Need to make those variables visible to the envsubst command used in lib.sh
      export VAR_CONFLUENT_TOPIC_NAME=${topic_names[$index]}
      export VAR_CONFLUENT_SPEC_TOPIC_NAME=${topic_spec_names[$index]}
      export VAR_CONFLUENT_TOPIC_PARTITIONS=${topic_partitions[$index]}
      export VAR_CONFLUENT_TOPIC_REPLICAS=${topic_replicas[$index]}
      export VAR_CONFLUENT_TOPIC_CLEANUP_POLICY="delete"

      # Use the project template for Confluent KafkaTopic CRD
      create_oc_resource "KafkaTopic" "${VAR_CONFLUENT_TOPIC_NAME}" "${lf_source_directory}" "${lf_target_directory}" "topic.yaml" "${VAR_CONFLUENT_NAMESPACE}"
  done
      
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create kafka users
function create_kafka_users () {
  local lf_tracelevel=4
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_source_directory="${MY_CONFLUENT_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_CONFLUENT_WORKINGDIR}resources/"

  # Creation of Kafka users in the Confluent namespace
  create_oc_resource "KafkaUser" "cft-admin" "${lf_source_directory}" "${lf_target_directory}" "cft-admin-user.yaml" "${VAR_CONFLUENT_NAMESPACE}"

  create_oc_resource "KafkaUser" "cft-all-access" "${lf_source_directory}" "${lf_target_directory}" "cft-all-access-user.yaml" "${VAR_CONFLUENT_NAMESPACE}"

  create_oc_resource "KafkaUser" "kafka-connect-credentials" "${lf_source_directory}" "${lf_target_directory}" "kafka-connect-credentials.yaml" "${VAR_CONFLUENT_NAMESPACE}"

  create_oc_resource "KafkaUser" "kafka-user1" "${lf_source_directory}" "${lf_target_directory}" "kafka-user1.yaml" "${VAR_CONFLUENT_NAMESPACE}"

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create kafka connector 
function create_kafka_connector () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_source_directory="${MY_CONFLUENT_SIMPLE_DEMODIR}resources/"
  local lf_target_directory="${MY_CONFLUENT_WORKINGDIR}resources/"

  # Create KafkaConnect and KafkaConnector in $ES_APPS_PROJECT project
  mylog info " for datagen, and MQ connectors" 0

  # Need to position a few variables for the source connector, for now hard coded, could be defined as parameters
  export VAR_CHL_UC="ORDERSCHL"
  export VAR_QMGR_LC="orders"  
  export VAR_ES_MQ_SOURCE="PAYMT.REQ.CPY"
  export VAR_ES_TOPIC_DEST="LH.ORDERS"
  export VAR_QMGR_CONNECTION_HOST=""
  # for example cp4i-mq-orders-server
  export VAR_MQ_ORDERS_TLS_SECRET="mq-${VAR_QMGR_LC}-server"

  # Create the certificate if it does not exist and copy it to MQ namespace
  local lf_jks_secret_name="mq-store-root-secret"
  if check_resource_exist secret $lf_jks_secret_name $VAR_ES_NAMESPACE true; then
    local lf_store_password=$(oc -n "${VAR_ES_NAMESPACE}" get secret "$lf_jks_secret_name" -o jsonpath='{.data.password}' | base64 --decode)
    export VAR_ES_MQ_SOURCE_STORE_PASSWORD=${lf_store_password}
  fi
  
  create_oc_resource "KafkaConnect" "${VAR_ES_KAFKA_CONNECT_INSTANCE_NAME}" "${lf_source_directory}" "${MY_CONFLUENT_WORKINGDIR}" "KConnect.yaml" "${VAR_CONFLUENT_NAMESPACE}"
  export VAR_MQ_ORDERS_TLS_SECRET=mq-${VAR_QMGR_LC}-server

  mylog info "Create Kafka Connectors for datagen and MQ connectors"
  create_oc_resource "KafkaConnector" "datagen" "${lf_source_directory}" "${lf_target_directory}" "KConnector_datagen.yaml" "${VAR_CONFLUENT_NAMESPACE}"

  # create_oc_resource "KafkaConnector" "mq-sink" "${lf_source_directory}" "${lf_target_directory}" "KConnector_MQ_sink.yaml" "${VAR_CONFLUENT_NAMESPACE}"

  create_oc_resource "KafkaConnector" "mq-source" "${lf_source_directory}" "${lf_target_directory}" "KConnector_MQ_source.yaml" "${VAR_CONFLUENT_NAMESPACE}"
  unset $VAR_ES_MQ_SOURCE_STORE_PASSWORD

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Deploy Confluent operands: KRaftController → Kafka → KafkaTopic (demo)
# Called by confluent_run_all as part of the demo/customisation phase.
# The Confluent for Kubernetes Operator must already be installed (install_confluent).
function create_confluent_operands() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  if ! $MY_CONFLUENT; then
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 0
  fi

  # Export variables consumed by templates (via adapt_file / envsubst)
  export VAR_CONFLUENT_NAMESPACE
  export VAR_CONFLUENT_KRAFTCONTROLLER_REPLICAS=${MY_CONFLUENT_KRAFTCONTROLLER_REPLICAS}
  export VAR_CONFLUENT_KAFKA_REPLICAS=${MY_CONFLUENT_KAFKA_REPLICAS}
  export VAR_CONFLUENT_DATA_VOLUME_CAPACITY=${MY_CONFLUENT_DATA_VOLUME_CAPACITY}
  export VAR_CONFLUENT_SERVER_IMAGE=${MY_CONFLUENT_SERVER_IMAGE}
  # KRaftController uses cp-server (same as Kafka brokers) per CFK API reference.
  export VAR_CONFLUENT_KAFKA_IMAGE=${MY_CONFLUENT_SERVER_IMAGE}
  export VAR_CONFLUENT_INIT_IMAGE=${MY_CONFLUENT_INIT_IMAGE}
  # Block StorageClass — CephFS excluded for Kafka data volumes.
  export VAR_CONFLUENT_STORAGE_CLASS=${MY_CONFLUENT_STORAGE_CLASS}

  # TLS mode — explicit, no silent fallback.
  # Ref: https://docs.confluent.io/operator/current/co-network-encryption.html
  case "${MY_CONFLUENT_TLS_MODE:-cfk-managed}" in
    cfk-managed)
      export VAR_CONFLUENT_TLS_AUTO_CERTS="true"
      export VAR_CONFLUENT_CA_ANNOTATION="platform.confluent.io/managed-cert-ca-pair-secret: ${MY_CONFLUENT_CA_SECRET}"
      mylog info "Confluent TLS: cfk-managed (CA Secret: ${MY_CONFLUENT_CA_SECRET})" 1>&2
      ;;
    provided-secret)
      export VAR_CONFLUENT_TLS_AUTO_CERTS="false"
      export VAR_CONFLUENT_CA_ANNOTATION=""
      mylog info "Confluent TLS: provided-secret (${MY_CONFLUENT_TLS_SECRET})" 1>&2
      ;;
    *)
      mylog error "MY_CONFLUENT_TLS_MODE='${MY_CONFLUENT_TLS_MODE}' is invalid. Use cfk-managed or provided-secret." 1>&2
      trace_out $lf_tracelevel ${FUNCNAME[0]}
      return 1
      ;;
  esac

  # ── TLS: cert-manager certificate chain ──────────────────────────────────
  # Pattern identical to Valkey (see provision_cluster-v2.sh).
  # 1. Self-signed root issuer
  create_self_signed_issuer "${VAR_CONFLUENT_ISSUER}-root" "${VAR_CONFLUENT_NAMESPACE}" "${MY_CONFLUENT_WORKINGDIR}"

  # 2. Root CA certificate → Secret name = MY_CONFLUENT_CA_SECRET
  export VAR_CERT_NAME="${VAR_CONFLUENT_NAMESPACE}-confluent-root"
  export VAR_NAMESPACE="${VAR_CONFLUENT_NAMESPACE}"
  export VAR_CERT_ISSUER_REF="${VAR_CONFLUENT_ISSUER}-root"
  export VAR_CERT_SECRET_NAME="${MY_CONFLUENT_CA_SECRET}"
  export VAR_CERT_COMMON_NAME="ConfluentCA"
  export VAR_CERT_ORGANISATION="${MY_CERT_ORGANISATION}"
  export VAR_CERT_COUNTRY="${MY_CERT_COUNTRY}"
  export VAR_CERT_LOCALITY="${MY_CERT_LOCALITY}"
  export VAR_CERT_STATE="${MY_CERT_STATE}"
  create_certificate "${VAR_CONFLUENT_NAMESPACE}" "${MY_CONFLUENT_WORKINGDIR}" "ca_certificate.yaml"

  # 3. Intermediate issuer (signs with the CA secret just created)
  create_intermediate_issuer "${VAR_CONFLUENT_ISSUER}-int" "${MY_CONFLUENT_CA_SECRET}" "${MY_CONFLUENT_WORKINGDIR}" "${VAR_CONFLUENT_NAMESPACE}"

  # 4. Server/leaf certificate (SANs for Kafka internal service)
  export VAR_CERT_NAME="${VAR_CONFLUENT_NAMESPACE}-confluent-server"
  export VAR_NAMESPACE="${VAR_CONFLUENT_NAMESPACE}"
  export VAR_CERT_ISSUER_REF="${VAR_CONFLUENT_ISSUER}-int"
  export VAR_CERT_SECRET_NAME="${VAR_CONFLUENT_NAMESPACE}-confluent-server"
  export VAR_CERT_COMMON_NAME="kafka.${VAR_CONFLUENT_NAMESPACE}.svc.cluster.local"
  export VAR_CERT_ORGANISATION="${MY_CERT_ORGANISATION}"
  export VAR_CERT_COUNTRY="${MY_CERT_COUNTRY}"
  export VAR_CERT_LOCALITY="${MY_CERT_LOCALITY}"
  export VAR_CERT_STATE="${MY_CERT_STATE}"
  export VAR_CERT_SAN_DNS_1="kafka.${VAR_CONFLUENT_NAMESPACE}.svc.cluster.local"
  export VAR_CERT_SAN_DNS_2="kafka.${VAR_CONFLUENT_NAMESPACE}.svc"
  create_certificate "${VAR_CONFLUENT_NAMESPACE}" "${MY_CONFLUENT_WORKINGDIR}" "server_certificate.yaml"
  unset VAR_CERT_NAME VAR_NAMESPACE VAR_CERT_ISSUER_REF VAR_CERT_SECRET_NAME \
        VAR_CERT_COMMON_NAME VAR_CERT_ORGANISATION VAR_CERT_COUNTRY \
        VAR_CERT_LOCALITY VAR_CERT_STATE VAR_CERT_SAN_DNS_1 VAR_CERT_SAN_DNS_2

  # Deploy KRaftController
  # Use fully-qualified API group to avoid collision with IBM Event Streams CRDs
  # (kraftcontrollers.platform.confluent.io vs kraftcontrollers.eventstreams.ibm.com)
  mylog info "Deploying KRaftController" 1>&2
  create_operand_instance "kraftcontrollers.platform.confluent.io" "kraftcontroller" \
    "${MY_OPERANDSDIR}" "${MY_CONFLUENT_WORKINGDIR}" \
    "CFT-KRaftController-Capability.yaml" \
    "${VAR_CONFLUENT_NAMESPACE}" \
    "{.status.phase}" "RUNNING"

  # Deploy Kafka cluster (depends on KRaftController)
  # kafka.platform.confluent.io avoids collision with kafka.eventstreams.ibm.com
  mylog info "Deploying Kafka cluster" 1>&2
  create_operand_instance "kafkas.platform.confluent.io" "kafka" \
    "${MY_OPERANDSDIR}" "${MY_CONFLUENT_WORKINGDIR}" \
    "CFT-Kafka-Capability.yaml" \
    "${VAR_CONFLUENT_NAMESPACE}" \
    "{.status.phase}" "RUNNING"

  # Deploy demo KafkaTopic
  # kafkatopics.platform.confluent.io avoids collision with kafkatopics.eventstreams.ibm.com
  mylog info "Creating demo KafkaTopic '${VAR_CONFLUENT_TOPIC_NAME}'" 1>&2
  export VAR_CONFLUENT_TOPIC_PARTITIONS=${MY_CONFLUENT_TOPIC_PARTITIONS:-12}
  export VAR_CONFLUENT_TOPIC_REPLICAS=${MY_CONFLUENT_TOPIC_REPLICAS:-3}
  export VAR_CONFLUENT_TOPIC_CLEANUP_POLICY=${MY_CONFLUENT_TOPIC_CLEANUP_POLICY:-compact}
  create_operand_instance "kafkatopics.platform.confluent.io" "${VAR_CONFLUENT_TOPIC_NAME}" \
    "${MY_OPERANDSDIR}" "${MY_CONFLUENT_WORKINGDIR}" \
    "CFT-KafkaTopic-Capability.yaml" \
    "${VAR_CONFLUENT_NAMESPACE}" \
    "{.status.state}" "CREATED"

  unset VAR_CONFLUENT_KRAFTCONTROLLER_REPLICAS VAR_CONFLUENT_KAFKA_REPLICAS \
        VAR_CONFLUENT_DATA_VOLUME_CAPACITY VAR_CONFLUENT_SERVER_IMAGE \
        VAR_CONFLUENT_KAFKA_IMAGE VAR_CONFLUENT_INIT_IMAGE VAR_CONFLUENT_STORAGE_CLASS \
        VAR_CONFLUENT_TLS_AUTO_CERTS VAR_CONFLUENT_CA_ANNOTATION \
        VAR_CONFLUENT_TOPIC_PARTITIONS VAR_CONFLUENT_TOPIC_REPLICAS VAR_CONFLUENT_TOPIC_CLEANUP_POLICY

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# run all customisation steps for Confluent
function confluent_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  SECONDS=0
  local lf_starting_date=$(date)

  check_directory_exist_create "${MY_CONFLUENT_WORKINGDIR}"

  # Ensure namespace exists (idempotent — already created by install_confluent)
  create_project "${VAR_CONFLUENT_NAMESPACE}" \
    "${VAR_CONFLUENT_NAMESPACE} project" \
    "For Confluent customisation" \
    "${MY_RESOURCESDIR}" "${MY_CONFLUENT_WORKINGDIR}"

  # Deploy operands (KRaftController, Kafka, KafkaTopic)
  create_confluent_operands

  # Grant monitoring permissions
  grant_kafka_monitoring

  # Create additional demo topics
  create_kafka_topics

  # Create Kafka users
  create_kafka_users

  # Create connectors (requires MQ — guarded inside the function)
  # create_kafka_connector

  local lf_ending_date=$(date)
  mylog info "==== Customisation of confluent [ended : $lf_ending_date and took : $SECONDS seconds]." 0

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}


################################################
# initialisation
function confluent_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ${FUNCNAME[0]}

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
    --all) confluent_run_all "$@";;
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

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/confluent.properties"
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

confluent_init

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi