# TODO this script needs rework for keycloak
################################################
# Run this script
################################################



################################################
# Configure the email server settings on the Keycloak master realm.
# Uses the same mail service as the APIC configuration (MailHog / SMTP relay
# running in ${VAR_MAIL_NAMESPACE}).
# Variables read from properties:
#   VAR_KEYCLOAK_NAMESPACE, VAR_MAIL_NAMESPACE, VAR_MAIL_SERVICE : cp4i-variables.properties
#   MY_KEYCLOAK_MASTER_REALM, MY_KEYCLOAK_USERNAME,
#   MY_KEYCLOAK_ADMIN_CLI_CLIENT                                  : cp4i-constants.properties
#   APIC_SMTP_SERVER_PORT, APIC_SMTP_USERNAME,
#   APIC_SMTP_PASSWORD, APIC_ADMIN_EMAIL                          : apic.properties (reused)
function keycloak_configure_email() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  decho $lf_tracelevel "Parameters: |no parameters|"

  mylog info "Configuring email server settings on Keycloak realm '${MY_KEYCLOAK_MASTER_REALM}'" 1>&2

  # Resolve the mail service ClusterIP (mailhog)
  local lf_mail_host
  lf_mail_host=$($MY_CLUSTER_COMMAND -n "${VAR_MAIL_NAMESPACE}" get svc/"${VAR_MAIL_SERVICE}" \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [[ -z "${lf_mail_host}" ]]; then
    mylog error "Could not resolve mail service ClusterIP for '${VAR_MAIL_SERVICE}' in namespace '${VAR_MAIL_NAMESPACE}'." 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi
  decho $lf_tracelevel "lf_mail_host: ${lf_mail_host} port: ${APIC_SMTP_SERVER_PORT}"

  # Build the SMTP JSON payload
  local lf_smtp_payload
  lf_smtp_payload=$(jq -n \
    --arg host    "${lf_mail_host}" \
    --arg port    "${APIC_SMTP_SERVER_PORT}" \
    --arg from    "${APIC_ADMIN_EMAIL}" \
    --arg user    "${APIC_SMTP_USERNAME}" \
    --arg pass    "${APIC_SMTP_PASSWORD}" \
    '{
      host:        $host,
      port:        ($port | tonumber),
      from:        $from,
      auth:        (if $user != "" then true else false end),
      user:        $user,
      password:    $pass,
      ssl:         false,
      starttls:    false,
      envelopeFrom: $from
    }')
  decho $lf_tracelevel "lf_smtp_payload: ${lf_smtp_payload}"

  # ── 6. PUT the SMTP settings on the realm ─────────────────────────────────
  decho $lf_tracelevel "curl -sk -X PUT \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}\" --data '{\"smtpServer\": ...}'"
  local lf_put_response
  lf_put_response=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}" \
    -H "Authorization: Bearer ${lf_access_token}" \
    -H "Content-Type: application/json" \
    --data "{\"smtpServer\": ${lf_smtp_payload}}")
  decho $lf_tracelevel "lf_put_response HTTP status: ${lf_put_response}"

  if [[ "${lf_put_response}" == "204" ]]; then
    mylog info "Email server configured successfully on Keycloak realm '${MY_KEYCLOAK_MASTER_REALM}'." 1>&2
  else
    mylog error "Failed to configure email server on Keycloak realm '${MY_KEYCLOAK_MASTER_REALM}'. HTTP status: ${lf_put_response}" 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create Keycloak token
function create_kc_token(){
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}
  
  decho $lf_tracelevel "Parameters: |no parameters|"

  # Retrieve the Keycloak initial admin credentials from the secret created by the Keycloak operator.
  # CP4I Common Services Keycloak stores credentials in 'cs-keycloak-initial-admin' (username=temp-admin).
  local lf_cs_keycloak_initial_admin_secret=cs-keycloak-initial-admin
  local lf_admin_username lf_admin_password
  lf_admin_username=$($MY_CLUSTER_COMMAND -n "${VAR_KEYCLOAK_NAMESPACE}" \
    get secret "${lf_cs_keycloak_initial_admin_secret}" \
    -o jsonpath='{.data.username}' 2>/dev/null | base64 --decode)
  lf_admin_password=$($MY_CLUSTER_COMMAND -n "${VAR_KEYCLOAK_NAMESPACE}" \
    get secret "${lf_cs_keycloak_initial_admin_secret}" \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)
  if [[ -z "${lf_admin_username}" || -z "${lf_admin_password}" ]]; then
    mylog error "Could not retrieve Keycloak admin credentials from secret '${lf_cs_keycloak_initial_admin_secret}' in namespace '${VAR_KEYCLOAK_NAMESPACE}'." 1>&2
    mylog error "  username='${lf_admin_username}' password=$([ -n "${lf_admin_password}" ] && echo '<set>' || echo '<empty>')" 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi
  decho $lf_tracelevel "lf_admin_username: ${lf_admin_username} | EP_KEYCLOAK: ${EP_KEYCLOAK}"

  # Obtain an admin access token (master realm / admin-cli)
  local lf_token_url="${EP_KEYCLOAK}/realms/${MY_KEYCLOAK_MASTER_REALM}/protocol/openid-connect/token"
  decho $lf_tracelevel "curl -sk -X POST \"${lf_token_url}\" --data grant_type=password username=${lf_admin_username} ..."
  local lf_token_response lf_http_status
  lf_token_response=$(curl -sk -o /tmp/kc_token_response.json -w "%{http_code}" -X POST \
    "${lf_token_url}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=${MY_KEYCLOAK_ADMIN_CLI_CLIENT}" \
    --data-urlencode "username=${lf_admin_username}" \
    --data-urlencode "password=${lf_admin_password}")
  lf_http_status="${lf_token_response}"
  lf_token_response=$(cat /tmp/kc_token_response.json 2>/dev/null)
  decho $lf_tracelevel "HTTP status: ${lf_http_status} | lf_token_response: ${lf_token_response}"

  KC_AT=$(printf '%s\n' "${lf_token_response}" | jq -r '.access_token // empty')
  if [[ -z "${KC_AT}" ]]; then
    mylog error "Failed to obtain Keycloak admin token. HTTP status: ${lf_http_status} | Response: ${lf_token_response}" 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
function keycloak_run_all () {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  keycloak_configure_email

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# initialisation
function keycloak_init() {
  local lf_tracelevel=1
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  # save the current cluster config context
  sc_current_context=$($MY_CLUSTER_COMMAND config current-context)

  # Create namespace 
  create_project "${VAR_KEYCLOAK_NAMESPACE}" "${VAR_KEYCLOAK_NAMESPACE} project" "For Openkeycloak" "${MY_RESOURCESDIR}" "${MY_keycloak_WORKINGDIR}"

   # Initialise the Keycloak route (EP_KEYCLOAK)
  local lf_kc_route_name=keycloak
  EP_KEYCLOAK=https://$($MY_CLUSTER_COMMAND -n "${VAR_KEYCLOAK_NAMESPACE}" get route "${lf_kc_route_name}" -o jsonpath={.spec.host} 2>/dev/null)
  if [[ -z "${EP_KEYCLOAK}" ]]; then
    mylog error "Could not resolve ${lf_kc_route_name} route in namespace '${VAR_KEYCLOAK_NAMESPACE}'." 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  else
    decho $lf_tracelevel "EP_KEYCLOAK: ${EP_KEYCLOAK}"
  fi

   # Create the token
  create_kc_token

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
    trace_out $lf_tracelevel ${FUNCNAME[0]}
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
        trace_out $lf_tracelevel ${FUNCNAME[0]}
        return 1
        ;;
      esac
  done
  #lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces
  lf_calls=$(echo "$lf_calls" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')

  # Call processing function if --call was used
  case $lf_key in
    --all)  case $MY_CLUSTER_COMMAND in
              kubectl)  keycloak_run_all_k8s "$@";;
              oc) keycloak_run_all "$@";;
            esac;;
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
# other example: ./keycloak.config.sh --call <function_name1>, <function_name2>, ...
# other example: ./keycloak.config.sh --all
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
export MY_keycloak_WORKINGDIR="${sc_component_script_dir}working/"

PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"
sc_provision_user_properties_file="${PROVISION_SCRIPTDIR}private/user.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"

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

# Load privatae user properties
. "${sc_provision_user_properties_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

keycloak_init

trap '$MY_CLUSTER_COMMAND config use-context $sc_current_context' EXIT
################################################
# main entry
################################################
# Main execution block (only runs if executed directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi