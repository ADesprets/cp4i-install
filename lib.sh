################################################
# encode_b64_file function
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
# @param 1 level (info/error/warn/wait/check/ok/no)
function mylog() {
  local lf_spaces=$(printf "%0.s " $(seq 1 $SC_SPACES_COUNTER))

  # prefix
  local p=
  # do not output the trailing newline
  local w=
  # suffix
  local s=
  case $1 in
    info)    c=2;;          #green
    error)   c=1            #red
             p='ERROR: ';;
    warn)    c=3;;          #yellow
    debug)   c=8            #grey
             p='CMD: ';; 
    wait)    c=4            #purple
             p="$(date) ";;
    check)   c=6            #cyan
             w=-n
             s=...;; 
    ok)      c=2            #green
             p=OK;;
    no)      c=3            #yellow
             p=NO;;  
    default) c=9            #default
             p='';;
  esac
  shift
  echo $w "$(tput setaf $c)$lf_spaces$p$@$s$(tput setaf 9)"
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
# function to print message if debug is set to 1
function decho () {
  local lf_in_messagelevel=$1
  shift 1

  if [ -n "$ADEBUG" ]; then
    if [ $TRACELEVEL -ge $lf_in_messagelevel ]; then
      mylog debug "$@"
    fi
  fi
}

#########################################################################
# check if openshift version available
# check_openshift_version v1 returns 0 if v1 does not exist 1 if v1 exist
function check_openshift_version() {
  local lf_in_version=$1

  IFS='.' read -ra v_components <<<"$lf_in_version"
  vmaj=${v_components[0]}
  vmin=${v_components[1]}
  res=$(ibmcloud ks versions -q --show-version Openshift --output json | jq --argjson vmaj "$vmaj" --argjson vmin "$vmin" '.openshift[] | select (.major == $vmaj and .minor == $vmin)')
  echo $res
}

################################################
# Compare versions
# from chatgpt
# This script defines a function compare_versions that takes two version strings as arguments and compares them component-wise.
# It uses the IFS (Internal Field Separator) to split the versions into components based on the dot ('.') separator.
# The function then compares each component, determining whether the first version is older, newer, or equal to the second version.
# The script will output whether the first version is older, newer, or equal to the second version.
# cmp_versions v1 v2 returns 0 if v1=v2, 1 if v1 is older than v2, 2 if v1 is newer than v2
function cmp_versions() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho  3 "F:IN :cmp_versions"

  local lf_in_version1=$1
  local lf_in_version2=$2
  decho  3 "lf_in_version1=$lf_in_version1|lf_in_version2=$lf_in_version2"

  IFS='.' read -ra v1_components <<<"$lf_in_version1"
  IFS='.' read -ra v2_components <<<"$lf_in_version2"

  local lf_len=${#v1_components[@]}
  local lf_res=0

  for ((i = 0; i < $lf_len; i++)); do
    v1=${v1_components[i]:-0}
    v2=${v2_components[i]:-0}

    if [ "$v1" -lt "$v2" ]; then
      #echo "$lf_in_version1 is older than $lf_in_version2"
      lf_res=1
      break
    elif [ "$v1" -gt "$v2" ]; then
      #echo "$lf_in_version1 is newer than $lf_in_version2"
      lf_res=2
      break
    fi
  done

  #echo "$lf_in_version1 is equal to $lf_in_version2"
  decho 3 "lf_res=$lf_res"
  decho 3 "F:OUT:cmp_versions"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
}

################################################
# Save a certificate in pem format
function save_certificate() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho  3 "F:IN :save_certificate"

  local lf_in_ns=$1
  local lf_in_secret_name=$2
  local lf_in_destination_path=$3

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.pem"
  cert=$(oc -n cp4i get secret ${lf_in_secret_name} -o jsonpath='{.data.ca\.crt}')
  echo $cert | base64 --decode >"${lf_in_destination_path}${lf_in_secret_name}.pem"

  decho  3 "F:OUT:save_certificate"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))

}

################################################
# Check that the CASE is already downloaded
# example pour filtrer avec conditions :
# avec jsonpath=$.[?(@.name=='ibm-licensing' && @.version=='4.2.1')]
# Pour tester une variable null : https://stackoverflow.com/questions/48261038/shell-script-how-to-check-if-variable-is-null-or-no
function is_case_downloaded() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho  3 "F:IN :is_case_downloaded"
  local lf_in_case=$1
  local lf_in_version=$2

  decho 3 "lf_in_case=$lf_in_case|lf_in_version=$lf_in_version"

  local lf_result lf_latestversion lf_cmp lf_res
  local lf_directory="${IBMPAKDIR}${lf_in_case}/${lf_in_version}"

  if [ ! -d "${lf_directory}" ]; then
    lf_res=0
  else
    lf_result=$(oc ibm-pak list --downloaded -o json)

    # One of the simplest ways to check if a string is empty or null is to use the -z and -n operators.
    # The -z operator returns true if the string is null or empty, and false otherwise.
    # The -n operator returns true if the string is not null or empty, and false otherwise.
    if [ -z "$lf_result" ]; then
      lf_res=0
    else
      # Pb avec le passage de variables à jsonpath ; décision retour vers jq
      # lf_result=$(echo $lf_result | jsonpath '$.[?(@.name == "${lf_in_case}" && @.latestVersion == "${lf_in_version}")]')
      # lf_result=$(echo $lf_result | jq -r --arg case "$lf_in_case" --arg version "$lf_in_version" '.[] | select (.name == $case and .latestVersion == $version)')
      lf_result=$(echo $lf_result | jq -r --arg case "$lf_in_case" '[.[] | select (.name == $case )]')
      if [ -z "$lf_result" ]; then
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

  decho  3 "F:OUT:is_case_downloaded"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
}

############################################################
# Check that the CR is newer than the CR file
# Inputs :
#  - Type of the custom resource
#  - Custom resource
#  - the file defining the custom resource
#  - the namespace
#  Returns 1 (if the cr is newer than the file) otherwise 0
function is_cr_newer() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :is_cr_newer"
  local lf_in_type=$1
  local lf_in_customresource=$2
  local lf_in_file=$3
  local lf_in_namespace=$4

  local lf_customresource_timestamp
  local lf_file_timestamp
  local lf_path="{.metadata.creationTimestamp}"
  local lf_res

  #oc -n $lf_in_namespace get $lf_in_type $lf_in_customresource -o jsonpath='$lf_path'| date -d - +%s
  lf_customresource_timestamp=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_customresource -o json | jq -r '.metadata.creationTimestamp')
  lf_customresource_timestamp=$(echo "$lf_customresource_timestamp" | date -d - +%s)
  lf_file_timestamp=$(stat -c %Y $lf_in_file)

  if [ $lf_customresource_timestamp -gt $lf_file_timestamp ]; then
    lf_res=1
  else
    lf_res=0
  fi

  decho 3 "F:OUT:is_cr_newer"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
}

################################################
# Check that all required executables are installed
function check_command_exist() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho  3 "F:IN :check_command_exist"

  local command=$1

  if ! command -v $command >/dev/null 2>&1; then
    mylog error "Executable $command does not exist or is not executable, exiting."
    exit 1
  fi

  decho 3 "F:OUT:check_command_exist"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the file exist, if no print a msg and exit
#
function check_file_exist() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 5 "F:IN :check_file_exist"

  local file=$1
  if [ ! -e "$file" ]; then
    mylog error "No such file: $file" 1>&2
    exit 1
  fi

  decho 5 "F:OUT:check_file_exist"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the directory exist, if no print a msg and exit
#
function check_directory_exist() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :check_directory_exist"

  local directory=$1
  if [ ! -d $directory ]; then
    mylog error "No such directory: $directory" 1>&2
    exit 1
  fi

  decho 4 "F:OUT:check_directory_exist"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the directory contains files, if no print a msg and exit
#
function check_directory_contains_files() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :check_directory_contains_files"

  local lf_in_directory=$1
  local lf_files
  shopt -s nullglob dotglob # To include hidden files
  lf_files=($lf_in_directory/*)

  decho 4 "F:OUT:check_directory_contains_files"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))

  return ${#lf_files[@]}
}

######################################################
# checks if the directory exist, otherwise create it
#
function check_directory_exist_create() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho  4 "F:IN :check_directory_exist_create"

  local directory=$1
  if [ ! -d $directory ]; then
    mkdir -p $directory
  fi

  decho 4 "F:OUT:check_directory_exist_create"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
function read_config_file() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN  :read_config_file"

  local lf_config_file
  if test -n "$PC_CONFIG"; then
    lf_config_file="$PC_CONFIG"
  else
    lf_config_file="$1"
  fi
  if test -z "$lf_config_file"; then
    mylog error "Usage: $0 <config file>" 1>&2
    mylog info "Example: $0 ${MAINSCRIPTDIR}cp4i.conf"

    decho 4 "F:OUT:read_config_file"
    SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
    exit 1
  fi

  check_file_exist $lf_config_file

  # load user specific variables, "set -a" so that variables are part of environment for envsubst
  set -a
  . "${lf_config_file}"
  set +a

  decho 4 "F:OUT:read_config_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check that all required executables are installed
function check_exec_prereqs() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :check_exec_prereqs"

  check_command_exist awk
  check_command_exist curl
  check_command_exist $MY_CONTAINER_ENGINE
  check_command_exist ibmcloud
  check_command_exist jq
  check_command_exist keytool
  check_command_exist oc
  check_command_exist openssl
  if $MY_MQ_CUSTOM; then
    check_command_exist runmqakm
  fi

  decho 4 "F:OUT:check_exec_prereqs"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Wait n secs
# @param secs: number of seconds to wait for and displays it on the same line
function waitn() {
  local secs=$1
  mylog info "Sleeping $secs"
  while [ $secs -gt 0 ]; do
    echo -ne "$secs\033[0K\r"
    sleep 1
    : $((secs--))
  done
}

################################################
# Send email
# @param mail_def, exemple 159.8.70.38:2525
function send_email() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :send_email"

  curl --url "smtp://$mail_def" \
    --mail-from cp4i-admin@ibm.com \
    --mail-rcpt cp4i-user@ibm.com \
    --upload-file ${MAINSCRIPTDIR}templates/emails/test-email.txt

  decho 3 "F:OUT:send_email"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# wait for command to return specified value
# @param what description of waited state
# @param value expected state value from check command
# @param command executed command that returns some state
function wait_for_state() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :wait_for_state"

  local lf_in_what=$1
  local lf_in_value=$2
  local lf_in_command=$3
  local lf_start_time=$(date +%s)
  local lf_current_time lf_elapsed_time lf_last_state lf_current_state lf_bullet
  local lf_bullets=('|' '/' '-' '\\')

  mylog check "Checking $lf_in_what"
  #mylog check "Checking $lf_in_what status until reaches value $lf_in_value with command $lf_in_command"
  lf_last_state=''
  while true; do
    lf_current_state=$(eval $lf_in_command)
    if test "$lf_current_state" = "$lf_in_value"; then
      mylog ok ", $lf_current_state"
      break
    fi

    if test "$lf_last_state" != "$lf_current_state"; then
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
  decho 3 "F:OUT:wait_for_state"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check if the resource of type octype with name name exists in the namespace ns.
# If it does not exist use the yaml file, with the appropriate variable.
# @param octype: kubernetes resource class, example: "subscription"
# @param name: name of the resource, example: "ibm-integration-platform-navigator"
# @param yaml: the file with the definition of the resource, example: "${subscriptionsdir}Navigator-Sub.yaml"
# @param ns: name space where the reousrce is created, example: $MY_OPERATORS_NAMESPACE
function check_create_oc_yaml() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :check_create_oc_yaml"

  local lf_in_octype="$1"
  local lf_in_cr_name="$2"
  local lf_in_yaml_file="$3"
  local lf_in_ns="$4"

  export MY_NAMESPACE="$4"

  local lf_newer

  check_file_exist $lf_in_yaml_file
  mylog check "Checking ${lf_in_octype} ${lf_in_cr_name} in ${lf_in_ns} project"
  decho 3 "oc -n ${lf_in_ns} get ${lf_in_octype} ${lf_in_cr_name}"

  if oc -n ${lf_in_ns} get ${lf_in_octype} ${lf_in_cr_name} >/dev/null 2>&1; then
    is_cr_newer $lf_in_octype $lf_in_cr_name $lf_in_yaml_file $lf_in_ns
    lf_newer=$?
    if [ $lf_newer -eq 1 ]; then
      mylog info "OK: Custom Resource $lf_in_cr_name is newer than file $lf_in_yaml_file"
    else
      envsubst <"${lf_in_yaml_file}" | oc -n ${lf_in_ns} apply -f - || exit 1
    fi
  else
    envsubst <"${lf_in_yaml_file}" | oc -n ${lf_in_ns} apply -f - || exit 1
  fi

  decho 3 "F:OUT:check_create_oc_yaml"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param namespace
function provision_persistence_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :provision_persistence_openldap"

  local lf_in_namespace="$1"
  # handle persitence for Openldap
  # only check one, assume that if one is created the other one is also created (short cut to optimize time)
  if oc -n ${lf_in_namespace} get "PersistentVolumeClaim" "pvc-ldap-main" >/dev/null 2>&1; then mylog ok; else
    envsubst <"${YAMLDIR}ldap/ldap-pvc.main.yaml" >"${WORKINGDIR}ldap-pvc.main.yaml"
    envsubst <"${YAMLDIR}ldap/ldap-pvc.config.yaml" >"${WORKINGDIR}ldap-pvc.config.yaml"
    oc -n ${lf_in_namespace} create -f ${WORKINGDIR}ldap-pvc.main.yaml
    oc -n ${lf_in_namespace} create -f ${WORKINGDIR}ldap-pvc.config.yaml
    wait_for_state "pvc pvc-ldap-config status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-config -o jsonpath='{.status.phase}'"
    wait_for_state "pvc pvc-ldap-main status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-main -o jsonpath='{.status.phase}'"
  fi

  decho 4 "F:OUT:provision_persistence_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "openldap"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
function deploy_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :deploy_openldap"

  local lf_in_octype="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"
  # check if deploment already performed
  mylog check "Checking ${lf_in_octype} ${lf_in_name} in ${lf_in_namespace}"
  if oc -n ${lf_in_namespace} get ${lf_in_octype} ${lf_in_name} >/dev/null 2>&1; then
    mylog ok
  else
    mylog check "Checking service ${lf_in_name} in ${lf_in_namespace}"
    if oc -n ${lf_in_namespace} get service ${lf_in_name} >/dev/null 2>&1; then
      mylog ok
    else
      mylog info "Creating LDAP server"
      oc adm policy add-scc-to-group anyuid system:serviceaccounts:${lf_in_namespace}

      # deploy openldap and take in account the PVCs just created
      # check that deployment of openldap was not done
      # https://www.ibm.com/docs/en/sva/10.0.6?topic=support-docker-image-openldap
      #echo $MY_ENTITLEMENT_KEY | docker login icr.io --username isva --password-stdin
      #oc -n ${lf_in_namespace} new-app ibmcom/verify-access-openldap:latest
      #oc -n ${lf_in_namespace} new-app isva/verify-access-openldap
      oc -n ${lf_in_namespace} new-app osixia/${lf_in_name}
      oc -n ${lf_in_namespace} get deployment.apps/openldap -o json | jq '. | del(."status")' >${WORKINGDIR}openldap.json
      envsubst <"${YAMLDIR}ldap/ldap-config.json" >"${WORKINGDIR}ldap-config.json"
      oc -n ${lf_in_namespace} patch deployment.apps/openldap --patch-file ${WORKINGDIR}ldap-config.json
      oc -n ${lf_in_namespace} patch service ${lf_in_name} -p='{"spec": {"type": "NodePort"}}'
      oc -n ${lf_in_namespace} patch service/${lf_in_name} --patch-file ${WORKINGDIR}openldap-service.json
    fi
  fi

  decho 3 "F:OUT:deploy_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "mailhog"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
# To add a user/password protection to the web UI: https://stackoverflow.com/questions/60162842/how-can-i-add-basic-authentication-to-the-mailhog-service-in-ddev-local
function deploy_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :deploy_mailhog"

  local lf_in_octype="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"

  # check if deploment already performed
  mylog check "Checking ${lf_in_octype} ${lf_in_name} in ${lf_in_namespace}"
  if oc -n ${lf_in_namespace} get ${lf_in_octype} ${lf_in_name} >/dev/null 2>&1; then
    mylog ok
  else
    mylog check "Checking service ${lf_in_name} in ${lf_in_namespace}"
    if oc -n ${lf_in_namespace} get service ${lf_in_name} >/dev/null 2>&1; then
      mylog ok
    else
      mylog info "Creating mailhog server"
      oc -n ${lf_in_namespace} new-app ${lf_in_name}/${lf_in_name}
    fi
  fi
  decho 3 "F:OUT:deploy_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check if the service is already exposed
function is_service_exposed() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :is_service_exposed"

  local lf_in_namespace="$1"
  local lf_in_service_name="$2"
  local lf_in_port="$3"

  local lf_port_name lf_res

  lf_port_name=$(oc -n "${lf_in_namespace}" get service "${lf_in_service_name}" -o json | jq --argjson port "$lf_in_port" '.spec.ports[] | select(.nodePort == $port) |.name')
  decho 4 "lf_port_name=$lf_port_name"
  
  if [ -z "$lf_port_name" ]; then
    lf_res=1
  else
    lf_res=0
  fi
  decho 4 "F:OUT:is_service_exposed"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
}

#===========================================
# Function to add entry if it doesn't exist
function add_entry_if_not_exists() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :add_entry_if_not_exists"

  local lf_in_ldap_server="$1"
  local lf_in_admin_dn="$2"
  local lf_in_admin_password="$3"
  local lf_in_entry_dn="$4"
  local lf_in_entry_content="$5"
  local lf_in_tmp_ldif_file="$6"

  # Check if entry exists
  local lf_in_search_result
  lf_in_search_result=$(ldapsearch -x -H $lf_in_ldap_server -D "$lf_in_admin_dn" -w $lf_in_admin_password -b "$lf_in_entry_dn" -s base "(objectClass=*)")
  # Check if the entry already exists
  if [ -n "$lf_in_search_result" ]; then
    if echo "$lf_in_search_result" | grep -q "dn: $lf_in_entry_dn"; then
      echo "Entry $lf_in_entry_dn already exists. Skipping."
    else
      echo "Entry $lf_in_entry_dn does not exist. Adding entry."
      echo "$lf_in_entry_content" > $lf_in_tmp_ldif_file
      ldapadd -x -H $lf_in_ldap_server -D "$lf_in_admin_dn" -w $lf_in_admin_password -f $lf_in_tmp_ldif_file
    fi
  fi

  decho 4 "F:OUT:add_entry_if_not_exists"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#========================================================
# Function to add ldif file entries if each doesn't exist
function add_ldif_file () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :add_ldif_file"

  local lf_in_ldif_file="$1"
  local lf_in_ldap_server="$2"
  local lf_in_admin_dn="$3"
  local lf_in_admin_password="$4"

  local lf_tmp_ldif="${WORKINGDIR}temp_entry.ldif"
  local lf_line lf_entry_dn lf_entry_content

  # Read the LDIF file and process each entry
  while IFS= read -r lf_line; do
    # Collect lines of a single LDIF entry
    if [[ -z "$lf_line" ]]; then
      # Empty line indicates end of an entry
      if [[ -n "$lf_entry_dn" && -n "$lf_entry_content" ]]; then
        add_entry_if_not_exists "$lf_in_ldap_server" "$lf_in_admin_dn" "$lf_in_admin_password" "$lf_entry_dn" "$lf_entry_content" "$lf_tmp_ldif"
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
    add_entry_if_not_exists "$lf_in_ldap_server" "$lf_in_admin_dn" "$lf_in_admin_password" "$lf_entry_dn" "$lf_entry_content" "$lf_tmp_ldif"
  fi
  
  # Clean up temporary file
  #rm -f $lf_tmp_ldif

  decho 4 "F:OUT:add_ldif_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param name: name of the resource, example: "openldap"
# @param namespace: the namespace to use
function expose_service_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :expose_service_openldap"

  local lf_in_name="$1" 
  local lf_in_namespace="$2"
  local lf_hostname

  decho 4 "lf_in_name=$lf_in_name|lf_in_namespace=$lf_in_namespace"

  # expose service externaly and get host and port
  oc -n ${lf_in_namespace} get service ${lf_in_name} -o json | jq '.spec.ports |= map(if .name == "389-tcp" then . + { "nodePort": 30389 } else . end)' | jq '.spec.ports |= map(if .name == "636-tcp" then . + { "nodePort": 30686 } else . end)' >${WORKINGDIR}openldap-service.json
  lf_port0=$(oc -n ${lf_in_namespace} get service ${lf_in_name} -o jsonpath='{.spec.ports[0].nodePort}')
  lf_port1=$(oc -n ${lf_in_namespace} get service ${lf_in_name} -o jsonpath='{.spec.ports[1].nodePort}')

  mylog info "Service ${lf_in_name} using port ${lf_port0} is not exposed."
  oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port0}

  mylog info "Service ${lf_in_name} using port ${lf_port1} is not exposed."
  oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port1}

  #is_service_exposed "${lf_in_namespace}" "${lf_in_name}" "${lf_port0}"
  #if [ $? -eq 0 ]; then
  #  mylog info "Service ${lf_in_name} using port ${lf_port0} is already exposed."
  #else
  #  mylog info "Service ${lf_in_name} using port ${lf_port0} is not exposed."
  #  oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port0}
  #fi

  #is_service_exposed "${lf_in_namespace}" "${lf_in_name}" "${lf_port1}"
  #if [ $? -eq 0 ]; then
  #  mylog info "Service ${lf_in_name} using port ${lf_port1} is already exposed."
  #else
  #  mylog info "Service ${lf_in_name} using port ${lf_port1} is not exposed."
  #  oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port1}
  #fi

  lf_hostname=$(oc -n ${lf_in_namespace} get route openldap-external -o jsonpath='{.spec.host}')

  # load users and groups into LDAP
  envsubst <"${YAMLDIR}ldap/ldap-users.ldif" >"${WORKINGDIR}ldap-users.ldif"
  mylog info "Adding LDAP entries with following command: "
  mylog info "$LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${WORKINGDIR}ldap-users.ldif"
  add_ldif_file ${WORKINGDIR}ldap-users.ldif "ldap://${lf_hostname}:${lf_port0}" "${ldap_admin_dn}" "${ldap_admin_password}"
  #$LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -c -f ${WORKINGDIR}ldap-users.ldif

  mylog info "You can search entries with the following command: "
  # ldapmodify -H ldap://$lf_hostname:$lf_port0 -D "$ldap_admin_dn" -w admin -f ${LDAPDIR}Import.ldiff
  mylog info "ldapsearch -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""

  decho 4 "F:OUT:expose_service_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}
################################################
# @param name: name of the resource, example: "mailhog"
# @param namespace: the namespace to use
function expose_service_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :expose_service_mailhog"

  local lf_in_name="$1"
  local lf_in_namespace="$2"
  local lf_port="$3"

  # expose service externaly and get host and port
  # Check if the service is already exposed
  if oc -n ${lf_in_namespace} get route ${lf_in_name} >/dev/null 2>&1; then
    mylog info "Service ${lf_in_name} is already exposed."
  else
    mylog info "Service ${lf_in_name} is not exposed."
    oc -n ${lf_in_namespace} expose svc/${lf_in_name} --port=${lf_port} --name=${lf_in_name}
  fi
  lf_hostname=$(oc -n ${lf_in_namespace} get route ${lf_in_name} -o jsonpath='{.spec.host}')
  decho 4 "MailHog accessible at ${lf_hostname}"

  decho 4 "F:OUT:expose_service_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create namespace
# @param ns namespace to be created
function create_namespace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :create_namespace"

  sc_in_ns=$1
  var_fail sc_in_ns "Please define project name in config"
  mylog check "Checking project $sc_in_ns"
  if oc get project $sc_in_ns >/dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $sc_in_ns"
    if ! oc new-project $sc_in_ns; then
      decho 4 "F:OUT:create_namespace"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
  fi

  decho 4 "F:OUT:create_namespace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check if the resource exists.
# @param octype: kubernetes resource class, example: "subscription"
# @param name: name of the resource, example: "ibm-integration-platform-navigator"
# @param ns: namespace/project to perform the search
# TODO The var variable is initialised for another function, this is not good
function check_resource_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :check_resource_availability"

  local lf_in_type="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"

  decho 3 "oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}'"
  var=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  while test -z $var; do
    var=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  done
  #SB]20231013 simulate a return value by echoing it
  #echo $var
  # SB]20240519 due to many problems with the return value, I will use an export variable to return the value
  export MY_RESOURCE=$var

  decho 4 "F:OUT:check_resource_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
function check_add_cs_ibm_pak() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :check_add_cs_ibm_pak"
  SECONDS=0

  local lf_in_case_name="$1"
  local lf_in_arch="$2"
  local lf_in_case_version="$3"

  local lf_case_version lf_file lf_downloaded

  #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
  if [ -z "$lf_in_case_version" ]; then
    local lf_case_version=$(oc ibm-pak list -o json | jq -r --arg case "$lf_in_case_name" '.[] | select (.name == $case ) | .latestVersion')
  else
    lf_case_version=$lf_in_case_version
  fi
  
  is_case_downloaded ${lf_in_case_name} ${lf_case_version} #1>&2 > /dev/null
  lf_downloaded=$?
  decho 4 "lf_downloaded=$lf_downloaded"

  if [ $lf_downloaded -eq 1 ]; then
    mylog info "case ${lf_in_case_name} ${lf_case_version} already downloaded"
  else
    oc ibm-pak get ${lf_in_case_name} --version ${lf_case_version}
    oc ibm-pak generate mirror-manifests ${lf_in_case_name} icr.io --version ${lf_case_version}
  fi

  lf_file=~/.ibm-pak/data/mirror/${lf_in_case_name}/${lf_case_version}/catalog-sources.yaml
  if [ -e "$lf_file" ]; then
    oc apply -f $lf_file
  fi

  lf_file=~/.ibm-pak/data/mirror/${lf_in_case_name}/${lf_case_version}/catalog-sources-linux-${lf_in_arch}.yaml
  if [ -e "$lf_file" ]; then
    oc apply -f $lf_file
  fi

  mylog info "Adding case $lf_in_case_name took $SECONDS seconds to execute." 1>&2

  decho 4 "F:OUT:check_add_cs_ibm_pak"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20231201 create operator subscription
function create_operator_subscription() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_operator_subscription"

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  export MY_OPERATOR_NAME=$1
  export MY_CATALOG_SOURCE_NAME=$2
  export MY_OPERATOR_NAMESPACE=$3
  export MY_STRATEGY=$4
  local lf_in_wait=$5
  local lf_in_csv_name=$6

  local lf_file lf_path lf_resource lf_state lf_type
  check_directory_exist ${OPERATORSDIR}

  SECONDS=0

  lf_file="${OPERATORSDIR}subscription.yaml"
  lf_type="Subscription"
  check_create_oc_yaml "${lf_type}" "${MY_OPERATOR_NAME}" "${lf_file}" "${MY_OPERATOR_NAMESPACE}"

  lf_type="clusterserviceversion"
  lf_path="{.status.phase}"
  lf_state="Succeeded"
  decho 3 "oc -n $MY_OPERATOR_NAMESPACE get $lf_type -o json | jq -r --arg my_resource \"$lf_in_csv_name\" '.items[].metadata | select (.name | contains ($my_resource)).name'"

  seconds=0
  while [ -z "$lf_resource" ]; do
    echo -ne "Timer: $seconds seconds | Creating csv...\033[0K\r"
    sleep 1
    lf_resource=$(oc -n $MY_OPERATOR_NAMESPACE get $lf_type -o json | jq -r --arg my_resource "$lf_in_csv_name" '.items[].metadata | select (.name | contains ($my_resource)).name')
    seconds=$((seconds + 1))
  done

  #lf_resource=$(oc -n $MY_OPERATOR_NAMESPACE get $lf_type -o json | jq -r  --arg my_resource "$lf_in_csv_name" '.items[].metadata | select (.name | contains ($my_resource)).name')
  decho 3 "lf_resource=$lf_resource|lf_in_csv_name=$lf_in_csv_name"
  if [ $lf_in_wait ]; then
    wait_for_state "$lf_type $lf_resource $lf_path is $lf_state" "$lf_state" "oc -n $MY_OPERATOR_NAMESPACE get $lf_type $lf_resource -o jsonpath='$lf_path'"
  fi
  mylog info "Creation of $MY_OPERATOR_NAME operator took $SECONDS seconds to execute." 1>&2

  decho 3 "F:OUT:create_operator_subscription"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20231204 create operand instance
function create_operand_instance() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_operand_instance"

  local lf_in_file=$1
  local lf_in_ns=$2
  local lf_in_path=$3
  local lf_in_resource=$4
  local lf_in_state=$5
  local lf_in_type=$6
  local lf_in_wait=$7

  SECONDS=0
  check_create_oc_yaml $lf_in_type $lf_in_resource $lf_in_file $lf_in_ns
  decho 3 "wait_for_state | $lf_in_type $lf_in_resource $lf_in_path is $lf_in_state | $lf_in_state | oc -n $lf_in_ns get $lf_in_type $lf_in_resource -o jsonpath=$lf_in_path"
  if $lf_in_wait; then
    wait_for_state "$lf_in_type $lf_in_resource $lf_in_path is $lf_in_state" "$lf_in_state" "oc -n $lf_in_ns get $lf_in_type $lf_in_resource -o jsonpath='$lf_in_path'"
  fi
  mylog info "Creation of $lf_in_type instance took $SECONDS seconds to execute." 1>&2

  decho 3 "F:OUT:create_operand_instance"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Get useful information to start using the stack
# Need to check that the resource exist.
function get_navigator_access() {
  decho 5 "F:IN :get_navigator_access"

  cp4i_url=$(oc -n $MY_OC_PROJECT get platformnavigator cp4i-navigator -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
  # cp4i_uid=$(oc -n $MY_OC_PROJECT get secret ibm-iam-bindinfo-platform-auth-idp-credentials -o jsonpath={.data.admin_username} | base64 -d)
  mylog info "CP4I Platform UI URL: " $cp4i_url
  # mylog info "CP4I admin user: " $cp4i_uid
  # mylog info "CP4I admin password: " $cp4i_pwd

  decho 5 "F:OUT:get_navigator_access"
}

#########################################################################################################
##SB]20231109 Generate properties and yaml/json files
## input parameter the operand custom dir (and generated dir both with config and scripts subdirectories)
# TODO Decide if it only works with files in the directory, or with subdirectories. Today just one level no subdirectories.
function generate_files() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :generate_files"
  decho 5 "$1 $2 $3"

  local lf_in_customdir=$1
  local lf_in_gendir=$2
  local lf_in_transform=$3
  local lf_nfiles lf_config_customdir lf_scripts_customdir lf_config_gendir lf_scripts_gendir lf_file

  # generate the differents properties files
  # SB]20231109 some generated files (yaml/json) are based on other generated files (properties), so :
  # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml or .json)
  # - generate first the *.properties files to be sourced then generate the *.yaml/*.json files

  lf_config_customdir="${lf_in_customdir}config/"
  lf_scripts_customdir="${lf_in_customdir}scripts/"
  lf_config_gendir="${lf_in_gendir}config/"
  lf_scripts_gendir="${lf_in_gendir}scripts/"

  # set -a
  # Start with *.properties files
  lf_nfiles=$(check_directory_contains_files $lf_scripts_customdir)
  if [ $lf_nfiles -gt 0 ]; then
    for lf_file in ${lf_scripts_customdir}*; do
      if [ -f $lf_file]; then
        filename=$(basename -- "$lf_file")
        cat $lf_file | envsubst >"${lf_scripts_gendir}${filename}"
        #  . "${lf_scripts_gendir}${filename}"
      fi
    done
  fi

  # Continue *.yaml files
  lf_nfiles=$(check_directory_contains_files $lf_config_customdir)
  if [ $lf_nfiles -gt 0 ]; then
    for lf_file in ${lf_config_customdir}*; do
      if [ -f $lf_file]; then
        filename=$(basename -- "$lf_file")
        if $lf_in_transform; then
          # mylog info "lf_in_transform $lf_file lf_file"
          cat $lf_file | envsubst >"${lf_config_gendir}${filename}"
        else
          # mylog info "Copy $lf_file lf_file"
          cat $lf_file >"${lf_config_gendir}${filename}"
        fi
      fi
    done
  fi
  #set +a
  decho 4 "F:OUT:generate_files"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#############################################################################################################################
function create_catalogsource() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :create_catalogsource"

  export CATALOG_SOURCE_NAMESPACE=$1
  export CATALOG_SOURCE_NAME=$2
  export CATALOG_SOURCE_DISPLAY_NAME=$3
  export CATALOG_SOURCE_IMAGE=$4
  export CATALOG_SOURCE_PUBLISHER=$5
  export CATALOG_SOURCE_INTERVAL=$6

  local lf_type="CatalogSource"
  local lf_file="${RESOURCSEDIR}catalog_source.yaml"
  local lf_path="{.status.connectionState.lastObservedState}"
  local lf_state="READY"
  local lf_result

  lf_result=$(oc get $lf_type -A -o json | jq -r --arg name $CATALOG_SOURCE_NAME --arg namespace $CATALOG_SOURCE_NAMESPACE '.items[] | select (.metadata.name == $name and .metadata.namespace == $namespace)')
  if [ -z "$lf_result" ]; then
    mylog info "no catalogsource $CATALOG_SOURCE_NAME found in namespace $CATALOG_SOURCE_NAMESPACE"
    envsubst <"${lf_file}" | oc -n ${CATALOG_SOURCE_NAMESPACE} apply -f - || exit 1
    wait_for_state "$lf_type $CATALOG_SOURCE_NAME $lf_path is $lf_state" "$lf_state" "oc -n ${CATALOG_SOURCE_NAMESPACE} get ${lf_type} ${CATALOG_SOURCE_NAME} -o jsonpath='$lf_path'"
  else
    is_cr_newer $lf_type $CATALOG_SOURCE_NAME $lf_file $CATALOG_SOURCE_NAMESPACE
    if [ $? -eq 1 ]; then
      mylog info "Custom Resource $CATALOG_SOURCE_NAME exists in ns $CATALOG_SOURCE_NAMESPACE and is newer than file $lf_file"
    else
      envsubst <"${lf_file}" | oc -n ${CATALOG_SOURCE_NAMESPACE} apply -f - || exit 1
      wait_for_state "$lf_type $CATALOG_SOURCE_NAME $lf_path is $lf_state" "$lf_state" "oc -n ${CATALOG_SOURCE_NAMESPACE} get ${lf_type} ${CATALOG_SOURCE_NAME} -o jsonpath='$lf_path'"
    fi
  fi

  decho 4 "F:OUT:create_catalogsource"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#########################################################################################################
## adapt file into working dir
## called generate_files before
function adapt_file() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :adapt_file"

  local lf_in_sourcedir=$1
  local lf_in_destdir=$2
  local lf_in_filename=$3

  if [ ! -d ${lf_in_destdir} ]; then
    mkdir -p ${lf_in_destdir}
  fi
  if [ -e "${lf_in_sourcedir}${lf_in_filename}" ]; then
    envsubst < "${lf_in_sourcedir}${lf_in_filename}" > "${lf_in_destdir}${lf_in_filename}"
  fi

  decho 4 "F:OUT:adapt_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}
