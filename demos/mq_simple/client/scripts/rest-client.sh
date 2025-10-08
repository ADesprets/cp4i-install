PROVISION_SCRIPTDIR="$( cd "$( dirname "${sc_component_script_dir}../../../../../" )" && pwd )/"
sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"

# load resources files
. "${sc_provision_variable_properties_file}"

# load resources files
. "${sc_provision_constant_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"

sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"
# load helper functions
. "${sc_provision_lib_file}"

mquser="mquser"
mqadmin="mqadmin"
mqpwd="Passw0rd!"

lf_qmgr="Orders"
lf_qmgr_lc=$(echo ${lf_qmgr} | tr '[:upper:]' '[:lower:]')
lf_q="PAYMT.RESP"

lf_ccdt=${MY_MQ_WORKINGDIR}${lf_qmgr}/ccdt.json
lf_truststore=${MY_MQ_WORKINGDIR}${lf_qmgr}/${VAR_CLNT1}-keystore.p12

decho 4 "$MY_CLUSTER_COMMAND -n $VAR_MQ_NAMESPACE get QueueManager ${lf_qmgr} -o jsonpath='{.status.adminUiUrl}'"
lf_mq_admin_url=$($MY_CLUSTER_COMMAND -n $VAR_MQ_NAMESPACE get QueueManager ${lf_qmgr_lc} -o jsonpath='{.status.adminUiUrl}')
if [ -z "${lf_mq_admin_url}" ]; then
  mylog error "The Queue Manager \'${lf_qmgr}\' is not available"
  exit 1
fi
rest_endpoint=$(echo ${lf_mq_admin_url} | sed 's#/ibmmq/console/##')
std_headers="-H \"accept: application/json; charset=utf-8\" -H \"ibm-mq-rest-csrf-token: blank\""

mylog info "The Open API for the administrative REST interface is available at ${rest_endpoint}/ibm/api/explorer/" 0

mylog info "Getting the list of the queue managers" 0
decho 4 "curl -k -u \"${mqadmin}:${mqpwd}\" ${std_headers} ${rest_endpoint}/ibmmq/rest/v3/admin/qmgr 2>/dev/null"
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" ${rest_endpoint}/ibmmq/rest/v3/admin/qmgr 2>/dev/null)
mylog result "${result}"

mylog info "Getting the list of the queues" 0
decho 4 "curl -k -u \"${mqadmin}:${mqpwd}\" ${std_headers} ${rest_endpoint}/ibmmq/rest/v1/admin/qmgr/${lf_qmgr}/queue 2>/dev/null"
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" ${rest_endpoint}/ibmmq/rest/v1/admin/qmgr/${lf_qmgr}/queue 2>/dev/null)
mylog result "${result}"

mylog info "Get channels for the ${lf_qmgr} queue manager" 0
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" "${rest_endpoint}/ibmmq/rest/v1/admin/qmgr/${lf_qmgr}/channel" 2>/dev/null)
mylog result "${result}"

mylog info "Post a message to the queue ${lf_q} in the ${lf_qmgr} queue manager" 0
mq_msg="Test message $(date +'%A, %d-%m-%Y %H:%M:%S')"
decho 4 "curl -k -u \"${mquser}:${mqpwd}\"  ${std_headers} -H \"content-type: text/plain; charset=utf-8\" -H \"ibm-mq-md-expiry: unlimited\" -H \"ibm-mq-md-priority: 9\" -H \"ibm-mq-md-persistence: persistent\" -d \"${mq_msg}\" \"${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${lf_qmgr}/queue/${lf_q}/message\" 2>/dev/null"
result=$(curl -k -u "${mquser}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" -H "content-type: text/plain; charset=utf-8" -H "ibm-mq-md-expiry: unlimited" -H "ibm-mq-md-priority: 9" -H "ibm-mq-md-persistence: persistent" -d "${mq_msg}" "${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${lf_qmgr}/queue/${lf_q}/message" 2>/dev/null)
mylog result "${result}"

mylog info "Get a message from the queue ${lf_q} in the ${lf_qmgr} queue manager" 0
decho 4 "curl -k -u \"${mquser}:${mqpwd}\" ${std_headers} \"${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${lf_qmgr}/queue/${lf_q}/message\" 2>/dev/null"
result=$(curl -k -u "${mquser}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" "${rest_endpoint}/ibmmq/rest/v3/messaging/qmgr/${lf_qmgr}/queue/${lf_q}/message" 2>/dev/null)
mylog result "${result}"

mylog info "Get installation" 0
result=$(curl -k -u "${mqadmin}:${mqpwd}" -H "accept: application/json; charset=utf-8" -H "ibm-mq-rest-csrf-token: blank" "${rest_endpoint}/ibmmq/rest/v3/admin/installation" 2>/dev/null)
mylog result "${result}"
