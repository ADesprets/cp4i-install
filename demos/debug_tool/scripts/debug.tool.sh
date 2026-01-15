#!/bin/bash

################################################
# Create service account to push images to internal
################################################
function create_service_account() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # create the SA
  $MY_CLUSTER_COMMAND -n $VAR_DEBUG_NAMESPACE create sa my-service-account 
  
  # Grant the SA pushing images to the internal registry
  $MY_CLUSTER_COMMAND -n $VAR_DEBUG_NAMESPACE policy add-role-to-user edit system:serviceaccount:$VAR_DEBUG_NAMESPACE:my-service-account

  # Get the Token
  # export VAR_TOKEN=$($MY_CLUSTER_COMMAND -n $MY_DEBUG_NAMESPACE sa get-token my-service-account)
  export VAR_TOKEN=$($MY_CLUSTER_COMMAND -n $VAR_DEBUG_NAMESPACE create token my-service-account)

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Ensure internal registry is available
################################################
function prepare_internal_registry() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # Expose service using default route
  decho $lf_tracelevel "$MY_CLUSTER_COMMAND patch configs.imageregistry.operator.openshift.io/cluster --patch '{\"spec\":{\"defaultRoute\":true}}' --type=merge"
  $MY_CLUSTER_COMMAND patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
  wait_for_resource Route default-route openshift-image-registry

  # Get the default registry route:
  export IMAGE_REGISTRY_HOST=$($MY_CLUSTER_COMMAND get route default-route -n openshift-image-registry --template='{{ .spec.host }}')

  # Get the certificate of the Ingress Operator and add it in the trust store, need to check if this is in /usr/local/share/ca-certificates
  # $MY_CLUSTER_COMMAND get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt  > /dev/null
  # $MY_CLUSTER_COMMAND -n openshift-ingress get secret letsencrypt-certs -o go-template='{{index .data "tls.crt7"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt
  # For Ubuntu:  update-ca-certificates / For Mac: / For RH: update-ca-trust / For Windows: 
  # sudo update-ca-trust enable

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Build docker image
################################################
function debug_build_image() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  $MY_CONTAINER_ENGINE build -t ${MY_DEBUG_APP_NAME_VERSION} .

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Login to internal registry
################################################
function login_to_registry() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  mylog info "Do not forget to update the password of kubeadmin in private/user.properties (MY_TECHZONE_PASSWORD)" 0
  decho $lf_tracelevel "Internal image registry host: $IMAGE_REGISTRY_HOST"
  local lf_cluster_server=$($MY_CLUSTER_COMMAND whoami --show-server)
  decho $lf_tracelevel "Cluster server host: $lf_cluster_server"
  # echo "kubeadmin password: $MY_TECHZONE_PASSWORD"
  $MY_CLUSTER_COMMAND login -p $MY_TECHZONE_PASSWORD -u kubeadmin $lf_cluster_server
  local lf_token=$($MY_CLUSTER_COMMAND whoami -t)
  decho $lf_tracelevel "Token: $lf_token"
  #docker login -u kubeadmin -p $lf_token $IMAGE_REGISTRY_HOST
  echo "$lf_token" | docker login -u kubeadmin --password-stdin "$IMAGE_REGISTRY_HOST"
  
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Push image to internal registry
################################################
function push_image_to_registry() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}
  
  #	tag the local image with details of image registry
  decho $lf_tracelevel "$MY_CONTAINER_ENGINE tag ${MY_DEBUG_APP_NAME_VERSION} ${IMAGE_REGISTRY_HOST}/${VAR_DEBUG_NAMESPACE}/${MY_DEBUG_APP_NAME_VERSION}"
  $MY_CONTAINER_ENGINE tag ${MY_DEBUG_APP_NAME_VERSION} ${IMAGE_REGISTRY_HOST}/${VAR_DEBUG_NAMESPACE}/${MY_DEBUG_APP_NAME_VERSION}
  $MY_CONTAINER_ENGINE push ${IMAGE_REGISTRY_HOST}/${VAR_DEBUG_NAMESPACE}/${MY_DEBUG_APP_NAME_VERSION}
    
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Deploy image by creating a Deployment
################################################
function deploy_image() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  mylog info "Application:version ${MY_DEBUG_APP_NAME_VERSION}" 0

  check_directory_exist_create "${MY_DEBUG_WORKINGDIR}"
  create_oc_resource "Deployment" "${VAR_DEBUG_APP_NAME}" "${MY_DEBUG_TOOL_DEMODIR}resources/" "${MY_DEBUG_WORKINGDIR}" "debug_deployment.yaml" "$VAR_DEBUG_NAMESPACE"
  
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# run all 
################################################
function debug_run_all () {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  SECONDS=0
  local lf_starting_date=$(date);
  
  mylog info "Create debug applications (DEBUG Tool)" 0

  prepare_internal_registry
  
  # Build the image
  if $MY_DEBUG_CUSTOM_BUILD; then
    pushd ${MY_DEBUG_TOOL_DEMODIR}resources > /dev/null 2>&1
    mylog info "==== build docker image." 1>&2
    debug_build_image
    popd > /dev/null 2>&1
  fi
  # save the current cluster config context
  sc_current_context=$($MY_CLUSTER_COMMAND config current-context)
  login_to_registry
  push_image_to_registry
  deploy_image
  $MY_CLUSTER_COMMAND logout

  # back to the saved context
  $MY_CLUSTER_COMMAND config use-context $sc_current_context

  local lf_ending_date=$(date)
    
  mylog info "==== Creation debug applications (DEBUG Tool) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# initialisation
function debug_init() {
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
    --all) debug_run_all "$@";;
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
# other example: ./debug.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./debug.config.sh --all
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
export VAR_DEBUG_WORKINGDIR="${sc_component_script_dir}working/"
PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"

sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load resources files
. "${sc_provision_constant_properties_file}"

# load resources files
. "${sc_provision_variable_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

debug_init

################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi