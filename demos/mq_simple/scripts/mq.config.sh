#!/bin/bash
################################################
# Script using cert manager
################################################

################################################
function create_mq_root_certificate () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  export VAR_CERT_NAME=${VAR_MQ_NAMESPACE}-mq-root
  export VAR_NAMESPACE=${VAR_MQ_NAMESPACE}
  export VAR_CERT_ISSUER_REF="${VAR_MQ_NAMESPACE}-mq-self-signed"
  export VAR_CERT_SECRET_NAME=${VAR_CERT_NAME}-secret
  export VAR_CERT_COMMON_NAME=${VAR_CERT_NAME}
  export VAR_CERT_ORGANISATION=${MY_CERT_ORGANISATION}
  export VAR_CERT_COUNTRY=${MY_CERT_COUNTRY}
  export VAR_CERT_LOCALITY=${MY_CERT_LOCALITY}
  export VAR_CERT_STATE=${MY_CERT_STATE}
  export VAR_CERT_JKS_SECRET_REF=${VAR_MQ_NAMESPACE}-mq-store-root-secret
  # export VAR_CERT_SERIAL=$(uuidgen)

  # We are using a secure QM, we want to expose the jks in the secret asociated to the root certificate. Since this is secured we are going to create a secret for the password with the TLS certificate of the queue manager
  # TODO Need to check what is happening when the certificate is regenerated maybe automatically by Cert Manager
  local lf_jks_secret_name="${VAR_MQ_NAMESPACE}-mq-store-root-secret"

  if check_resource_exist secret $lf_jks_secret_name $VAR_ES_NAMESPACE false; then
    mylog info "Secret $lf_jks_secret_name in ${VAR_ES_NAMESPACE} namespace already exists." 1>&2
    local lf_store_password=$(oc -n "${VAR_ES_NAMESPACE}" get secret "$lf_jks_secret_name" -o jsonpath='{.data.password}' | base64 --decode)
    export VAR_ES_MQ_SOURCE_STORE_PASSWORD=${lf_store_password}
  else
    mylog info "Secret $lf_jks_secret_name in ${VAR_ES_NAMESPACE} namespace does not exist." 1>&2
    local lf_store_password=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | fold -w 20 | head -n 1)
    create_generic_secret "$lf_jks_secret_name" "" "$lf_store_password" "${VAR_ES_NAMESPACE}" "${MY_ES_WORKINGDIR}"
    export VAR_ES_MQ_SOURCE_STORE_PASSWORD=${lf_store_password}
  fi

  create_oc_resource "Certificate" "${VAR_CERT_NAME}" "${MY_YAMLDIR}tls/" "${MY_MQ_WORKINGDIR}" "ca_certificate_jks.yaml" "${VAR_MQ_NAMESPACE}"
  wait_for_resource "Secret" "${VAR_CERT_SECRET_NAME}" "${VAR_MQ_NAMESPACE}"

  unset VAR_CERT_NAME VAR_NAMESPACE VAR_CERT_ISSUER_REF VAR_CERT_COMMON_NAME VAR_CERT_ORGANISATION VAR_CERT_COUNTRY VAR_CERT_LOCALITY VAR_CERT_STATE VAR_CERT_JKS_SECRET_REF

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
function create_leaf_certificate () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # get the dns name of the cluster
  local lf_cluster_domain=$($MY_CLUSTER_COMMAND get dns cluster -o jsonpath='{.spec.baseDomain}')
  
  export VAR_CERT_NAME=${VAR_MQ_NAMESPACE}-mq-${VAR_QMGR_LC}-server
  export VAR_NAMESPACE=${VAR_MQ_NAMESPACE}
  export VAR_CERT_COMMON_NAME=${VAR_CERT_NAME}
  export VAR_CERT_SAN_DNS_1="*.${lf_cluster_domain}"
  export VAR_CERT_SAN_DNS_2="${VAR_QMGR_LC}-ibm-mq.${VAR_MQ_NAMESPACE}.svc.cluster.local"
  export VAR_CERT_ISSUER_REF=${VAR_MQ_NAMESPACE}-mq-${VAR_QMGR_LC}-int-issuer
  export VAR_CERT_ORGANISATION=${MY_CERT_ORGANISATION}
  export VAR_CERT_COUNTRY=${MY_CERT_COUNTRY}
  export VAR_CERT_LOCALITY=${MY_CERT_LOCALITY}
  export VAR_CERT_STATE=${MY_CERT_STATE}
  # export VAR_CERT_SERIAL=$(uuidgen)

  create_oc_resource "Certificate" "${VAR_CERT_NAME}" "${MY_YAMLDIR}tls/" "${MY_MQ_WORKINGDIR}" "server_certificate.yaml" "${VAR_MQ_NAMESPACE}"

  unset VAR_CERT_NAME VAR_NAMESPACE VAR_CERT_COMMON_NAME VAR_CERT_SAN_DNS_1 VAR_CERT_SAN_DNS_2 VAR_CERT_ISSUER_REF VAR_CERT_ORGANISATION VAR_CERT_COUNTRY VAR_CERT_LOCALITY VAR_CERT_STATE
  
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
function create_qmgr_route () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  create_oc_resource "Route" "${VAR_QMGR_LC}-route" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}" "qmgr_route.yaml" "$VAR_MQ_NAMESPACE"

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create Queue Manager
# param 1: Queue Manager name
# param 2: TODO add the channel name for applications as parameter
# param 3..n: Queues names
function create_qmgr () {
  local lf_tracelevel=3
  
  trace_in $lf_tracelevel ${FUNCNAME[0]}
  local lf_qm_defs=("$@")

  export VAR_QMGR=${lf_qm_defs[0]}
  # for SNI to be check
  export VAR_QMGR_UC=$(echo $VAR_QMGR | tr '[:lower:]' '[:upper:]')
  export VAR_QMGR_LC=$(echo $VAR_QMGR | tr '[:upper:]' '[:lower:]')
  export VAR_INI_CM="${VAR_QMGR_LC}-ini-cm"
  export VAR_MQSC_OBJECTS_CM="${VAR_QMGR_LC}-mqsc-cm"
  export VAR_AUTH_CM="${VAR_QMGR_LC}-auth-cm"
  export VAR_WEBCONFIG_CM="${VAR_QMGR_LC}-webconfig-cm"

  mkdir -p ${MY_MQ_WORKINGDIR}${VAR_QMGR}
  
  mylog info "Creating Queue Manager: ${VAR_QMGR} in namespace: ${VAR_MQ_NAMESPACE}"

  create_intermediate_issuer "${VAR_MQ_NAMESPACE}-mq-${VAR_QMGR_LC}-int-issuer" "${VAR_MQ_NAMESPACE}-mq-root-secret" "${MY_MQ_WORKINGDIR}" "${VAR_MQ_NAMESPACE}"
  create_leaf_certificate

  # Copy the template to add the missing lines
  mkdir -p "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/"
  cp -f "${MY_MQ_SIMPLE_DEMODIR}tmpl/qmgr_cm_mqsc.yaml" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/."
  cp -f "${MY_MQ_SIMPLE_DEMODIR}tmpl/qmgr_cm_mqsc_auth.yaml" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/."

  for ((i=1; i<${#lf_qm_defs[@]}; i++)); do
    # For each Queue update the template file for the queues definitions and authentication definitions will be generated in working directory
    # If ends by CPY then it is a streaming queue
    # TODO Improve authentication instead of user default user and impact with certificate usage
    if [[ "${lf_qm_defs[$i]}" == *CPY ]]; then
      mylog info "Adding Queue ${lf_qm_defs[$i]} and streaming queue definitions."
      lf_qn=${lf_qm_defs[$i]%".CPY"}
      appendToFile 4 "DEFINE QLOCAL('${lf_qm_defs[$i]}')" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/qmgr_cm_mqsc.yaml"
      appendToFile 4 "DEFINE QLOCAL('${lf_qn}') STREAMQ('${lf_qm_defs[$i]}') REPLACE DEFPSIST(YES)" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/qmgr_cm_mqsc.yaml"
      appendToFile 4 "SET AUTHREC PROFILE('${lf_qn}') PRINCIPAL('${VAR_MQ_USER}') OBJTYPE(QUEUE) AUTHADD(BROWSE,GET,INQ,PUT,DSP)" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/qmgr_cm_mqsc_auth.yaml"
      appendToFile 4 "SET AUTHREC PROFILE('${lf_qm_defs[$i]}') PRINCIPAL('${VAR_MQ_USER}') OBJTYPE(QUEUE) AUTHADD(BROWSE,GET,INQ,PUT,DSP)" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/qmgr_cm_mqsc_auth.yaml"
    else
      mylog info "Adding Queue ${lf_qm_defs[$i]} definitions."
      appendToFile 4 "DEFINE QLOCAL('${lf_qm_defs[$i]}') REPLACE DEFPSIST(YES)" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/qmgr_cm_mqsc.yaml"
      appendToFile 4 "SET AUTHREC PROFILE('${lf_qm_defs[$i]}') PRINCIPAL('${VAR_MQ_USER}') OBJTYPE(QUEUE) AUTHADD(BROWSE,GET,INQ,PUT,DSP)" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/qmgr_cm_mqsc_auth.yaml"
    fi
  done
  # Create QM config maps
  create_oc_resource "ConfigMap" "${VAR_INI_CM}" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/" "qmgr_cm_ini.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "${VAR_MQSC_OBJECTS_CM}" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/" "qmgr_cm_mqsc.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "${VAR_AUTH_CM}" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/tmp/" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/" "qmgr_cm_mqsc_auth.yaml" "$VAR_MQ_NAMESPACE"
  create_oc_resource "ConfigMap" "${VAR_WEBCONFIG_CM}" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/" "qmgr_cm_web.yaml" "$VAR_MQ_NAMESPACE"
  
  # At this stage VAR_QMGR_LC is exported
  create_qmgr_route
  
  # Use the new CRD MessagingServer (available since CP4I 16.1.0-SC2)
  if $MY_MESSAGINGSERVER; then
    # Creating MQ MessagingServer instance
    create_operand_instance "MessagingServer" "${VAR_MSGSRV_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/" "MessagingServer-Capability.yaml" "$VAR_MQ_NAMESPACE" "{.status.conditions[0].type}" "Ready"
  else 
    create_operand_instance "QueueManager" "${VAR_QMGR_LC}" "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}${VAR_QMGR}/" "qmgr.yaml" "$VAR_MQ_NAMESPACE" "{.status.phase}" "Running"
  fi

  unset VAR_QMGR VAR_QMGR_UC VAR_INI_CM VAR_MQSC_OBJECTS_CM VAR_AUTH_CM VAR_WEBCONFIG_CM
  
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create client key repository
# param 1: Queue Manager name
################################################
function create_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_in_qmgr=$1

  local lf_clnt_workingdir="${MY_MQ_WORKINGDIR}${lf_in_qmgr}/${VAR_CLNT1}/"
  check_directory_exist_create  "$lf_clnt_workingdir"
  mylog "info" "Creating empty client key database for $VAR_CLNT1 to use with MQSSLKEYR env variable in ${lf_clnt_workingdir} directory."

  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${lf_clnt_workingdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${lf_clnt_workingdir}${VAR_CLNT1}-keystore.p12";;
  esac  

  # Create the empty client1 key database (password is hard coded for now):
  runmqakm -keydb -create -db $lf_clnt_keydb -pw password -type $VAR_KEYDB_TYPE -stash > /dev/null 2>&1  

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create pki infrastructure : keys, certs, kdb, ....
# param 1: Queue Manager name
################################################
function create_pki_cr () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_in_qmgr=$1

  ##-- Get the private/cert/ca for the Issuer cs-ca-issuer 
  #mylog "info" "Getting   : certificate and key for CA"
  #get_issuer_tls_resources

  ##-- Create the client key database 
  mylog "info" "Creating client key database for $VAR_CLNT1 to use with MQSSLKEYR env variable."
  create_clnt_kdb $lf_in_qmgr
  
  ##-- Add the queue manager's certificate to the client key database:
  mylog "info" "Adding root and leaf certificates to the client key database"
  add_qmgr_crt_2_clnt_kdb $lf_in_qmgr
  
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Add certs to client keydb
  # param 1: Queue Manager name
################################################
function add_qmgr_crt_2_clnt_kdb () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  local lf_in_qmgr=$1
  local lf_in_qmgr_lc=$(echo $lf_in_qmgr | tr '[:upper:]' '[:lower:]')

  local lf_clnt_workingdir="${MY_MQ_WORKINGDIR}${lf_in_qmgr}/${VAR_CLNT1}/"
  local root_cert_secret_name=${VAR_MQ_NAMESPACE}-mq-root-secret
  local leaf_cert_secret_name=${VAR_MQ_NAMESPACE}-mq-${lf_in_qmgr_lc}-server-secret

  mylog "info" "Adding the QMGR certificates to the client key database"
  # For the self-signed certificate the root (ca.crt) and server (tls.crt) are the same
  save_certificate ${root_cert_secret_name} ca.crt ${lf_clnt_workingdir} $VAR_MQ_NAMESPACE
  # Leaf certificate <ns>-mq-<qmgr>-server-secret, the ca.crt is from the root (equals), we could have used it.
  save_certificate ${leaf_cert_secret_name} tls.crt ${lf_clnt_workingdir} $VAR_MQ_NAMESPACE

  # The name is derived from the secret name
  local lf_ca_crt="${lf_clnt_workingdir}${root_cert_secret_name}.ca.crt.pem"
  local lf_server_crt="${lf_clnt_workingdir}${leaf_cert_secret_name}.tls.crt.pem"
    
  case $VAR_KEYDB_TYPE in
    cms)  local lf_clnt_keydb="${lf_clnt_workingdir}${VAR_CLNT1}-keystore.kdb";;
    pkcs12) local lf_clnt_keydb="${lf_clnt_workingdir}${VAR_CLNT1}-keystore.p12";;
  esac

  # Order is important, root at the end (to be checked)
  decho $lf_tracelevel "runmqakm -cert -add -db $lf_clnt_keydb -label mq-leaf-server -file $lf_server_crt -format ascii -stashed"
  runmqakm -cert -add -db $lf_clnt_keydb -label mq-leaf-server -file $lf_server_crt -format ascii -stashed > /dev/null 2>&1
  decho $lf_tracelevel "runmqakm -cert -add -db $lf_clnt_keydb -label mq-root-ca -file $lf_ca_crt -format ascii -stashed"
	runmqakm -cert -add -db $lf_clnt_keydb -label mq-root-ca -file $lf_ca_crt -format ascii -stashed > /dev/null 2>&1

  # Check. List the database certificates:
  mylog "info" "listing certificates in keydb : $lf_clnt_keydb"
  decho $lf_tracelevel "runmqakm -cert -list -db $lf_clnt_keydb -stashed"
  runmqakm -cert -list -db $lf_clnt_keydb -stashed #> /dev/null 2>&1

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create Openshift CCDT file
# param 1: Queue Manager name
################################################
function create_ccdt () {
  local lf_tracelevel=5
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument:the queue manager name"
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    exit  1
  fi

  local lf_in_qmgr=$1
  local lf_in_qmgr_uc=$(echo $lf_in_qmgr | tr '[:lower:]' '[:upper:]')
  local lf_in_qmgr_lc=$(echo $lf_in_qmgr | tr '[:upper:]' '[:lower:]')

  # CCDT template file
  local sc_ccdt_tmpl_file="${MY_MQ_SIMPLE_DEMODIR}tmpl/ccdt.json";
 
  # Generate ccdt file
  export MQCCDTURL="${MY_MQ_WORKINGDIR}${lf_in_qmgr}/ccdt.json"
  export ROOTURL=$($MY_CLUSTER_COMMAND get route -n $VAR_MQ_NAMESPACE "${lf_in_qmgr_lc}-ibm-mq-qm" -o jsonpath='{.spec.host}')
  export VAR_QMGR=$lf_in_qmgr
  export VAR_CHL_UC="${lf_in_qmgr_uc}CHL"

  mylog "info" "Creating ccdt file for Queue Manager ${lf_in_qmgr} to use with MQCCDTURL env variabe. Located here : $MQCCDTURL"
  decho $lf_tracelevel "$MY_CLUSTER_COMMAND get route -n $VAR_MQ_NAMESPACE \"${lf_in_qmgr}-ibm-mq-qm\" -o jsonpath='{.spec.host}'"
  decho $lf_tracelevel "VAR_CHL_UC=$VAR_CHL_UC|lf_in_qmgr=$VAR_QMGR_UC|ROOTURL=$ROOTURL"

  adapt_file "${MY_MQ_SIMPLE_DEMODIR}tmpl/" "${MY_MQ_WORKINGDIR}${lf_in_qmgr}/" ccdt.json

  mylog "warn" "To use the amqsput client, you need to ensure that the file /var/mqm/mqclient.ini contains entry OutboundSNI=HOSTNAME under SSL. It is required to avoid the TLS handshake to occur with the Ingress server."
  mylog "info" "To use amqsput use the following command: export MQCCDTURL=${MQCCDTURL}, then export MQSSLKEYR=${MY_MQ_WORKINGDIR}${lf_in_qmgr}/${VAR_CLNT1}-keystore.p12 (or .kdb depending on the type of key database you have created), then run the command: amqsputc PAYMT.REQ Orders"

  unset VAR_QMGR_UC VAR_CHL_UC ROOTURL

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Run this script natively (from terminal)
################################################
function mq_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}
  
  # Create tls artifacts for all QMs in the project
  create_self_signed_issuer "${VAR_MQ_NAMESPACE}-mq-self-signed" "${VAR_MQ_NAMESPACE}" "${MY_MQ_WORKINGDIR}"

  create_mq_root_certificate

  create_qmgr "Orders" "PAYMT.RESP" "PAYMT.REQ.CPY"
  create_pki_cr "Orders"
  create_ccdt "Orders"

  create_qmgr "Sensors" "WEATHER.PAR"
  create_pki_cr "Sensors"
  create_ccdt "Sensors"

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# initialisation
function mq_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # Create namespace 
  create_project "$VAR_MQ_NAMESPACE" "$VAR_MQ_NAMESPACE project" "For MQ" "${MY_RESOURCESDIR}" "${MY_MQ_WORKINGDIR}"
  add_ibm_entitlement "$VAR_MQ_NAMESPACE"

  check_directory_exist_create  "${MY_MQ_WORKINGDIR}"
  
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# main function
# Main logic
function main() {
  local lf_tracelevel=1
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
  lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces

  # Call processing function if --call was used
  case $lf_key in
    --all) mq_run_all "$@";;
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
# other example: ./mq.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./mq.config.sh --all
################################################

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
sc_component_properties_file="${sc_component_script_dir}../properties/mq.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a par ce que à cet instant je n'ai pas accès à la fonction read_config_file
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

export MY_MQ_WORKINGDIR="${PROVISION_SCRIPTDIR}working/demos/mq_simple/"

mq_init

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi