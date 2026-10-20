#!/bin/bash
################################################
# IBM MQ stand-alone Web Server (MQ Console) on OpenShift
# - builds an image from the stand-alone MQ Web Server tarball (Fix Central)
# - deploys it (PVC, Deployment, Service, passthrough Route)
# - add_qmgr_to_mqweb registers a queue manager of the MQ Operator in the console (channel, certificates, CCDT)
#   ex: ./mqweb.config.sh --call add_qmgr_to_mqweb orders iwhi-mq
#   (VAR_MQWEB_QMGRS lists queue managers to register during --all)
# Prerequisite: the MQ Web Server tarball in Src/ (VAR_MQWEB_ARCHIVE)
################################################

################################################
# Create the secret with the console users and truststore passwords (kept if it already exists)
function create_mqweb_credentials () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  if check_resource_exist secret "${VAR_MQWEB_CREDENTIALS_SECRET}" "${VAR_MQWEB_NAMESPACE}" false; then
    mylog info "Secret ${VAR_MQWEB_CREDENTIALS_SECRET} already exists in ${VAR_MQWEB_NAMESPACE}, keeping the existing passwords." 1>&2
  else
    generate_password 16
    local lf_admin_pwd=$VAR_USER_PASSWORD_GEN
    generate_password 16
    local lf_reader_pwd=$VAR_USER_PASSWORD_GEN
    generate_password 20
    local lf_truststore_pwd=$VAR_USER_PASSWORD_GEN
    unset VAR_USER_PASSWORD_GEN

    mylog info "Creating secret ${VAR_MQWEB_CREDENTIALS_SECRET} in ${VAR_MQWEB_NAMESPACE}"
    if $MY_APPLY_FLAG; then
      $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" create secret generic "${VAR_MQWEB_CREDENTIALS_SECRET}" \
        --from-literal=MQWEB_ADMIN_PWD="${lf_admin_pwd}" \
        --from-literal=MQWEB_READER_PWD="${lf_reader_pwd}" \
        --from-literal=MQWEB_TRUSTSTORE_PWD="${lf_truststore_pwd}" || exit 1
    fi
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create the console channel and its authorities on a queue manager
# The console connects as an MQ client through a dedicated SVRCONN channel mapped to ${VAR_MQWEB_MCAUSER}
# param 1: QueueManager resource name
# param 2: namespace of the queue manager
# param 3: MQ queue manager name
# param 4: true if the queue manager has TLS keys (TLS channel), false otherwise
function configure_qmgr_for_mqweb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  if [[ $# -ne 4 ]]; then
    mylog error "You have to provide 4 arguments: QueueManager resource name, namespace, queue manager name and tls (true|false)"
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    exit 1
  fi

  local lf_in_qmgr_cr=$1
  local lf_in_namespace=$2
  local lf_in_qmgr=$3
  local lf_in_tls=$4

  # Active (ready) pod of the queue manager, works for SingleInstance and NativeHA
  local lf_pod=$($MY_CLUSTER_COMMAND -n "${lf_in_namespace}" get pod -l app.kubernetes.io/instance=${lf_in_qmgr_cr} \
    -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -1)
  if [[ -z $lf_pod ]]; then
    mylog error "No ready pod found for queue manager ${lf_in_qmgr_cr} in ${lf_in_namespace}."
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    exit 1
  fi

  local lf_ssl=""
  if $lf_in_tls; then
    lf_ssl="SSLCIPH('ANY_TLS12_OR_HIGHER') SSLCAUTH(OPTIONAL)"
  fi

  local lf_mqsc="DEFINE CHANNEL('${VAR_MQWEB_CHL}') CHLTYPE(SVRCONN) TRPTYPE(TCP) ${lf_ssl} REPLACE
SET CHLAUTH('${VAR_MQWEB_CHL}') TYPE(ADDRESSMAP) ADDRESS('*') USERSRC(MAP) MCAUSER('${VAR_MQWEB_MCAUSER}') ACTION(REPLACE)
SET AUTHREC OBJTYPE(QMGR) PRINCIPAL('${VAR_MQWEB_MCAUSER}') AUTHADD(ALL)"
  local lf_objtype
  for lf_objtype in QUEUE TOPIC CHANNEL CLNTCONN PROCESS NAMELIST AUTHINFO LISTENER SERVICE COMMINFO; do
    lf_mqsc+="
SET AUTHREC PROFILE('**') OBJTYPE(${lf_objtype}) PRINCIPAL('${VAR_MQWEB_MCAUSER}') AUTHADD(ALL)"
  done
  # The messaging REST API asserts the console user (alternate user authority): grant the console users on the queues
  lf_mqsc+="
SET AUTHREC OBJTYPE(QMGR) PRINCIPAL('${VAR_MQWEB_ADMIN_USER}') AUTHADD(CONNECT,INQ,DSP)
SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) PRINCIPAL('${VAR_MQWEB_ADMIN_USER}') AUTHADD(ALL)
SET AUTHREC OBJTYPE(QMGR) PRINCIPAL('${VAR_MQWEB_READER_USER}') AUTHADD(CONNECT,INQ,DSP)
SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) PRINCIPAL('${VAR_MQWEB_READER_USER}') AUTHADD(BROWSE,INQ,DSP)"

  mylog info "Creating channel ${VAR_MQWEB_CHL} and authorities for ${VAR_MQWEB_MCAUSER} on queue manager ${lf_in_qmgr} (pod ${lf_pod})"
  decho $lf_tracelevel "$lf_mqsc"
  if $MY_APPLY_FLAG; then
    echo "$lf_mqsc" | $MY_CLUSTER_COMMAND -n "${lf_in_namespace}" exec -i "${lf_pod}" -c qmgr -- runmqsc "${lf_in_qmgr}" > /dev/null || exit 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Add a queue manager deployed by the MQ Operator to the stand-alone console
# - creates the console channel and its authorities on the queue manager
# - adds its certificates to ${VAR_MQWEB_CERTS_SECRET} (imported in the console truststore)
# - adds its CCDT to ${VAR_MQWEB_CCDT_CM} (key <queue manager name>.json), pointing to its internal service
# - restarts the console, which (re)registers every CCDT at startup
# The MQ queue manager name and its TLS secret are read from the QueueManager resource.
# param 1: QueueManager resource name, ex: orders
# param 2: namespace of the queue manager (optional, default ${VAR_MQ_NAMESPACE})
# param 3: restart the console (optional, true|false, default true)
# example: ./mqweb.config.sh --call add_qmgr_to_mqweb orders iwhi-mq
function add_qmgr_to_mqweb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -lt 1 ]] || [[ $# -gt 3 ]]; then
    mylog error "Usage: add_qmgr_to_mqweb <QueueManager resource name> [namespace, default ${VAR_MQ_NAMESPACE}] [restart console: true|false, default true]"
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    exit 1
  fi

  local lf_in_qmgr_cr=$1
  local lf_in_namespace=${2:-$VAR_MQ_NAMESPACE}
  local lf_in_restart=${3:-true}

  check_resource_exist QueueManager "${lf_in_qmgr_cr}" "${lf_in_namespace}" true

  local lf_qmgr=$($MY_CLUSTER_COMMAND -n "${lf_in_namespace}" get QueueManager "${lf_in_qmgr_cr}" -o jsonpath='{.spec.queueManager.name}')
  local lf_pki_secret=$($MY_CLUSTER_COMMAND -n "${lf_in_namespace}" get QueueManager "${lf_in_qmgr_cr}" -o jsonpath='{.spec.pki.keys[0].secret.secretName}')
  local lf_tls=false
  [[ -n $lf_pki_secret ]] && lf_tls=true
  mylog info "Adding queue manager ${lf_qmgr} (QueueManager ${lf_in_namespace}/${lf_in_qmgr_cr}, tls: ${lf_tls}) to the MQ stand-alone console" 0

  # 1. Console channel on the queue manager
  configure_qmgr_for_mqweb "${lf_in_qmgr_cr}" "${lf_in_namespace}" "${lf_qmgr}" ${lf_tls}

  # 2. Certificates of the queue manager (CA and leaf, the chain is not always sent completely)
  local lf_item lf_b64 lf_data='{}'
  if $lf_tls; then
    for lf_item in ca.crt tls.crt; do
      lf_b64=$($MY_CLUSTER_COMMAND -n "${lf_in_namespace}" get secret "${lf_pki_secret}" -o jsonpath="{.data.${lf_item//./\\.}}")
      if [[ -n $lf_b64 ]]; then
        lf_data=$(jq -c --arg k "${lf_in_namespace}.${lf_in_qmgr_cr}.${lf_item%.crt}.pem" --arg v "$lf_b64" '.[$k]=$v' <<< "$lf_data")
      fi
    done
    mylog info "Adding the certificates of ${lf_pki_secret} to secret ${VAR_MQWEB_CERTS_SECRET}"
    if $MY_APPLY_FLAG; then
      if ! check_resource_exist secret "${VAR_MQWEB_CERTS_SECRET}" "${VAR_MQWEB_NAMESPACE}" false; then
        $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" create secret generic "${VAR_MQWEB_CERTS_SECRET}" || exit 1
      fi
      $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" patch secret "${VAR_MQWEB_CERTS_SECRET}" --type merge -p "{\"data\":${lf_data}}" || exit 1
    fi
  fi

  # 3. CCDT, the console reaches the queue manager through its internal service (no SNI route involved)
  local lf_ccdt_dir="${MY_MQWEB_WORKINGDIR}ccdt/${lf_in_namespace}/${lf_in_qmgr_cr}/"
  export VAR_QMGR="${lf_qmgr}"
  export VAR_QMGR_HOST="${lf_in_qmgr_cr}-ibm-mq.${lf_in_namespace}.svc.cluster.local"
  adapt_file "${MY_MQWEB_DEMODIR}tmpl/" "${lf_ccdt_dir}" ccdt.json
  unset VAR_QMGR VAR_QMGR_HOST
  if ! $lf_tls; then
    jq 'del(.channel[].transmissionSecurity)' "${lf_ccdt_dir}ccdt.json" > "${lf_ccdt_dir}ccdt.json.tmp" && mv "${lf_ccdt_dir}ccdt.json.tmp" "${lf_ccdt_dir}ccdt.json"
  fi

  # The key is the queue manager name: the entrypoint uses it as unique name in the console
  mylog info "Adding ${lf_qmgr}.json to ConfigMap ${VAR_MQWEB_CCDT_CM}"
  if $MY_APPLY_FLAG; then
    if ! check_resource_exist configmap "${VAR_MQWEB_CCDT_CM}" "${VAR_MQWEB_NAMESPACE}" false; then
      $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" create configmap "${VAR_MQWEB_CCDT_CM}" || exit 1
    fi
    lf_data=$(jq -c -n --arg k "${lf_qmgr}.json" --rawfile v "${lf_ccdt_dir}ccdt.json" '{data: {($k): $v}}')
    $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" patch configmap "${VAR_MQWEB_CCDT_CM}" --type merge -p "${lf_data}" || exit 1
  fi

  # 4. Restart the console to rebuild the truststore and register the queue manager
  if $lf_in_restart && $MY_APPLY_FLAG && check_resource_exist deployment "${VAR_MQWEB_APP_NAME}" "${VAR_MQWEB_NAMESPACE}" false; then
    mylog info "Restarting deployment ${VAR_MQWEB_APP_NAME} to register ${lf_qmgr}"
    $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" rollout restart deployment/"${VAR_MQWEB_APP_NAME}"
    $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" rollout status deployment/"${VAR_MQWEB_APP_NAME}" --timeout=600s || exit 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}


################################################
# Create the ConfigMap with the console security configuration (mqwebuser.xml)
function create_mqweb_config () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  adapt_file "${MY_MQWEB_DEMODIR}tmpl/" "${MY_MQWEB_WORKINGDIR}" mqwebuser.xml

  mylog info "Creating/Updating ConfigMap ${VAR_MQWEB_CONFIG_CM} in ${VAR_MQWEB_NAMESPACE}"
  if $MY_APPLY_FLAG; then
    $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" create configmap "${VAR_MQWEB_CONFIG_CM}" \
      --from-file=mqwebuser.xml="${MY_MQWEB_WORKINGDIR}mqwebuser.xml" \
      --dry-run=client -o yaml | $MY_CLUSTER_COMMAND apply -f - || exit 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Build the mqweb image in the cluster (BuildConfig docker strategy, binary source)
function build_mqweb_image () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  if [[ ! -f "${VAR_MQWEB_ARCHIVE}" ]]; then
    mylog error "MQ Web Server tarball not found: ${VAR_MQWEB_ARCHIVE}. Download it from Fix Central into ${VAR_MQWEB_SRC_DIR} (file name set in VAR_MQWEB_ARCHIVE, ${sc_component_properties_file})."
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    exit 1
  fi

  # Build context: Containerfile + entrypoint + tarball
  local lf_build_dir="${MY_MQWEB_WORKINGDIR}build/"
  check_directory_exist_create "${lf_build_dir}"
  cp -f "${MY_MQWEB_DEMODIR}build/Containerfile" "${MY_MQWEB_DEMODIR}build/entrypoint.sh" "${lf_build_dir}"
  cp -f "${VAR_MQWEB_ARCHIVE}" "${lf_build_dir}mqweb.tar.gz"

  create_oc_resource "BuildConfig" "${VAR_MQWEB_APP_NAME}" "${MY_MQWEB_DEMODIR}tmpl/" "${MY_MQWEB_WORKINGDIR}" "mqweb_build.yaml" "${VAR_MQWEB_NAMESPACE}"

  mylog info "Building image ${VAR_MQWEB_IMAGE} (this takes a few minutes)"
  if $MY_APPLY_FLAG; then
    $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" start-build "${VAR_MQWEB_APP_NAME}" --from-dir="${lf_build_dir}" --follow --wait || exit 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Deploy the mqweb server: PVC, Deployment, Service, Route
function deploy_mqweb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_existing=false
  if check_resource_exist deployment "${VAR_MQWEB_APP_NAME}" "${VAR_MQWEB_NAMESPACE}" false; then
    lf_existing=true
  fi

  create_oc_resource "PersistentVolumeClaim" "${VAR_MQWEB_APP_NAME}-data" "${MY_MQWEB_DEMODIR}tmpl/" "${MY_MQWEB_WORKINGDIR}" "mqweb_pvc.yaml" "${VAR_MQWEB_NAMESPACE}"
  create_oc_resource "Deployment" "${VAR_MQWEB_APP_NAME}" "${MY_MQWEB_DEMODIR}tmpl/" "${MY_MQWEB_WORKINGDIR}" "mqweb_deployment.yaml" "${VAR_MQWEB_NAMESPACE}"
  create_oc_resource "Service" "${VAR_MQWEB_APP_NAME}" "${MY_MQWEB_DEMODIR}tmpl/" "${MY_MQWEB_WORKINGDIR}" "mqweb_service.yaml" "${VAR_MQWEB_NAMESPACE}"
  create_oc_resource "Route" "${VAR_MQWEB_APP_NAME}" "${MY_MQWEB_DEMODIR}tmpl/" "${MY_MQWEB_WORKINGDIR}" "mqweb_route.yaml" "${VAR_MQWEB_NAMESPACE}"

  if $MY_APPLY_FLAG; then
    # Config, certs, CCDT and image are read at container start: restart to pick up changes on re-runs
    if $lf_existing; then
      mylog info "Restarting deployment ${VAR_MQWEB_APP_NAME} to pick up the new configuration"
      $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" rollout restart deployment/"${VAR_MQWEB_APP_NAME}"
    fi
    $MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" rollout status deployment/"${VAR_MQWEB_APP_NAME}" --timeout=600s || exit 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Display the console URL and credentials
function display_mqweb_access () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_host=$($MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" get route "${VAR_MQWEB_APP_NAME}" -o jsonpath='{.spec.host}')
  local lf_admin_pwd=$($MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" get secret "${VAR_MQWEB_CREDENTIALS_SECRET}" -o jsonpath='{.data.MQWEB_ADMIN_PWD}' | base64 --decode)
  local lf_reader_pwd=$($MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" get secret "${VAR_MQWEB_CREDENTIALS_SECRET}" -o jsonpath='{.data.MQWEB_READER_PWD}' | base64 --decode)

  mylog info "MQ stand-alone console: https://${lf_host}/ibmmq/console/" 0
  mylog info "  admin     : ${VAR_MQWEB_ADMIN_USER} / ${lf_admin_pwd}" 0
  mylog info "  read-only : ${VAR_MQWEB_READER_USER} / ${lf_reader_pwd}" 0
  local lf_qmgrs=$($MY_CLUSTER_COMMAND -n "${VAR_MQWEB_NAMESPACE}" get configmap "${VAR_MQWEB_CCDT_CM}" -o json 2>/dev/null | jq -r '(.data // {}) | keys[] | sub("\\.json$"; "")' | tr '\n' ' ')
  [[ -n "${lf_qmgrs// /}" ]] && mylog info "  remote queue managers: ${lf_qmgrs}" 0

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Run this script natively (from terminal)
################################################
function mqweb_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installation of the MQ stand-alone web console [started : $lf_starting_date]." 0

  create_mqweb_credentials

  # Optional: pre-register remote queue managers (the console itself does not need any)
  # No restart here, deploy_mqweb (re)starts the console afterwards
  if [[ -n "${VAR_MQWEB_QMGRS// /}" ]]; then
    local lf_qmgr_cr
    for lf_qmgr_cr in ${VAR_MQWEB_QMGRS}; do
      add_qmgr_to_mqweb "${lf_qmgr_cr}" "${VAR_MQ_NAMESPACE}" false
    done
  else
    mylog info "No queue manager to pre-register (VAR_MQWEB_QMGRS is empty), installing the console alone." 0
  fi

  create_mqweb_config
  build_mqweb_image
  deploy_mqweb
  display_mqweb_access

  local lf_ending_date=$(date)
  mylog info "==== Installation of the MQ stand-alone web console [ended : $lf_ending_date and took : $SECONDS seconds]." 0

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# initialisation
function mqweb_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  check_directory_exist_create "${MY_MQWEB_WORKINGDIR}"

  # Create namespace
  create_project "$VAR_MQWEB_NAMESPACE" "$VAR_MQWEB_NAMESPACE project" "For MQ stand-alone web console" "${MY_RESOURCESDIR}" "${MY_MQWEB_WORKINGDIR}"

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
  lf_calls=$(echo "$lf_calls" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')

  # Call processing function if --call was used
  case $lf_key in
    --all) mqweb_run_all "$@";;
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
# example: ./mqweb.config.sh --all
# example: ./mqweb.config.sh --call configure_qmgr_for_mqweb Orders, deploy_mqweb
################################################

# the following script returns the absolute path of this script independently from using it directly or calling it from another script
sc_component_script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/mqweb.properties"

# load the properties files (set -a to export everything for envsubst)
set -a
. "${sc_provision_script_parameters_file}"
. "${sc_provision_constant_properties_file}"
. "${sc_provision_variable_properties_file}"
. "${sc_component_properties_file}"
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

export MY_MQWEB_DEMODIR="$( cd "${sc_component_script_dir}../" && pwd )/"
export MY_MQWEB_WORKINGDIR="${PROVISION_SCRIPTDIR}working/demos/ibm_mq_standalone_webconsole/"

mqweb_init

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
