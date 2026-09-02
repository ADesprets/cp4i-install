# TODO this script needs rework for keycloak
################################################
# Run this script
################################################



################################################
# Configure the email server settings on the Keycloak master realm.
# Uses the same mail service as the APIC configuration (MailHog / SMTP relay
# running in ${VAR_MAIL_NAMESPACE}).
# Variables read from properties:
#   VAR_KEYCLOAK_NAMESPACE, VAR_MAIL_NAMESPACE, VAR_MAIL_SERVICE  : cp4i-variables.properties
#   VAR_KEYCLOAK_ADMIN_EMAIL, VAR_KEYCLOAK_ADMIN_EMAIL_DISPLAY_NAME,
#   VAR_KEYCLOAK_REPLY_TO_EMAIL, VAR_KEYCLOAK_REPLY_TO_DISPLAY_NAME : cp4i-variables.properties
#   MY_KEYCLOAK_MASTER_REALM, MY_KEYCLOAK_USERNAME,
#   MY_KEYCLOAK_ADMIN_CLI_CLIENT                                  : cp4i-constants.properties
#   VAR_SMTP_SERVER_PORT, VAR_SMTP_USERNAME,
#   VAR_SMTP_PASSWORD                                             : cp4i-variables.properties
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
  decho $lf_tracelevel "lf_mail_host: ${lf_mail_host} port: ${VAR_SMTP_SERVER_PORT}"

  # Build the SMTP JSON payload
  local lf_smtp_payload
  lf_smtp_payload=$(jq -n \
    --arg host            "${lf_mail_host}" \
    --arg port            "${VAR_SMTP_SERVER_PORT}" \
    --arg from            "${VAR_KEYCLOAK_ADMIN_EMAIL}" \
    --arg fromDisplayName "${VAR_KEYCLOAK_ADMIN_EMAIL_DISPLAY_NAME}" \
    --arg replyTo         "${VAR_KEYCLOAK_REPLY_TO_EMAIL}" \
    --arg replyToDisplayName "${VAR_KEYCLOAK_REPLY_TO_DISPLAY_NAME}" \
    --arg user            "${VAR_SMTP_USERNAME}" \
    --arg pass            "${VAR_SMTP_PASSWORD}" \
    '{
      host:             $host,
      port:             ($port | tonumber),
      from:             $from,
      fromDisplayName:  $fromDisplayName,
      replyTo:          $replyTo,
      replyToDisplayName: $replyToDisplayName,
      auth:             (if $user != "" then true else false end),
      user:             $user,
      password:         $pass,
      ssl:              false,
      starttls:         false,
      envelopeFrom:     $from
    }')
  decho $lf_tracelevel "lf_smtp_payload: $(echo "${lf_smtp_payload}" | jq -c .)"

  # PUT the SMTP settings on the master realm
  decho $lf_tracelevel "curl -sk -X PUT -H \"Content-Type: application/json\" -H \"Authorization: Bearer \$AT\" \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}\" --data '{\"smtpServer\": ...}'"
  local lf_put_response
  lf_put_response=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}" \
    -H "Authorization: Bearer ${KC_AT}" \
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

# create_kc_token is defined in lib.sh and available to all demo scripts.
# See lib.sh for the full implementation and parameter documentation.

################################################
# Create a Keycloak administrator user in the master realm.
# Variables read from properties:
#   MY_USER           : private/user.properties  (username / uid)
#   MY_USER_PASSWORD  : private/user.properties  (password)
#   MY_USER_EMAIL     : private/user.properties  (email address)
#   MY_USER_FIRSTNAME : private/user.properties  (first name)
#   MY_USER_LASTNAME  : private/user.properties  (last name)
#   MY_KEYCLOAK_MASTER_REALM                    : cp4i-constants.properties
# Prerequisites:
#   EP_KEYCLOAK and KC_AT must already be set (call keycloak_init first).
function keycloak_create_master_admin() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  decho $lf_tracelevel "Parameters: |no parameters|"

  mylog info "Creating administrator user '${MY_USER}' in Keycloak master realm '${MY_KEYCLOAK_MASTER_REALM}'" 1>&2

  # Build the user JSON payload
  local lf_user_payload
  lf_user_payload=$(jq -n \
    --arg username  "${MY_USER}" \
    --arg email     "${MY_USER_EMAIL}" \
    --arg password  "${MY_USER_PASSWORD}" \
    --arg firstname "${MY_USER_FIRSTNAME}" \
    --arg lastname  "${MY_USER_LASTNAME}" \
    '{
      username:       $username,
      email:          $email,
      firstName:      $firstname,
      lastName:       $lastname,
      enabled:        true,
      emailVerified:  true,
      credentials: [{
        type:      "password",
        value:     $password,
        temporary: false
      }]
    }')
  decho $lf_tracelevel "lf_user_payload: $(echo "${lf_user_payload}" | jq -c .)"

  # POST the new user to the master realm
  decho $lf_tracelevel "curl -sk -X POST -H \"Content-Type: application/json\" -H \"Authorization: Bearer \$KC_AT\" \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/users\" --data '...'"
  local lf_http_status
  lf_http_status=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/users" \
    -H "Authorization: Bearer ${KC_AT}" \
    -H "Content-Type: application/json" \
    --data "${lf_user_payload}")
  decho $lf_tracelevel "lf_http_status: ${lf_http_status}"

  case "${lf_http_status}" in
    201)
      mylog info "Administrator user '${MY_USER}' created successfully in realm '${MY_KEYCLOAK_MASTER_REALM}'." 1>&2
      ;;
    409)
      mylog info "Administrator user '${MY_USER}' already exists in realm '${MY_KEYCLOAK_MASTER_REALM}' – proceeding to role assignment." 1>&2
      ;;
    *)
      mylog error "Failed to create administrator user '${MY_USER}' in realm '${MY_KEYCLOAK_MASTER_REALM}'. HTTP status: ${lf_http_status}" 1>&2
      trace_out $lf_tracelevel ${FUNCNAME[0]}
      return 1
      ;;
  esac

  # Retrieve the user ID by username search (works for both 201 and 409)
  decho $lf_tracelevel "curl -sk -X GET \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/users?username=${MY_USER}&exact=true\""
  local lf_user_id
  lf_user_id=$(curl -sk -X GET \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/users?username=${MY_USER}&exact=true" \
    -H "Authorization: Bearer ${KC_AT}" \
    -H "Content-Type: application/json" \
    | jq -r '.[0].id // empty')
  if [[ -z "${lf_user_id}" ]]; then
    mylog error "Could not determine user ID for '${MY_USER}' in realm '${MY_KEYCLOAK_MASTER_REALM}'." 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi
  decho $lf_tracelevel "lf_user_id: ${lf_user_id}"

  # Fetch the 'admin' realm-role representation (id + name are required for the mapping call)
  decho $lf_tracelevel "curl -sk -X GET \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/roles/admin\""
  local lf_role_payload
  lf_role_payload=$(curl -sk -X GET \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/roles/admin" \
    -H "Authorization: Bearer ${KC_AT}" \
    -H "Content-Type: application/json")
  decho $lf_tracelevel "lf_role_payload: $(echo "${lf_role_payload}" | jq -c .)"

  if [[ -z "${lf_role_payload}" ]] || echo "${lf_role_payload}" | jq -e '.error' >/dev/null 2>&1; then
    mylog error "Could not retrieve 'admin' role from realm '${MY_KEYCLOAK_MASTER_REALM}': ${lf_role_payload}" 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi

  # Assign the 'admin' realm role to the newly created user
  decho $lf_tracelevel "curl -sk -X POST \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/users/${lf_user_id}/role-mappings/realm\""
  local lf_role_status
  lf_role_status=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_MASTER_REALM}/users/${lf_user_id}/role-mappings/realm" \
    -H "Authorization: Bearer ${KC_AT}" \
    -H "Content-Type: application/json" \
    --data "[${lf_role_payload}]")
  decho $lf_tracelevel "lf_role_status: ${lf_role_status}"

  if [[ "${lf_role_status}" == "204" ]]; then
    mylog info "Realm role 'admin' assigned to user '${MY_USER}'." 1>&2
  else
    mylog error "Failed to assign realm role 'admin' to user '${MY_USER}'. HTTP status: ${lf_role_status}" 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
# Create the APIC OIDC/OAuth2 client in the cloudpak realm.
# The client is used by APIC to authenticate users via Keycloak.
# Variables read from properties:
#   MY_KEYCLOAK_APIC_CLIENT_ID : cp4i-constants.properties  (client_id)
#   MY_KEYCLOAK_CP4I_REALM     : cp4i-constants.properties  (target realm)
# Prerequisites:
#   EP_KEYCLOAK and KC_AT must already be set with credentials that have
#   admin rights on the cloudpak realm (call create_kc_token with MY_USER first).
function keycloak_create_apic_client() {
  local lf_tracelevel=3
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  decho $lf_tracelevel "Parameters: |no parameters|"

  mylog info "Creating APIC OIDC client '${MY_KEYCLOAK_APIC_CLIENT_ID}' in Keycloak realm '${MY_KEYCLOAK_CP4I_REALM}'" 1>&2

  # Build the client JSON payload
  # standardFlowEnabled   : Authorization Code flow  (OIDC / browser login)
  # serviceAccountsEnabled: Client Credentials flow  (OAuth2 machine-to-machine)
  # directAccessGrantsEnabled: Resource Owner Password flow (optional – useful for testing)
  local lf_client_payload
  lf_client_payload=$(jq -n \
    --arg clientId "${MY_KEYCLOAK_APIC_CLIENT_ID}" \
    '{
      clientId:                  $clientId,
      name:                      "APIC Keycloak Client",
      description:               "OIDC/OAuth2 client for IBM API Connect",
      enabled:                   true,
      protocol:                  "openid-connect",
      publicClient:              false,
      standardFlowEnabled:       true,
      implicitFlowEnabled:       false,
      directAccessGrantsEnabled: true,
      serviceAccountsEnabled:    true,
      authorizationServicesEnabled: false,
      redirectUris:              ["*"],
      webOrigins:                ["*"],
      attributes: {
        "access.token.lifespan": "300"
      }
    }')
  decho $lf_tracelevel "lf_client_payload: $(echo "${lf_client_payload}" | jq -c .)"

  # POST the client to the cloudpak realm
  decho $lf_tracelevel "curl -sk -X POST \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_CP4I_REALM}/clients\""
  local lf_http_status
  lf_http_status=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_CP4I_REALM}/clients" \
    -H "Authorization: Bearer ${KC_AT}" \
    -H "Content-Type: application/json" \
    --data "${lf_client_payload}")
  decho $lf_tracelevel "lf_http_status: ${lf_http_status}"

  case "${lf_http_status}" in
    201)
      mylog info "APIC client '${MY_KEYCLOAK_APIC_CLIENT_ID}' created successfully in realm '${MY_KEYCLOAK_CP4I_REALM}'." 1>&2
      ;;
    409)
      mylog info "APIC client '${MY_KEYCLOAK_APIC_CLIENT_ID}' already exists in realm '${MY_KEYCLOAK_CP4I_REALM}' (HTTP 409 – skipping)." 1>&2
      trace_out $lf_tracelevel ${FUNCNAME[0]}
      return 0
      ;;
    *)
      mylog error "Failed to create APIC client '${MY_KEYCLOAK_APIC_CLIENT_ID}' in realm '${MY_KEYCLOAK_CP4I_REALM}'. HTTP status: ${lf_http_status}" 1>&2
      trace_out $lf_tracelevel ${FUNCNAME[0]}
      return 1
      ;;
  esac

  # Retrieve the internal client UUID (needed for the client-secret endpoint)
  decho $lf_tracelevel "curl -sk -X GET \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_CP4I_REALM}/clients?clientId=${MY_KEYCLOAK_APIC_CLIENT_ID}&exact=true\""
  local lf_client_uuid
  lf_client_uuid=$(curl -sk -X GET \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_CP4I_REALM}/clients?clientId=${MY_KEYCLOAK_APIC_CLIENT_ID}&exact=true" \
    -H "Authorization: Bearer ${KC_AT}" \
    -H "Content-Type: application/json" \
    | jq -r '.[0].id // empty')
  if [[ -z "${lf_client_uuid}" ]]; then
    mylog error "Could not retrieve UUID for client '${MY_KEYCLOAK_APIC_CLIENT_ID}' in realm '${MY_KEYCLOAK_CP4I_REALM}'." 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi
  decho $lf_tracelevel "lf_client_uuid: ${lf_client_uuid}"

  # Retrieve and display the generated client secret
  decho $lf_tracelevel "curl -sk -X GET \"${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_CP4I_REALM}/clients/${lf_client_uuid}/client-secret\""
  local lf_client_secret
  lf_client_secret=$(curl -sk -X GET \
    "${EP_KEYCLOAK}/admin/realms/${MY_KEYCLOAK_CP4I_REALM}/clients/${lf_client_uuid}/client-secret" \
    -H "Authorization: Bearer ${KC_AT}" \
    -H "Content-Type: application/json" \
    | jq -r '.value // empty')
  if [[ -z "${lf_client_secret}" ]]; then
    mylog error "Could not retrieve client secret for '${MY_KEYCLOAK_APIC_CLIENT_ID}'." 1>&2
    trace_out $lf_tracelevel ${FUNCNAME[0]}
    return 1
  fi

  mylog info "APIC client secret (store this for APIC OIDC registry configuration): ${lf_client_secret}" 1>&2

  trace_out $lf_tracelevel ${FUNCNAME[0]}
}

################################################
function keycloak_run_all () {
  local lf_tracelevel=2
  trace_in $lf_tracelevel ${FUNCNAME[0]}

  keycloak_create_master_admin
  keycloak_configure_email
  # Refresh the token as MY_USER (admin) before acting on the cloudpak realm
  create_kc_token "${MY_USER}" "${MY_USER_PASSWORD}"
  keycloak_create_apic_client

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

  # Create the initial token using the operator-provisioned temp-admin credentials
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