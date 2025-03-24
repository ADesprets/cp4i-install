###########################################################
# install_networkpolicies function for License Service
# https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license
function install_networkpolicies() {
  trace_in 5 install_networkpolicies

  # applying network policies
  mylog info "Applying network policies for IBM License service" 
  check_create_oc_yaml "NetworkPolicy" "egress-ibm-licensing-operator" "${MY_RESOURCESDIR}" "${MY_LICENSE_SERVICE_WORKINGDIR}" "${MY_LICENSE_SERVICE_BEDROCK_EGRESS_OPERATOR_FILE}" "${MY_LICENSE_SERVICE_NAMESPACE}"
  check_create_oc_yaml "NetworkPolicy" "egress-ibm-licensing-service-instance" "${MY_RESOURCESDIR}" "${MY_LICENSE_SERVICE_WORKINGDIR}" "${MY_LICENSE_SERVICE_BEDROCK_EGRESS_INSTANCE_FILE}" "${MY_LICENSE_SERVICE_NAMESPACE}"

  trace_out 5 install_networkpolicies
}

################################################
# search_networkpolicies function
# Search for deny-all or allow-same-namespace networkpolicies
function search_networkpolicies() {
  trace_in 5 search_networkpolicies

  local lf_res lf_deny_all lf_allow_same_namespace
  #mylog info "==== Searching for deny-all or allow-same-namespace networkpolicies." 1>&2

  # Search for deny-all networkpolicies
  mylog info "Searching for deny-all networkpolicies..." 1>&2
  lf_deny_all=$(oc get networkpolicy --all-namespaces -o json | jq '.items[] | select(.spec.ingress == null and .spec.egress == null) | {namespace: .metadata.namespace, name: .metadata.name}')

  # Search for allow-same-namespace networkpolicies
  mylog info "Searching for allow-same-namespace networkpolicies..." 1>&2
  lf_allow_same_namespace=$(oc get networkpolicy --all-namespaces -o json | jq '.items[] | select(.spec.ingress != null and .spec.ingress[].from[]?.namespaceSelector.matchLabels."project" == .metadata.namespace) | {namespace: .metadata.namespace, name: .metadata.name}')

  if [[ -n $lf_deny_all ]] || [[ -n $lf_allow_same_namespace ]]; then
    lf_res=1
  else
    lf_res=0
  fi

  trace_out 5 search_networkpolicies
  return $lf_res
}

################################################
# trace_in function
# @param 1: function name
#
function trace_in() {
  local lf_in_tracelevel=$1
  local lf_in_function_name=$2

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments : the tracelevel and the function name"
    exit  1
  fi  

  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho $lf_in_tracelevel "F:IN :$lf_in_function_name"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR_INSIDE_FUNCTION))
}

################################################
# trace_out function
# @param 1: function name
#
function trace_out() {
  local lf_in_tracelevel=$1
  local lf_in_function_name=$2

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments : the tracelevel and the function name"
    exit  1
  fi

  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR_INSIDE_FUNCTION))
  decho $lf_in_tracelevel "F:OUT:$lf_in_function_name"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# encode_b64_file function
# @param 1: 
# return the encoded (base64) input parameter
#
function encode_b64_file() {
  local lf_in_file=$1
  local lf_encoded=""

  lf_encoded=$(cat $lf_in_file | base64 -w 0)
  echo $lf_encoded
}

################################################
# simple logging with colors
# @param 1: level (info/error/warn/wait/check/ok/no)
function mylog() {

  local lf_in_level=$1
  local lf_in_text=$2
  local lf_in_indent_level=$3 

  local lf_spaces=$(printf "%0.s " $(seq 1 $SC_SPACES_COUNTER))

  # prefix
  local p=
  # do not output the trailing newline
  local w=
  # suffix
  local s=
  case $lf_in_level in
    info)    c=2;;          #green
    error)   c=1            #red
             p='ERROR: ';;
    warn)    c=3;;          #yellow
    debug)   c=8            #grey
             p='CMD: ';; 
    wait)    c=4            #purple
             p="$(date) ";;
    check)   c=6            #cyan
             s=...;; 
    ok)      c=2            #green
             #w=-n
             p=OK;;
    no)      c=3            #yellow
             p=NO;;  
    default) c=9            #default
             p='';;
  esac
  
  if [[ -z $lf_in_indent_level ]]; then
    echo -e $w "$(tput setaf $c)$lf_spaces$p$2$s$(tput setaf 9)\t"
  else
    echo -e $w "$(tput setaf $c)$p$2$s$(tput setaf 9)\t"
  fi
}

################################################
# assert that variable is defined
# @param 1 name of variable
# @param 2 error message, or name of method to call if begins with "fix"
function var_fail() {
  if eval test -z '$'$1; then
    mylog error "missing config variable: $1" 1>&2
    case "$2" in
    fix* | echo*) eval $2 ;;
    "") ;;
    *) mylog log "$2" 1>&2 ;;
    esac
    exit 1
  fi
}

#########################################################################
# Print message with levels
# @param 1:
# @param 2:
function decho () {
  local lf_in_messagelevel=$1
  shift 1

  if [[ -n $ADEBUG ]]; then
    if [[ $TRACELEVEL -ge $lf_in_messagelevel ]]; then
      mylog debug "$@"
    fi
  fi
}

################################################
# Compare versions
# from chatgpt
# Compare two version strings as arguments and compares them component-wise.
# It uses the IFS (Internal Field Separator) to split the versions into components based on the dot ('.') separator.
# It then compares each component, determining whether the first version is older, newer, or equal to the second version.
# The script will output whether the first version is older, newer, or equal to the second version.
# cmp_versions v1 v2 returns 0 if v1=v2, 1 if v1 is older than v2, 2 if v1 is newer than v2
function cmp_versions() {
  trace_in 5 cmp_versions

  local lf_in_version1=$1
  local lf_in_version2=$2
  decho 5 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments : version1 and version2"
    trace_out 3 cmp_versions
    exit  1
  fi

  # Just try to compare the versions using string comparison if they are equal
  if [[ "$lf_in_version1" == "$lf_in_version2" ]]; then
    #echo "$lf_in_version1 is equal to $lf_in_version2"
    trace_out 5 cmp_versions
    return 0
  fi

  IFS='.' read -ra v1_components <<<"$lf_in_version1"
  IFS='.' read -ra v2_components <<<"$lf_in_version2"

  local lf_len=${#v1_components[@]}
  local lf_res=0

  for ((i = 0; i < $lf_len; i++)); do
    v1=${v1_components[i]:-0}
    v2=${v2_components[i]:-0}

    if [[ $v1 -lt $v2 ]]; then
      #echo "$lf_in_version1 is older than $lf_in_version2"
      lf_res=1
      break
    elif [[ $v1 -gt $v2 ]]; then
      #echo "$lf_in_version1 is newer than $lf_in_version2"
      lf_res=2
      break
    fi
  done

  trace_out 5 cmp_versions
  return $lf_res
}

################################################
# Save a certificate in pem format from secret
# @param 1: namespace where the secret exist
# @param 2: name of the secret
# @param 3: Data in the secret that contains the certificate
# @param 4: Directory where to save the certificate
function save_certificate() {
  trace_in 5 save_certificate

  local lf_in_ns=$1
  local lf_in_secret_name=$2
  local lf_in_data_name=$3
  local lf_in_destination_path=$4
  decho 5 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|"

  if [[ $# -ne 4 ]]; then
    mylog error "You have to provide 4 arguments : namespace, secret_name, data_name and destination directory path"
    trace_out 5 save_certificate
    exit  1
  fi

  local lf_data_normalised=$(sed 's/\./\\./g' <<< ${lf_in_data_name})

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"
  decho 6 "oc -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath=\"{.data.$lf_data_normalised}\""
  local lf_cert=$(oc -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath="{.data.$lf_data_normalised}")

  echo $lf_cert | base64 --decode >"${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"

  trace_out 5 save_certificate
}

################################################
# Check that the CASE is already downloaded
# example pour filtrer avec conditions :
# avec jsonpath=$.[?(@.name=='ibm-licensing' && @.version=='4.2.1')]
# Pour tester une variable null : https://stackoverflow.com/questions/48261038/shell-script-how-to-check-if-variable-is-null-or-no
# @param 1:
# @param 2:
function is_case_downloaded() {
  trace_in 5 is_case_downloaded

  local lf_in_case=$1
  local lf_in_version=$2
  decho 5 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments : case and version"
    trace_out 3 is_case_downloaded
    exit  1
  fi

  local lf_latestversion lf_cmp lf_res
  local lf_directory="${MY_IBMPAK_CASESDIR}${lf_in_case}/${lf_in_version}"

  if [[ ! -d "${lf_directory}" ]]; then
    lf_res=0
  else
    lf_result=$(oc ibm-pak list --downloaded -o json)

    # One of the simplest ways to check if a string is empty or null is to use the -z and -n operators.
    # The -z operator returns true if the string is null or empty, and false otherwise.
    # The -n operator returns true if the string is not null or empty, and false otherwise.
    if [[ -z $lf_result ]]; then
      lf_res=0
    else
      # Pb avec le passage de variables à jsonpath ; décision retour vers jq
      lf_result=$(echo $lf_result | jq -r --arg case "$lf_in_case" '[.[] | select (.name == $case )]')
      if [[ -z $lf_result ]]; then
        lf_res=0
      else
        lf_latestversion=$(echo $lf_result | jq -r max_by'(.latestVersion)|.latestVersion')
        
        decho 3 "lf_latestversion=$lf_latestversion"

        cmp_versions $lf_latestversion $lf_in_version
        lf_cmp=$?
        decho 3 "lf_cmp=$lf_cmp"
        case $lf_cmp in
        0) lf_res=1;;
        2) mylog info "newer version of case $lf_in_case is available. Current version=$lf_in_version. Latest version=$lf_latestversion"
           lf_res=1;;
        esac
      fi
    fi
  fi

  trace_out 5 is_case_downloaded
  return $lf_res
}

################################################
# Check that all required executables are installed
# @param 1:
function check_command_exist() {
  trace_in 5 check_command_exist

  local lf_in_command=$1
  decho 5 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument : command name"
    trace_out 3 check_command_exist
    exit  1
  fi

  if ! command -v $lf_in_command >/dev/null 2>&1; then
    mylog error "Executable $lf_in_command does not exist or is not executable, exiting."
    exit 1
  fi

  trace_out 5 check_command_exist
}

######################################################
# checks if the file exist, if no print a msg and exit
# @param 1:
function check_file_exist() {
  trace_in 5 check_file_exist

  local lf_in_file=$1
  decho 5 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument : file name"
    trace_out 5 check_file_exist
    exit  1
  fi

  if [[ ! -e $lf_in_file ]]; then
    mylog error "No such file: $lf_in_file" 1>&2
    exit 1
  fi

  trace_out 5 check_file_exist
}

######################################################
# checks if the directory exist, if no print a msg and exit
# @param 1:
function check_directory_exist() {
  trace_in 5 check_directory_exist

  local lf_in_directory=$1
  decho 5 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument : directory name"
    trace_out 3 check_directory_exist
    exit  1
  fi

  if [[ ! -d $lf_in_directory ]]; then
    mylog error "No such directory: $lf_in_directory" 1>&2
    exit 1
  fi

  trace_out 5 check_directory_exist
}

######################################################
# checks if the directory contains files, if no print a msg and exit
# @param 1:
function check_directory_contains_files() {
  local lf_in_directory=$1  
  local lf_files
  shopt -s nullglob dotglob # To include hidden files
  lf_files=$(find . -maxdepth 1 -type f | wc -l)

  return $lf_files
}

######################################################
# checks if the directory exist, otherwise create it
# @param 1: directory name
function check_directory_exist_create() {
  trace_in 5 check_directory_exist_create

  local lf_in_directory=$1
  decho 5 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument : directory name"
    trace_out 3 check_directory_exist_create
    exit  1
  fi

  if [[ ! -d $lf_in_directory ]]; then
    mkdir -p $lf_in_directory
  fi

  trace_out 5 check_directory_exist_create
}

################################################
# 
# @param 1:
function read_config_file() {
  trace_in 5 read_config_file

  local lf_in_config_file=$1
  decho 5 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument: file name"
    trace_out 3 read_config_file
    exit  1
  fi

  check_file_exist $lf_in_config_file

  # load user specific variables, "set -a" so that variables are part of environment for envsubst set -a: Turns on automatic export for variables and set +a: Turns off automatic export for variables.
  set -a
  . "${lf_in_config_file}"
  set +a

  trace_out 5 read_config_file
}

################################################
# Check that all required executables are installed
# No parameters.
function check_exec_prereqs() {
  trace_in 3 check_exec_prereqs

  check_command_exist awk
  check_command_exist tr
  check_command_exist curl
  check_command_exist $MY_CONTAINER_ENGINE
  check_command_exist ibmcloud
  check_command_exist jq
  check_command_exist yq
  check_command_exist keytool
  check_command_exist oc
  check_command_exist "oc ibm-pak"
  check_command_exist openssl
  check_command_exist mvn

  if $MY_MQ_CUSTOM; then
    check_command_exist runmqakm
  fi

  if $MY_LDAP; then
    check_command_exist ldapsearch
    check_resource_exist storageclass $MY_FILE_LDAP_STORAGE_CLASS
  fi

  if $MY_APIC_GRAPHQL; then
    check_command_exist helm
  fi
  
  trace_out 3 check_exec_prereqs
}

################################################
# Check that the resource exists
# @param the resource to be checked
# @param 1: resource type
# @param 2: resource name
function check_resource_exist() {
  trace_in 5 check_resource_exist

  local lf_in_type=$1
  local lf_in_name=$2
  decho 5 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments: resource type and resource name"
    trace_out 5 check_resource_exist
    exit  1
  fi

  # check resource exist
  local lf_res
  
  lf_res=$(oc get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  if test -z $lf_res; then
    mylog error "Resource $lf_in_name of type $lf_in_type does not exist, exiting."
    exit 1
  fi

  trace_out 5 check_resource_exist
}

################################################
# Wait n secs
# @param secs: number of seconds to wait for and displays it on the same line
# @param 1:

function waitn() {
  local lf_in_secs=$1
  mylog info "Sleeping $lf_in_secs"
  while [ $lf_in_secs -gt 0 ]; do
    echo -ne "$lf_in_secs\033[0K\r"
    sleep 1
    : $((lf_in_secs--))
  done
}

################################################
# wait for command to return specified value
# @param 1: what description of waited state
# @param 2: value expected state value from check command
# @param 3: command executed command that returns some state
function wait_for_state() {
  trace_in 3 wait_for_state

  local lf_in_what=$1
  local lf_in_value=$2
  local lf_in_command=$3
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments: description of waited state, value expected and command"
    trace_out 3 wait_for_state
    exit  1
  fi

  local lf_start_time=$(date +%s)
  local lf_current_time lf_elapsed_time lf_last_state lf_current_state lf_bullet
  local lf_bullets=('|' '/' '-' '\\')

  lf_last_state=''
  while true; do
    lf_current_state=$(eval $lf_in_command)
    if [[ "$lf_current_state" == "$lf_in_value" ]]; then
      break
    fi

    if [[ "$lf_last_state" != "$lf_current_state" ]]; then
      mylog wait "$lf_current_state"
      lf_last_state=$lf_current_state
    fi

    for lf_bullet in "${lf_bullets[@]}"; do
      # Use echo with -ne to print without newline and with escape sequences
      lf_current_time=$(date +%s)
  
      # Calculate the elapsed time
      lf_elapsed_time=$((lf_current_time - lf_start_time))
  
      # Display the elapsed time on the same line
      echo -ne "\rElapsed time: ${lf_elapsed_time} seconds$lf_bullet"      
      #echo -ne "\r$lf_bullet Timer: $seconds seconds | Waiting...\033[0K\r"
      # Sleep for a short interval to control the speed of the animation
      sleep 0.1
    done 
  done

  trace_out 3 wait_for_state
}

################################################
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
function add_ibm_entitlement() {
  trace_in 5 add_ibm_entitlement

  local lf_in_ns=$1
  decho 3 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument: namespace"
    trace_out 5 add_ibm_entitlement
    exit  1
  fi

  mylog check "Checking ibm-entitlement-key in $lf_in_ns"
  if ! oc -n $lf_in_ns get secret ibm-entitlement-key >/dev/null 2>&1; then
    var_fail MY_ENTITLEMENT_KEY "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    $MY_CONTAINER_ENGINE -h >/dev/null 2>&1
    if test $? -eq 0 && ! echo $MY_ENTITLEMENT_KEY | $MY_CONTAINER_ENGINE login cp.icr.io --username cp --password-stdin; then
      mylog error "Invalid entitlement key" 1>&2
      trace_out 5 add_ibm_entitlement
      exit 1
    fi

    mylog info "Adding ibm-entitlement-key to $lf_in_ns"
    if ! oc -n $lf_in_ns create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io; then
      trace_out 5 add_ibm_entitlement
      exit 1
    fi
  fi

  trace_out 5 add_ibm_entitlement
}

################################################
# Check if the resource of type octype with name name exists in the namespace ns.
# If it does not exist use the yaml file, with the appropriate variable.
# @param 1: octype: kubernetes resource class, example: "subscription"
# @param 2: name: name of the resource, example: "ibm-integration-platform-navigator"
# @param 3: dir: the source directory example: "${subscriptionsdir}"
# @param 4: dir: the target directory example: "${workingdir}apic/"
# @param 5: yaml: the file with the definition of the resource, example: "Navigator-Sub.yaml"
# @param 6: namespace
function check_create_oc_yaml() {
  trace_in 4 check_create_oc_yaml

  local lf_in_type="$1"
  local lf_in_cr_name="$2"
  local lf_in_source_directory="$3"
  local lf_in_target_directory="$4"
  local lf_in_yaml_file="$5"
  local lf_in_namespace="$6"
  decho 4 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|\"$6\"|"

  if [[ $# -ne 6 ]]; then
    mylog error "You have to provide 6 arguments: type, resource, source directory, destination directory, yaml file and namespace"
    trace_out 4 check_create_oc_yaml
    exit  1
  fi
  
  check_file_exist "${lf_in_source_directory}${lf_in_yaml_file}"

  adapt_file $lf_in_source_directory $lf_in_target_directory $lf_in_yaml_file

  if $MY_APPLY_FLAG; then
    mylog check "Creating or Updating ${lf_in_cr_name}/${lf_in_type}"
    oc apply -f "${lf_in_target_directory}${lf_in_yaml_file}" || exit 1
    wait_for_resource $lf_in_type $lf_in_cr_name $lf_in_namespace
  fi

  trace_out 4 check_create_oc_yaml
}

################################################
# 
# @param 1: namespace
function provision_persistence_openldap() {
  trace_in 3 provision_persistence_openldap

  # handle persitence for Openldap
  # only check one, assume that if one is created the other one is also created (short cut to optimize time)
  export VAR_NAMESPACE=$VAR_LDAP_NAMESPACE

  # create PVCs for LDAP
  create_operand_instance "PersistentVolumeClaim" "${MY_LDAP_PVC_MAIN}" "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_pvc.main.yaml" "$VAR_LDAP_NAMESPACE" "{.status.phase}" "Bound"

  create_operand_instance "PersistentVolumeClaim" "${MY_LDAP_PVC_CONFIG}" "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_pvc.config.yaml" "$VAR_LDAP_NAMESPACE" "{.status.phase}" "Bound"

  unset VAR_NAMESPACE

  trace_out 3 provision_persistence_openldap
}

################################################
# @param 1: octype: kubernetes resource class, example: "subscription"
# @param 2: name: name of the resource, example: "ibm-integration-platform-navigator"
# @param 3: service account 
# @param 4: namespace
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
function deploy_openldap() {
  trace_in 3 deploy_openldap

  local lf_in_type="$1"
  local lf_in_name="$2"
  local lf_in_serviceaccount="$3"
  local lf_in_namespace="$4"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|"

  if [[ $# -ne 4 ]]; then
    mylog error "You have to provide 4 arguments: type, resource, service account and namespace"
    trace_out 3 deploy_openldap
    exit  1
  fi


  mylog info "Creating LDAP server"
  create_oc_resource "ServiceAccount" "$MY_LDAP_SERVICEACCOUNT" "${MY_RESOURCESDIR}" "${MY_LDAP_WORKINGDIR}" "serviceaccount.yaml" "$VAR_LDAP_NAMESPACE"
  oc adm policy add-scc-to-user privileged system:serviceaccount:${lf_in_namespace}:${MY_LDAP_SERVICEACCOUNT}
  oc adm policy add-scc-to-user anyuid system:serviceaccount:${lf_in_namespace}:${MY_LDAP_SERVICEACCOUNT}
  #oc adm policy add-scc-to-group anyuid system:serviceaccounts:${lf_in_namespace}

  # deploy openldap and take in account the PVCs just created
  # check that deployment of openldap was not done
  create_oc_resource "Deployment" "${lf_in_name}" "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_deployment.yaml" "$lf_in_namespace"
  oc -n ${lf_in_namespace} get deployment.apps/openldap -o json | jq '. | del(."status")' >${MY_LDAP_WORKINGDIR}openldap.json

  read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
  adapt_file "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_config.json" 
  oc -n ${lf_in_namespace} patch deployment.apps/openldap --patch-file "${MY_LDAP_WORKINGDIR}ldap_config.json"

  trace_out 3 deploy_openldap
}

################################################
# @param 1: octype: kubernetes resource class, example: "deployment"
# @param 2: ocname: name of the resource, example: "mailhog"
# @param 3:
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
# To add a user/password protection to the web UI: https://stackoverflow.com/questions/60162842/how-can-i-add-basic-authentication-to-the-mailhog-service-in-ddev-local
function deploy_mailhog() {
  trace_in 3 deploy_mailhog

  local lf_in_type="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments: type, resource, and namespace"
    trace_out 3 deploy_mailhog
    exit  1
  fi

  # check if deploment already performed
  mylog check "Checking ${lf_in_name}/${lf_in_type} in ${lf_in_namespace}"
  if ! oc -n ${lf_in_namespace} get ${lf_in_type} ${lf_in_name} >/dev/null 2>&1; then
    mylog check "Checking service ${lf_in_name} in ${lf_in_namespace}"
    if ! oc -n ${lf_in_namespace} get service ${lf_in_name} >/dev/null 2>&1; then
      mylog info "Creating mailhog server"
      oc -n ${lf_in_namespace} new-app ${lf_in_name}/${lf_in_name}
    fi
  fi

  trace_out 3 deploy_mailhog
}

#===========================================
# Add entry in LDAP if it doesn't exist
# @param 1: LDAP Server
# @param 2: user DN
# @param 3: user password
# @param 4: Base entry
# @param 5:
# @param 6:
function add_ldap_entry_if_not_exists() {
  trace_in 4 add_ldap_entry_if_not_exists

  local lf_in_ldap_server="$1"
  local lf_in_admin_dn="$2"
  local lf_in_admin_password="$3"
  local lf_in_entry_dn="$4"
  local lf_in_entry_content="$5"
  local lf_in_tmp_ldif_file="$6"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|\"$6\"|"

  if [[ $# -ne 6 ]]; then
    mylog error "You have to provide 6 arguments: ldap server, admin DN, admin password, entry DN, entry content and ldif file"
    trace_out 4 add_ldap_entry_if_not_exists
    exit  1
  fi

  # Check if entry exists
  local lf_in_search_result
  lf_in_search_result=$(ldapsearch -x -H $lf_in_ldap_server -D "$lf_in_admin_dn" -w $lf_in_admin_password -b "$lf_in_entry_dn" -s base "(objectClass=*)")
  # Check if the entry already exists
  if [[ -n $lf_in_search_result ]]; then
    if echo "$lf_in_search_result" | grep -q "dn: $lf_in_entry_dn"; then
      mylog info "Entry $lf_in_entry_dn already exists. Skipping."
    else
      decho 3 "Entry $lf_in_entry_dn does not exist. Adding entry."
      echo "$lf_in_entry_content" > $lf_in_tmp_ldif_file
      ldapadd -x -H $lf_in_ldap_server -D "$lf_in_admin_dn" -w $lf_in_admin_password -f $lf_in_tmp_ldif_file
    fi
  fi

  trace_out 4 add_ldap_entry_if_not_exists
}

#========================================================
# add ldif file entries if each doesn't exist
# @param 1:
# @param 2:
# @param 3:
# @param 4:
function add_ldif_file () {
  trace_in 4 add_ldif_file

  local lf_in_ldap_server="$1"
  local lf_in_admin_dn="$2"
  local lf_in_admin_password="$3"
  local lf_in_ldif_file="$4"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|"

  if [[ $# -ne 4 ]]; then
    mylog error "You have to provide 4 arguments: ldap server, admin DN, admin password and ldif file"
    trace_out 4 add_ldif_file
    exit  1
  fi

  local lf_tmp_ldif="${MY_WORKINGDIR}temp_entry.ldif"
  local lf_line lf_entry_dn lf_entry_content

  # Read the LDIF file and process each entry
  while IFS= read -r lf_line; do
    # Collect lines of a single LDIF entry
    if [[ -z "$lf_line" ]]; then
      # Empty line indicates end of an entry
      if [[ -n "$lf_entry_dn" && -n "$lf_entry_content" ]]; then
        add_ldap_entry_if_not_exists "$lf_in_ldap_server" "$lf_in_admin_dn" "$lf_in_admin_password" "$lf_entry_dn" "$lf_entry_content" "$lf_tmp_ldif"
        lf_entry_dn=""
        lf_entry_content=""
      fi
    else
      # Accumulate the DN and content of the entry
      if [[ "$lf_line" =~ ^dn:\ (.*) ]]; then
        lf_entry_dn="${BASH_REMATCH[1]}"
      fi
      lf_entry_content+="$lf_line"$'\n'
    fi
  done < $lf_in_ldif_file
  
  # Process the last entry if the file doesn't end with a new line
  if [[ -n "$lf_entry_dn" && -n "$lf_entry_content" ]]; then
    add_ldap_entry_if_not_exists "$lf_in_ldap_server" "$lf_in_admin_dn" "$lf_in_admin_password" "$lf_entry_dn" "$lf_entry_content" "$lf_tmp_ldif"
  fi
  
  # Clean up temporary file
  #rm -f $lf_tmp_ldif

  trace_out 4 add_ldif_file
}

################################################
# create the ldap service and route
# @param 1: name: name of the resource, example: "openldap"
# @param 2: dir: the source directory example: "${subscriptionsdir}"
# @param 3: dir: the target directory example: "${workingdir}ldap/"
# @param 4: file
# @param 5: namespace: the namespace to use
#
function create_expose_service_openldap() {
  trace_in 3 create_expose_service_openldap

  local lf_in_source_directory="$1"
  local lf_in_target_directory="$2"
  local lf_in_file="$3"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments : source directory, target directory and file"
    trace_out 3 create_expose_service_openldap
    exit  1
  fi

  # Create the service to expose the openldap server
  create_oc_resource "Service" "${VAR_LDAP_SERVICE}" "$lf_in_source_directory" "${lf_in_target_directory}" "$lf_in_file" "${VAR_LDAP_NAMESPACE}"

  # expose service externaly and get host and port
  oc -n ${VAR_LDAP_NAMESPACE} get service ${VAR_LDAP_SERVICE} -o json | \
     jq '.spec.ports |= map(if .name == "389-tcp" then . + { "nodePort": 30389 } else . end)' | \
     jq '.spec.ports |= map(if .name == "636-tcp" then . + { "nodePort": 30686 } else . end)' >${lf_in_target_directory}openldap-service.json

  # Saad there was a bug the openldap-service.json did not exist when those two calls were made in the deploy_openldap function, I moved them here
  # I do not think all this code is needed, what did you want to do?
  oc -n ${VAR_LDAP_NAMESPACE} patch service/${VAR_LDAP_SERVICE} --patch-file ${lf_in_target_directory}openldap-service.json

  export VAR_LDAP_PORT=$(oc -n ${VAR_LDAP_NAMESPACE} get service ${VAR_LDAP_SERVICE} -o jsonpath='{.spec.ports[0].nodePort}')
  lf_port1=$(oc -n ${VAR_LDAP_NAMESPACE} get service ${VAR_LDAP_SERVICE} -o jsonpath='{.spec.ports[1].nodePort}')

  mylog info "Expose service ${VAR_LDAP_SERVICE} using port ${VAR_LDAP_PORT} to the route ${VAR_LDAP_ROUTE}."
  oc -n ${VAR_LDAP_NAMESPACE} expose service ${VAR_LDAP_SERVICE} --name=${VAR_LDAP_ROUTE} --port=${VAR_LDAP_PORT}

  export VAR_LDAP_HOSTNAME=$(oc -n ${VAR_LDAP_NAMESPACE} get route ${VAR_LDAP_ROUTE} -o jsonpath='{.spec.host}')

  trace_out 3 create_expose_service_openldap
}

################################################
# @param 1: dir: the source directory example: "${subscriptionsdir}"
# @param 2: dir: the target directory example: "${workingdir}ldap/"
# @param 3: ldif file
function load_users_2_ldap_server() {
  trace_in 4 load_users_2_ldap_server

  local lf_in_source_directory="$1"
  local lf_in_target_directory="$2"
  local lf_in_file="$3"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments : source directory, target directory and ldif file"
    trace_out 4 load_users_2_ldap_server
    exit  1
  fi

  if [[ -z $VAR_LDAP_HOSTNAME ]] || [[ -z $VAR_LDAP_PORT ]]; then
    mylog error "ldap hostname or port are null"
    trace_out 4 load_users_2_ldap_server
    exit  1
  fi

  # load users and groups into LDAP
  adapt_file "$lf_in_source_directory" "${lf_in_target_directory}" "${lf_in_file}"

  mylog info "Adding LDAP entries using the function add_ldif_file"
  add_ldif_file "ldap://${VAR_LDAP_HOSTNAME}:${VAR_LDAP_PORT}" "${MY_LDAP_ADMIN_DN}" "${MY_LDAP_ADMIN_PASSWORD}" "${lf_in_target_directory}${lf_in_file}" 

  mylog info "You can search entries with the following command: "
  mylog info "ldapsearch -H ldap://${VAR_LDAP_HOSTNAME}:${VAR_LDAP_PORT} -x -D \"$MY_LDAP_ADMIN_DN\" -w \"$MY_LDAP_ADMIN_PASSWORD\" -b \"$MY_LDAP_BASE_DN\" -s sub -a always -z 1000 \"(objectClass=*)\""

  trace_out 4 load_users_2_ldap_server
}

################################################
# @param 1: name: name of the resource, example: "mailhog"
# @param 2: namespace: the namespace to use
function expose_service_mailhog() {
  trace_in 3 expose_service_mailhog

  local lf_in_cr_name="$1"
  local lf_in_port="$2"
  local lf_in_namespace="$3"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments: resource name, port and namespace"
    trace_out 3 expose_service_mailhog
    exit  1
  fi

  # expose service externaly and get host and port
  # Check if the service is already exposed
  if oc -n ${lf_in_namespace} get route ${lf_in_cr_name} >/dev/null 2>&1; then
    mylog info "Service ${lf_in_cr_name} is already exposed."
  else
    mylog info "Service ${lf_in_cr_name} is not exposed."
    oc -n ${lf_in_namespace} expose svc/${lf_in_cr_name} --port=${lf_in_port} --name=${lf_in_cr_name}
  fi
  lf_hostname=$(oc -n ${lf_in_namespace} get route ${lf_in_cr_name} -o jsonpath='{.spec.host}')
  decho 3 "MailHog accessible at ${lf_hostname}"

  trace_out 3 expose_service_mailhog
}

################################################
# Create project
# @param 1: ns namespace to be created
# @param 2: display name of the project
# @param 3: description of the project
# @param 4: working directory where the generated yaml file will be stored
function create_project() {
  trace_in 3 create_project

  local lf_in_name="$1"
  local lf_in_display_name="$2"
  local lf_in_description="$3"
  local lf_in_source_directory="$4"
  local lf_in_target_directory="$5"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|"

  if [[ $# -ne 5 ]]; then
    mylog error "You have to provide 5 arguments: resource name, display name; description, source directory and target directory"
    trace_out 3 create_project
    exit  1
  fi

  export VAR_NAMESPACE=$lf_in_name
  export VAR_NAMESPACE_DISPLAYNAME=$lf_in_display_name
  export VAR_NAMESPACE_DESCRIPTION=$lf_in_description

  var_fail lf_in_name "Please define project name in config"
  mylog check "Checking project $lf_in_name"
  if ! oc get project $lf_in_name >/dev/null 2>&1; then 
    mylog info "Creating project $lf_in_name"
    adapt_file ${lf_in_source_directory} ${lf_in_target_directory} project.yaml
    if $MY_APPLY_FLAG; then
      oc apply -f "${lf_in_target_directory}project.yaml"
      if [[ $? -ne 0 ]]; then 
        unset VAR_NAMESPACE VAR_NAMESPACE_DISPLAYNAME VAR_NAMESPACE_DESCRIPTION
        trace_out 3 create_project
       exit 1
      fi
    fi    
  fi

  unset VAR_NAMESPACE VAR_NAMESPACE_DISPLAYNAME VAR_NAMESPACE_DESCRIPTION
  trace_out 3 create_project
}

################################################
# wait for availability of the resource
# @param 1: resource type
# @param 2: resource name 
# @param 3: namespace
function wait_for_resource() {
  trace_in 3 wait_for_resource

  local lf_in_type=$1
  local lf_in_cr_name=$2
  local lf_in_namespace=$3
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments: type, resource name and namespace"
    trace_out 3 wait_for_resource
    exit  1
  fi

  seconds=0
  while [[ -z $lf_resource ]]; do
    echo -ne "Timer: $seconds seconds | waiting for $lf_in_cr_name/$lf_in_type in project $lf_in_namespace...\033[0K\r"
    sleep 1
    lf_resource=$(oc -n $lf_in_namespace get $lf_in_type -o json | jq -r --arg my_resource "$lf_in_cr_name" '.items[].metadata | select (.name == $my_resource).name')
    seconds=$((seconds + 1))
  done
  echo 
  export VAR_RESOURCE=$lf_resource

  trace_out 3 wait_for_resource
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
# @param 1: the case name
# @param 2: the operator name (in most cases it's the same as the case name
# @param 3: This is the arch (amd64 for example)
# @param 4: This is the version of the channel. It is an optional parameter, if ommited it is retrieved, else used values from invocation
function check_add_cs_ibm_pak() {
  trace_in 3 check_add_cs_ibm_pak

  local lf_in_case_name="$1"
  local lf_in_operator_name="$2"
  local lf_in_arch="$3"
  local lf_in_case_version="$4"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|"

  if [[ $# -ne 3 && $# -ne 4 ]] ; then
    mylog error "You have to provide 3 or 4 arguments: case name, operator name, arch and optional case version"
    trace_out 3 check_add_cs_ibm_pak
    exit  1
  fi

  local lf_type lf_file lf_file_tmp1 lf_file_tmp2 lf_downloaded lf_display_name

  #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
  if [[ -z $lf_in_case_version ]]; then
    read lf_case_version lf_app_version < <(oc ibm-pak list  -o json | jq -r --arg case "$lf_in_case_name" '.[] | select(.name == $case) | "\(.latestVersion) \(.latestAppVersion)"')
  else
    lf_case_version=$lf_in_case_version
    lf_app_version=$(oc ibm-pak list --case-name $lf_in_case_name -o json | jq --arg v "$lf_in_case_version" '.versions[$v].appVersion')
  fi
  decho 3 "lf_case_version=$lf_case_version|lf_app_version=$lf_app_version"
  export VAR_APP_VERSION=$lf_app_version

  is_case_downloaded ${lf_in_case_name} ${lf_case_version} #1>&2 > /dev/null
  lf_downloaded=$?
  decho 4 "lf_downloaded=$lf_downloaded"

  if [[ $lf_downloaded -eq 1 ]]; then
    mylog info "case ${lf_in_case_name} ${lf_case_version} already downloaded"
  else
    oc ibm-pak get ${lf_in_case_name} --version ${lf_case_version}
    oc ibm-pak generate mirror-manifests ${lf_in_case_name} icr.io --version ${lf_case_version}
  fi

  lf_file_tmp1=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources.yaml
  lf_file_tmp2=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources-linux-${lf_in_arch}.yaml

  if [[ -e $lf_file_tmp1 ]]; then
    lf_file=$lf_file_tmp1
    lf_display_name="${lf_in_case_name}-${lf_case_version}"
  elif [[ -e $lf_file_tmp2 ]]; then
    lf_file=$lf_file_tmp2
    lf_display_name="${lf_in_case_name}-${lf_case_version}-linux-${lf_in_arch}"
  else
    mylog error "No catalog source file found for case ${lf_in_case_name} ${lf_case_version}"
    exit 1
  fi

  # Getting the id of the catalogsource, using head -n 1 to get only one value in case of many
  lf_type="CatalogSource"
  decho 3 "lf_file=$lf_file|lf_display_name=$lf_display_name"
  #local lf_catalogsource=$(yq "select(.spec.displayName == \"$lf_display_name\") | .metadata.name" $lf_file | head -n 1)
  local lf_catalogsource=$(yq -o=json ". | select(.spec.displayName == \"$lf_display_name\") | .metadata.name" "$lf_file")

  decho 3 "lf_catalogsource=$lf_catalogsource"
  export VAR_CATALOG_SOURCE=$lf_catalogsource
  if $MY_APPLY_FLAG; then 
    oc apply -f $lf_file || exit 1
  fi

  # wait for the availability of the catalogsource
  wait_for_resource "packagemanifest" "${lf_in_operator_name}" $MY_CATALOGSOURCES_NAMESPACE

  trace_out 3 check_add_cs_ibm_pak
}

#########################################################################################################
##SB]20231109 Generate properties and yaml/json files
## input parameter the operand custom dir (and generated dir both with config and scripts subdirectories)
# TODO Decide if it only works with files in the directory, or with subdirectories. Today just one level no subdirectories.
# @param 1:
# @param 2:
# @param 3:
function generate_files() {
  trace_in 3 generate_files

  local lf_in_customdir=$1
  local lf_in_gendir=$2
  local lf_in_transform=$3
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments: source directory, destination directory and file"
    trace_out 3 generate_files
    exit  1
  fi

  local lf_nfiles lf_config_customdir lf_scripts_customdir lf_config_gendir lf_scripts_gendir lf_file

  # generate the differents properties files
  # SB]20231109 some generated files (yaml/json) are based on other generated files (properties), so :
  # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml or .json)
  # - generate first the *.properties files to be sourced then generate the *.yaml/*.json files

  local lf_config_customdir="${lf_in_customdir}config/"
  local lf_scripts_customdir="${lf_in_customdir}scripts/"
  local lf_config_gendir="${lf_in_gendir}config/"
  local lf_scripts_gendir="${lf_in_gendir}scripts/"

  local lf_nfiles lf_file lf_filename

  decho 3 "lf_config_customdir: $lf_config_customdir"
  decho 3 "lf_scripts_customdir: $lf_scripts_customdir"
  decho 3 "lf_config_gendir: $lf_config_gendir"
  decho 3 "lf_scripts_gendir: $lf_scripts_gendir"

  # set -a
  check_directory_contains_files $lf_scripts_customdir
  lf_nfiles=$?
  if [[ $lf_nfiles -gt 0 ]]; then
    for lf_file in ${lf_scripts_customdir}*; do
      if [[ -f $lf_file ]]; then
        lf_filename=$(basename -- "$lf_file")
        adapt_file "$lf_scripts_customdir" "$lf_scripts_gendir" "$lf_filename"
        #  . "${lf_scripts_gendir}${filename}"
      fi
    done
  fi

  check_directory_contains_files $lf_config_customdir
  lf_nfiles=$?
  if [[ $lf_nfiles -gt 0 ]]; then
    for lf_file in ${lf_config_customdir}*; do
      if [[ -f $lf_file ]]; then
        lf_filename=$(basename -- "$lf_file")
        if $lf_in_transform; then
          # mylog info "lf_in_transform $lf_file lf_file"
          adapt_file "$lf_config_customdir" "$lf_config_gendir" "$lf_filename"
        else
          # mylog info "Copy $lf_file lf_file"
          cp $lf_file "${lf_config_gendir}${lf_filename}"
        fi
      fi
    done
  fi
  #set +a
  trace_out 3 generate_files
}

#########################################################################################################
## adapt file into working dir
## called generate_files before
# @param 1: Directory where the source file is located.
# @param 2: Target directory where the file is created.
# @param 3: name of the file (as source and for the target).
function adapt_file() {
  trace_in 5 adapt_file

  local lf_in_source_directory=$1
  local lf_in_target_directory=$2
  local lf_in_filename=$3
  decho 5 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments: source directory, destination directory and file"
    trace_out 5 adapt_file
    exit  1
  fi
  
  check_directory_exist_create ${lf_in_target_directory}
  check_file_exist "${lf_in_source_directory}${lf_in_filename}"
  envsubst < "${lf_in_source_directory}${lf_in_filename}" > "${lf_in_target_directory}${lf_in_filename}"

  trace_out 5 adapt_file
}

################################################
# Create a certificate chain using the Cert manager
# @param 1: 
# @param 2: 
# @param 3:
# @param 4:
# @param 5:
# @param 6:
# @param 7:
function create_certificate_chain() {
  trace_in 3 create_certificate_chain

  local lf_in_namespace="$1"
  local lf_in_issuername="$2"
  local lf_in_root_cert_name="$3"
  local lf_in_tls_label1="$4"
  local lf_in_tls_certname="$5"
  local lf_in_workingdir="$6"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|\"$6\"|"
  
  if [[ $# -ne 6 ]]; then
    mylog error "You have to provide 6 arguments: namespace, issuer name, root cert, label, cert name and working directory"
    trace_out 3 create_certificate_chain
    exit  1
  fi

  local lf_type lf_cr_name lf_yaml_file lf_source_directory lf_target_directory lf_namespace
  

  mylog info "Create a certificate chain in ${lf_in_namespace} namespace"

  # For Self-signed issuer
  export TLS_CA_ISSUER_NAME=${lf_in_namespace}-${lf_in_issuername}-ca
  export TLS_NAMESPACE=${lf_in_namespace}

  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ Issuer_ca.yaml

  # For Self-signed Certificate and Root Certificate
  export TLS_ROOT_CERT_NAME=${lf_in_namespace}-${lf_in_root_cert_name}-ca
  export TLS_LABEL1=${lf_in_tls_label1}
  export TLS_CERT_ISSUER_NAME=${lf_in_namespace}-${lf_in_issuername}-tls

  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ CACertificate.yaml
  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ Issuer_non_ca.yaml

  # For TLS Certificate
  export TLS_CERT_NAME=${lf_in_namespace}-${lf_in_tls_certname}-tls
  export TLS_INGRESS=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ TLSCertificate.yaml

  # Create both Issuers and both Certificates
  create_oc_resource "Issuer" "${lf_in_namespace}-${lf_in_issuername}-ca" "${MY_TLS_GEN_CUSTOMDIR}config/" "${lf_in_workingdir}" "Issuer_ca.yaml" "$lf_in_namespace"

  create_oc_resource "Certificate" "${lf_in_namespace}-${lf_in_issuername}-ca" "${MY_TLS_GEN_CUSTOMDIR}config/" "${lf_in_workingdir}" "CACertificate.yaml" "$lf_in_namespace"

  create_oc_resource "Issuer" "${lf_in_namespace}-${lf_in_issuername}-tls" "${MY_TLS_GEN_CUSTOMDIR}config/" "${lf_in_workingdir}" "Issuer_non_ca.yaml" "$lf_in_namespace"

  create_oc_resource "Certificate" "${lf_in_namespace}-${lf_in_issuername}-tls" "${MY_TLS_GEN_CUSTOMDIR}config/" "${lf_in_workingdir}" "TLSCertificate.yaml" "$lf_in_namespace"
  
  unset TLS_CA_ISSUER_NAME TLS_NAMESPACE TLS_ROOT_CERT_NAME TLS_LABEL1 TLS_INGRESS

  trace_out 3 create_certificate_chain
}

################################################
# SB]20231215
# SB]20231130 patcher les foundational services en acceptant la license
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm
# 3.Setting the hardware profile and accepting the license
# License: Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
# 20250110 : add two more parameters to the function, to use it also for License Service instance which needs also the same patching
function accept_license_fs() {
  trace_in 5 accept_license_fs

  local lf_in_type=$1
  local lf_in_cr_name=$2
  local lf_in_namespace=$3
  decho 4 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments: type, resource name and namespace"
    trace_out 5 accept_license_fs
    exit  1
  fi

  decho 4 "oc -n ${lf_in_namespace} get ${lf_in_type} ${lf_in_cr_name} -o jsonpath='{.spec.license.accept}'"
  local lf_accept=$(oc -n ${lf_in_namespace} get ${lf_in_type} ${lf_in_cr_name} -o jsonpath='{.spec.license.accept}')
  decho 4 "accept=$accept"
  if [[ $lf_accept == "true" ]]; then
    mylog info "license already accepted." 1>&2
  else
    oc -n ${lf_in_namespace} patch ${lf_in_type} ${lf_in_cr_name} --type merge -p '{"spec": {"license": {"accept": true}}}'
  fi

  trace_out 5 accept_license_fs
}

################################################
function generate_password() {
  trace_in 5 generate_password

  local lf_in_length=$1
  decho 5 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide 1 argument: length"
    trace_out 3 generate_password
    exit  1
  fi

  local lf_pattern='A-Za-z0-9!@#$%^&*()_+'

  # Generate a password based on the pattern
  local lf_password=$(cat /dev/urandom | tr -dc "$lf_pattern" | head -c "$lf_in_length")
  export USER_PASSWORD_GEN=$lf_password

  trace_out 5 generate_password
}

################################################
# Check if the resource of type octype with name name exists in the namespace ns.
# If it does not exist use the yaml file, with the appropriate variable.
# @param 1: octype: kubernetes resource class, example: "subscription"
# @param 2: name: name of the resource, example: "ibm-integration-platform-navigator"
# @param 3: dir: the source directory example: "${subscriptionsdir}"
# @param 4: dir: the target directory example: "${workingdir}apic/"
# @param 5: yaml: the file with the definition of the resource, example: "Navigator-Sub.yaml"
# @param 6: namespace: the namespace to use
function create_oc_resource() {
  trace_in 3 create_oc_resource

  local lf_in_type="$1"
  local lf_in_cr_name="$2"
  local lf_in_source_directory="$3"
  local lf_in_target_directory="$4"
  local lf_in_yaml_file="$5"
  local lf_in_namespace="$6"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|\"$6\"|"

  if [[ $# -ne 6 ]]; then
    mylog error "You have to provide 6 arguments: type, resource, namespace, issuer name, root cert, label, cert name and working directory"
    trace_out 3 create_oc_resource
    exit  1
  fi

  mylog check "Checking ${lf_in_cr_name}/${lf_in_type} in namespace $lf_in_namespace" 1>&2
  case $lf_in_type in
    Certificate)   export VAR_CERT="${lf_in_cr_name}";;
    Issuer)        export VAR_ISSUER="${lf_in_cr_name}"
                   export VAR_NAMESPACE="${lf_in_namespace}";;
    OperatorGroup) export VAR_OPERATORGROUP="${lf_in_cr_name}"
                   export VAR_NAMESPACE="${lf_in_namespace}";;
    ServiceAccount) export VAR_SERVICEACCOUNT="${lf_in_cr_name}"
                   export VAR_NAMESPACE="${lf_in_namespace}";;
  esac
  
  if [[ $lf_in_type == "OperatorGroup" ]]; then
    export VAR_OPERATORGROUP="${lf_in_cr_name}"
    export VAR_NAMESPACE="${lf_in_namespace}" 
  fi
  
  adapt_file $lf_in_source_directory $lf_in_target_directory $lf_in_yaml_file
  check_create_oc_yaml "${lf_in_type}" "${lf_in_cr_name}" "${lf_in_source_directory}" "${lf_in_target_directory}" "${lf_in_yaml_file}" ""${lf_in_namespace}

  case $lf_in_type in
    Certificate)  unset VAR_CERT;;
    Issuer)        unset VAR_ISSUER VAR_NAMESPACE;;
    OperatorGroup) unset VAR_OPERATORGROUP VAR_NAMESPACE;;
    ServiceAccount) unset VAR_SERVICEACCOUNT VAR_NAMESPACE;;
  esac

  trace_out 3 create_oc_resource
}


################################################
# create operand instance
# @param 1: octype: kubernetes resource class, example: "subscription"
# @param 2: name: name of the resource, example: "ibm-integration-platform-navigator"
# @param 3: dir: the source directory example: "${subscriptionsdir}"
# @param 4: dir: the target directory example: "${workingdir}apic/"
# @param 5: yaml: the file with the definition of the resource, example: "Navigator-Sub.yaml"
# @param 6: namespace: the namespace to use
# @param 7: path: json path to check resource state
# @param 8: state: resource state
function create_operand_instance() {
  trace_in 3 create_operand_instance  

  local lf_in_type=$1
  local lf_in_cr_name=$2
  local lf_in_source_directory="$3"
  local lf_in_target_directory="$4"
  local lf_in_yaml_file=$5
  local lf_in_namespace=$6
  local lf_in_path=$7
  local lf_in_state=$8
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|\"$6\"|\"$7\"|\"$8\"|"

  if [[ $# -ne 8 ]]; then
    mylog error "You have to provide 6 arguments: type, resource, source directory, target directory, yaml file, namespace, jsonpath and state"
    trace_out 3 create_operand_instance
    exit  1
  fi

  create_oc_resource "${lf_in_type}" "${lf_in_cr_name}" "${lf_in_source_directory}" "${lf_in_target_directory}" "${lf_in_yaml_file}" "$lf_in_namespace"
  
  if oc -n $lf_in_namespace get $lf_in_type $lf_in_cr_name >/dev/null 2>&1; then
    wait_for_state "$lf_in_type $lf_in_cr_name $lf_in_path is $lf_in_state" "$lf_in_state" "oc -n $lf_in_namespace get $lf_in_type $lf_in_cr_name -o jsonpath='$lf_in_path'"
  else
    mylog error "$lf_in_cr_name of type $lf_in_type in $lf_in_namespace namespace does not exist, will not wait for state"
  fi

  trace_out 3 create_operand_instance  
}

################################################
# create operator instance
# @param 1: operator name
# @param 2: catalogue source
# @param 3: dir: the source directory (in this case MY_OPERATORSDIR)
# @param 4: dir: the target directory example: "${workingdir}apic/"
# @param 5: namespace: the namespace to use
function create_operator_instance() {
  trace_in 3 create_operator_instance  

  local lf_in_cr_name="$1"
  local lf_in_catalogue_source="$2"
  local lf_in_source_directory="$3"
  local lf_in_target_directory="$4"
  local lf_in_namespace="$5"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|"

  if [[ $# -ne 5 ]]; then
    mylog error "You have to provide 6 arguments: operator, catalog source, source directory, target directory and namespace"
    trace_out 3 create_operand_instance
    exit  1
  fi

  # export needed variables
  export VAR_OPERATOR_NAME=$lf_in_cr_name
  export VAR_CATALOG_SOURCE_NAME=$lf_in_catalogue_source
  export VAR_OPERATOR_NAMESPACE=$lf_in_namespace

  check_directory_exist ${lf_in_source_directory}

  lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest -o json | jq -r --arg op "$VAR_OPERATOR_NAME" --arg cs "$VAR_CATALOG_SOURCE_NAME" '.items[] | select(.metadata.name==$op and .status.catalogSource==$cs) | .status.defaultChannel')
  local lf_strategy="Automatic"
  lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest -o json | jq -r --arg op "$VAR_OPERATOR_NAME" --arg cs "$VAR_CATALOG_SOURCE_NAME" '.items[] | select(.metadata.name==$op and .status.catalogSource==$cs) | .status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  export VAR_OPERATOR_CHL=$lf_operator_chl
  export VAR_STRATEGY="Automatic"

  local lf_path lf_resource lf_state lf_type

  #SECONDS=0
  create_oc_resource "Subscription" "${VAR_OPERATOR_NAME}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "subscription.yaml" $VAR_OPERATOR_NAMESPACE
  lf_type="clusterserviceversion"
  wait_for_resource "$lf_type" "$lf_csv_name" "$VAR_OPERATOR_NAMESPACE"
  lf_resource=$VAR_RESOURCE
  unset VAR_RESOURCE

  lf_type="clusterserviceversion"
  lf_path="{.status.phase}"
  lf_state="Succeeded"

  if oc -n $VAR_OPERATOR_NAMESPACE get $lf_type $lf_resource >/dev/null 2>&1; then
    wait_for_state "$lf_type $lf_resource $lf_path is $lf_state" "$lf_state" "oc -n $VAR_OPERATOR_NAMESPACE get $lf_type $lf_resource -o jsonpath='$lf_path'"
  else
    mylog error "$lf_resource of type $lf_type in $VAR_OPERATOR_NAMESPACE namespace does not exist, will not wait for state"
  fi
  
  unset VAR_OPERATOR_NAME VAR_OPERATOR_NAMESPACE VAR_OPERATOR_CHL VAR_STRATEGY VAR_CATALOG_SOURCE_NAME

  trace_out 3 create_operator_instance  
}

################################################
# Function to process calls
function process_calls() {
  trace_in 2 process_calls

  local lf_in_calls="$1"  # Get the full string of calls and parameters

  local lf_commands    # Array to store the commands
  local lf_cmd         # Command to process
  local lf_func        # Function name
  local lf_params      # Parameters
  local lf_list        # List of available functions


    # Split the calls by comma and loop through each
    IFS=',' read -ra lf_commands <<< "$lf_in_calls"
    for lf_cmd in "${lf_commands[@]}"; do
      # Trim leading/trailing spaces from the command
      lf_cmd=$(echo "$lf_cmd" | xargs)

      # Extract the function name and parameters
      lf_func=$(echo "$lf_cmd" | awk '{print $1}')
      lf_params=$(echo "$lf_cmd" | awk '{$1=""; sub(/^ /, ""); print}')  # Get all the parameters after the function name
      decho 3 "Function: $lf_func|Parameters: $lf_params"

      # Check if the function exists and call it
      if declare -f "$lf_func" > /dev/null; then
        if [ "$lf_func" = "main" ] || [ "$lf_func" = "process_calls" ]; then
          mylog error "Functions 'main', 'process_calls' cannot be called."
          trace_out 2 process_calls
          return 1
        fi
        #install_needed_resources_part
        $lf_func $lf_params
      else
        mylog error "Function '$lf_func' not found."
        lf_list=$(declare -F | awk '{print $NF}')
        mylog info "Available functions are:" 0
        mylog info "$lf_list" 0
        trace_out 3 process_calls
        return 1
      fi
    done

  trace_out 2 process_calls
}
