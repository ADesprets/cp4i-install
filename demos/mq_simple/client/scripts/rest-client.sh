
PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"

# load config files
. "${sc_provision_variable_properties_file}"

# load config files
. "${sc_provision_constant_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"

sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
# load helper functions
. "${sc_provision_lib_file}"

mquser="desprets"
mqadmin="mqadmin"
mqpwd="Passw0rd!"

lf_mq_admin_url=$($MY_CLUSTER_COMMAND -n $VAR_MQ_NAMESPACE get QueueManager ${VAR_QMGR} -o jsonpath='{.status.adminUiUrl}')
if [ -z "${lf_mq_admin_url}" ]; then
  mylog error "The Queue Manager ${VAR_QMGR} is not available"
  exit 1
fi
rest_endpoint=$(echo ${lf_mq_admin_url} | sed 's#/ibmmq/console/##')
std_headers="-H \"accept: application/json; charset=utf-8\" -H \"ibm-mq-rest-csrf-token: blank\""

mylog info "The Open API for the administrative REST interface is available at ${rest_endpoint}/ibm/api/explorer/"

mylog info "Getting the list of the queue managers"
decho 4 "curl -k -u \"${mqadmin}:${mqpwd}\" ${std_headers} ${rest_endpoint}/ibmmq/rest/v3/admin/qmgr 2>/dev/null"
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" ${rest_endpoint}/ibmmq/rest/v3/admin/qmgr 2>/dev/null)
mylog result "${result}"

mylog info "Post a message to the queue Q1 in the ${VAR_QMGR} queue manager"
mq_msg="Test message $(date +'%A, %d-%m-%Y %H:%M:%S')"

decho 4 "curl -k -u \"${mquser}:${mqpwd}\"  ${std_headers} -H \"content-type: text/plain; charset=utf-8\" -H \"ibm-mq-md-expiry: unlimited\" -H \"ibm-mq-md-priority: 9\" -H \"ibm-mq-md-persistence: persistent\" -d \"${mq_msg}\" \"${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${VAR_QMGR}/queue/Q1/message\" 2>/dev/null"
result=$(curl -k -u "${mquser}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" -H "content-type: text/plain; charset=utf-8" -H "ibm-mq-md-expiry: unlimited" -H "ibm-mq-md-priority: 9" -H "ibm-mq-md-persistence: persistent" -d "${mq_msg}" "${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${VAR_QMGR}/queue/Q1/message" 2>/dev/null)
mylog result "${result}"

mylog info "Get a message from the queue Q1 in the ${VAR_QMGR} queue manager"
decho 4 "curl -k -u \"${mquser}:${mqpwd}\" ${std_headers} \"${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${VAR_QMGR}/queue/Q1/message\" 2>/dev/null"
result=$(curl -k -u "${mquser}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" "${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${VAR_QMGR}/queue/Q1/message" 2>/dev/null)
mylog result "${result}"

mylog info "Get installation"
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" "${rest_endpoint}/ibmmq/rest/v3/admin/installation" 2>/dev/null)
mylog result "${result}"

mylog info "Get queues for the ${VAR_QMGR} queue manager"
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" "${rest_endpoint}/ibmmq/rest/v1/admin/qmgr/${VAR_QMGR}/queue" 2>/dev/null)
mylog result "${result}"

mylog info "Get channels for the ${VAR_QMGR} queue manager"
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" "${rest_endpoint}/ibmmq/rest/v1/admin/qmgr/${VAR_QMGR}/channel" 2>/dev/null)
mylog result "${result}"
