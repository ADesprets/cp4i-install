################################################
# Login to internal registry
################################################
function login_to_registry() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel login_to_registry

  decho $lf_tracelevel "Internal image registry host: $VAR_IMAGE_REGISTRY_HOST"
  local lf_cluster_server=$($MY_CLUSTER_COMMAND whoami --show-server)
  decho $lf_tracelevel "Cluster server host: $lf_cluster_server"
  decho $lf_tracelevel "kubeadmin password: $MY_TECHZONE_PASSWORD"
  $MY_CLUSTER_COMMAND project ${VAR_LDAP_NAMESPACE}
  $MY_CLUSTER_COMMAND login -p $MY_TECHZONE_HTPASSWD -u ${MY_USER} #$lf_cluster_server
  local lf_token=$($MY_CLUSTER_COMMAND whoami -t)
  echo "$lf_token" | $MY_CONTAINER_ENGINE login -u ${MY_USER} --password-stdin "$VAR_IMAGE_REGISTRY_HOST"

  # Create a user for registry
  #$MY_CLUSTER_COMMAND policy add-role-to-user system:image-builder system:serviceaccount:$VAR_LDAP_NAMESPACE:$MY_LDAP_SERVICEACCOUNT
  #$MY_CLUSTER_COMMAND policy add-role-to-user system:image-builder system:serviceaccount:openshift:admin-sa
  $MY_CLUSTER_COMMAND policy add-role-to-user system:image-builder system:serviceaccount:openshift:${MY_USER}

  #docker login -u kubeadmin -p "$($MY_CLUSTER_COMMAND whoami -t)" "$VAR_IMAGE_REGISTRY_HOST"
  #local lf_token=$($MY_CLUSTER_COMMAND -n $VAR_LDAP_NAMESPACE create token $MY_LDAP_SERVICEACCOUNT)
  #echo "$lf_token" | docker login -u $MY_LDAP_SERVICEACCOUNT --password-stdin "$VAR_IMAGE_REGISTRY_HOST"
  #local lf_token=$($MY_CLUSTER_COMMAND -n openshift create token saad)
  #echo "$lf_token" | docker login -u saad --password-stdin "$VAR_IMAGE_REGISTRY_HOST"
  
  trace_out $lf_tracelevel login_to_registry
}

################################################
# Push image to internal registry
################################################
function push_image_to_registry() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel push_image_to_registry

  # Add roles to the user
  $MY_CLUSTER_COMMAND -n openshift policy add-role-to-user system:image-builder ${MY_USER}
  $MY_CLUSTER_COMMAND -n openshift policy add-role-to-user system:registry ${MY_USER}

  #	tag the local image with details of image registry
  decho $lf_tracelevel "CMD: $MY_CONTAINER_ENGINE tag ${MY_LDAP_APP_NAME_VERSION} ${VAR_IMAGE_REGISTRY_HOST}/${VAR_LDAP_NAMESPACE}/${MY_LDAP_APP_NAME_VERSION}"
  $MY_CONTAINER_ENGINE tag ${MY_LDAP_APP_NAME_VERSION} ${VAR_IMAGE_REGISTRY_HOST}/${VAR_LDAP_NAMESPACE}/${MY_LDAP_APP_NAME_VERSION}
  $MY_CONTAINER_ENGINE push ${VAR_IMAGE_REGISTRY_HOST}/${VAR_LDAP_NAMESPACE}/${MY_LDAP_APP_NAME_VERSION}
    
  trace_out $lf_tracelevel push_image_to_registry
}

################################################
# Build docker image
################################################
function ldap_build_image() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ldap_build_image

  $MY_CONTAINER_ENGINE build -t ${MY_LDAP_APP_NAME_VERSION} .

  trace_out $lf_tracelevel ldap_build_image
}

#############################################################
# Run this script
#############################################################
function ldap_run_all () {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ldap_run_all

  # Build the image
  if $MY_LDAP_CUSTOM_BUILD; then
    pushd ${MY_LDAP_SIMPLE_DEMODIR}resources/ > /dev/null 2>&1
    ldap_build_image
    popd > /dev/null 2>&1
  fi
  # save the current cluster config context
  sc_current_context=$($MY_CLUSTER_COMMAND config current-context)
  login_to_registry
  push_image_to_registry
  $MY_CLUSTER_COMMAND logout

  # back to the saved context
  $MY_CLUSTER_COMMAND config use-context $sc_current_context

  # load users and groups into LDAP
  load_users_2_ldap_server "${VAR_LDAP_TMPL_DIRECTORY}" "${MY_LDAP_WORKINGDIR}" "${VAR_LDAP_LDIF_FILE}"
  
  trace_out $lf_tracelevel ldap_run_all
}

################################################
# initialisation
function ldap_init() {
  local lf_tracelevel=1
  trace_in $lf_tracelevel ldap_init

  # save the current cluster config context
  sc_current_context=$($MY_CLUSTER_COMMAND config current-context)

  # Create namespace 
  create_project "${VAR_LDAP_NAMESPACE}" "${VAR_LDAP_NAMESPACE} project" "For OpenLDAP" "${MY_RESOURCESDIR}" "${MY_LDAP_WORKINGDIR}"

  read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
  export VAR_LDAP_PORT=$($MY_CLUSTER_COMMAND -n ${VAR_LDAP_NAMESPACE} get service "${VAR_LDAP_SERVICE}" -o jsonpath='{.spec.ports[0].nodePort}')
  export VAR_LDAP_HOSTNAME=$($MY_CLUSTER_COMMAND -n ${VAR_LDAP_NAMESPACE} get route "${VAR_LDAP_ROUTE}" -o jsonpath='{.spec.host}')

  $MY_CLUSTER_COMMAND apply -f "${MY_YAMLDIR}ldap/scc.yaml"
  # Then assign it to your service account
  $MY_CLUSTER_COMMAND adm policy add-scc-to-user openldap-scc -z $MY_LDAP_SERVICEACCOUNT -n ${VAR_LDAP_NAMESPACE}

  trace_out $lf_tracelevel ldap_init
}

################################################
# main function
# Main logic
function main() {
  local lf_tracelevel=1
  trace_in $lf_tracelevel main

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    trace_out $lf_tracelevel main
    exit 1
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
  lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces

  # Call processing function if --call was used
  case $lf_key in
    --all) ldap_run_all "$@";;
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
# other example: ./ldap.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./ldap.config.sh --all
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
export MY_LDAP_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"
sc_provision_user_properties_file="${PROVISION_SCRIPTDIR}private/user.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
sc_component_properties_file="${sc_component_script_dir}../resources/ldap.properties"

# SB]20250319 Je suis obligé d'utiliser set -a et set +a parceque à cet instant je n'ai pas accès à la fonction read_config_file
# load script parrameters fil
set -a
. "${sc_provision_script_parameters_file}"

# load config files
. "${sc_provision_constant_properties_file}"

# load config files
. "${sc_provision_variable_properties_file}"

# Load mq variables
. "${sc_component_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"

# Load privatae user properties
. "${sc_provision_user_properties_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

ldap_init

trap '$MY_CLUSTER_COMMAND config use-context $sc_current_context' EXIT
######################################################
# main entry
######################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi