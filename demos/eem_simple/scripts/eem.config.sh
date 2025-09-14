
#######################################################################################################DEBUT
# run all
function eem_run_all () {
  	local lf_tracelevel=3
		trace_in $lf_tracelevel eem_run_all

  SECONDS=0
  local lf_starting_date=$(date);
  
  # Instruction to create the event gateway in APIC
  # Documentation: https://ibm.github.io/event-automation/eem/integrating-with-apic/configure-eem-for-apic/
  
  decho $lf_tracelevel "$MY_CLUSTER_COMMAND -n $VAR_APIC_NAMESPACE get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="jwksUrl")].uri}'"
  lf_jwks_url=$($MY_CLUSTER_COMMAND -n $VAR_APIC_NAMESPACE get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="jwksUrl")].uri}')
  # 2) ingress certificate (cp4i-apic-ingress-ca) D:\CurrentProjects\CP4I\Installation\cp4i-install\tmp\cp4i-apic-ingress-ca.pem
  # kubectl -n <APIC namespace> get secret <ingress-ca name> -ojsonpath="{.data['ca\.crt']}" | base64 -d
  # 	$MY_CLUSTER_COMMAND -n cp4i get secret cp4i-apic-ingress-ca -ojsonpath="{.data['ca\.crt']}" | base64 -d
  # 3) secret for EEM apim-cpd.yaml
  
  export VAR_EEM_APIC_INGRESS_CA_CERT_SECRET_NAME=apim-cpd
  if ! $MY_CLUSTER_COMMAND -n ${VAR_EEM_NAMESPACE} get secret $VAR_EEM_APIC_INGRESS_CA_CERT_SECRET_NAME >/dev/null 2>&1; then
    mylog info "Configure Event Endpoint Management to trust API Connect" 0
  
    decho $lf_tracelevel "$MY_CLUSTER_COMMAND -n $VAR_APIC_NAMESPACE get secret ${VAR_APIC_INSTANCE_NAME}-ingress-ca -o=jsonpath=\"{.data['ca\.crt']}\""
    lf_apic_ca_ingress=$($MY_CLUSTER_COMMAND -n $VAR_APIC_NAMESPACE get secret ${VAR_APIC_INSTANCE_NAME}-ingress-ca -o=jsonpath="{.data['ca\.crt']}")
    export EEM_APIC_INGRESS_CA_CERT=${lf_apic_ca_ingress}
    adapt_file ${MY_EEM_SIMPLE_DEMODIR}resources/ ${MY_EEM_WORKINGDIR}resources/ apim-cpd.yaml
  
    # Create Secret to access API Connect from EEM.
    create_oc_resource "Secret" "$VAR_EEM_APIC_INGRESS_CA_CERT_SECRET_NAME" "${MY_EEM_SIMPLE_DEMODIR}resources/" "${MY_EEM_WORKINGDIR}resources/" "apim-cpd.yaml" "$VAR_EEM_NAMESPACE"
  
    # 4) Update cp4i-eem CRD
    # spec.manager
    #     apic:
    #       jwks:
    #         endpoint: 'https://cp4i-apic-mgmt-platform-api-cp4i.apps.66c486d0cc846855dd383768.ocp.techzone.ibm.com/api/cloud/oauth2/certs'		
    # spec.manager.
    #     tls:
    # 	    trustedCertificates:
    # 	    - certificate: ca.crt
    # 		  secretName: apim-cpd
    # Need to restart the pod
    # 5) Optional, Update cp4i-eem CRD
    # spec.manager.apic
    # 	clientSubjectDN: CN=IBM Event Endpoint Management
  
    # Update the EventEndpointManagement instance with the API Connect configuration details
    decho $lf_tracelevel "$MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE patch EventEndpointManagement "${VAR_EEM_INSTANCE_NAME}" --type merge -p '{\"spec\": {"manager": {\"apic\": {\"jwks\": { \"endpoint\": \"$lf_jwks_url\"}}}}}'"
    $MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE patch EventEndpointManagement "${VAR_EEM_INSTANCE_NAME}" --type merge -p "{\"spec\" : {\"manager\": {\"apic\": {\"jwks\": {\"endpoint\": \"$lf_jwks_url\"}}}}}"
    # TODO  name of instance (apim-cpd) should in  a variable
    decho $lf_tracelevel "$MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE patch EventEndpointManagement "${VAR_EEM_INSTANCE_NAME}" --type merge -p \"{\"spec\":  {\"manager\": {\"tls\": {\"trustedCertificates\": [{\"certificate\": \"ca.crt\"},{\"secretName\": \"$VAR_EEM_APIC_INGRESS_CA_CERT_SECRET_NAME\"}]}}}}\""
    $MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE patch EventEndpointManagement "${VAR_EEM_INSTANCE_NAME}" --type merge -p '{"spec":{"manager":{"tls":{"trustedCertificates":[{"certificate":"ca.crt","secretName":"apim-cpd"}]}}}}'
  fi
  
  # 6) Get Certificates for API connect
  save_certificate cp4i-eem-ibm-eem-manager ca.crt ${MY_EEM_WORKINGDIR} ${VAR_EEM_NAMESPACE}
  save_certificate cp4i-eem-ibm-eem-manager tls.crt ${MY_EEM_WORKINGDIR} ${VAR_EEM_NAMESPACE} 
  save_certificate cp4i-eem-ibm-eem-manager tls.key ${MY_EEM_WORKINGDIR} ${VAR_EEM_NAMESPACE}
  
  # 7) TlS Profile in APIC EMM Client/EEM Trust
  # Create a TLS Client Profile (eemclientprofile)
  # 	Create a TLS keystore (eem_key)
  # 		installcp4i/working/cp4i-eem-ibm-eem-manager.tls.crt.pem
  # 		installcp4i/working/cp4i-eem-ibm-eem-manager.tls.key.pem
  # 	Create a TLS truststore (eem_trust)
  # 		installcp4i/working/cp4i-eem-ibm-eem-manager.ca.crt.pem
  #   Create a TLS Client profile (eem_TLS_client_profile)
  # 8) Register eem-eventgateway eemgtw
  # Service endpoint configuration $MY_CLUSTER_COMMAND -n cp4i get route | grep apic | grep eem
  # 	https://cp4i-eem-ibm-eem-apic-cp4i.apps.66d5d603d361e1cd7ea1cfc0.ocp.techzone.ibm.com
  # Reference the TLS Client Profile
  # API invocation endpoint	ibm-egw-rt
  # $MY_CLUSTER_COMMAND -n cp4i get route | grep ibm-egw-rt
  # 	cp4i-eg-ibm-egw-rt-1-cp4i.apps.66d5d603d361e1cd7ea1cfc0.ocp.techzone.ibm.com:443


  local lf_ending_date=$(date)
    
  mylog info "==== Customisation of eem (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  trace_out $lf_tracelevel eem_run_all
}


################################################
# initialisation
function eem_init() {
  	local lf_tracelevel=2
		trace_in $lf_tracelevel eem_init

  trace_out $lf_tracelevel eem_init
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
    --all) eem_run_all "$@";;
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

################################################################################################
# Start of the script main entry
################################################################################################
# other example: ./eem.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./eem.config.sh --all
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
export MY_EEM_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../properties/eem.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load properties files
. "${sc_provision_constant_properties_file}"

# load properties files
. "${sc_provision_variable_properties_file}"

# Load mq variables
. "${sc_component_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

eem_init

######################################################
# main entry
######################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi