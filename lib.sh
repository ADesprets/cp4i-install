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
function decho() {
  if [ -n "$ADEBUG" ]; then
    mylog debug "$@"
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
# cmp_versions v1 v2 returns 0 if v1=v2, 1 if v1 is newer than v2, 2 if v1 is older than v2
function cmp_versions() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :cmp_versions"

  local lf_in_version1=$1
  local lf_in_version2=$2

  IFS='.' read -ra v1_components <<<"$lf_in_version1"
  IFS='.' read -ra v2_components <<<"$lf_in_version2"

  local lf_len=${#v1_components[@]}
  local lf_res=0

  for ((i = 0; i < $lf_len; i++)); do
    v1=${v1_components[i]:-0}
    v2=${v2_components[i]:-0}

    if [ "$v1" -lt "$v2" ]; then
      #echo "$lf_in_version1 is older than $lf_in_version2"
      lf_res=2
    elif [ "$v1" -gt "$v2" ]; then
      #echo "$lf_in_version1 is newer than $lf_in_version2"
      lf_res=1
    fi
  done

  #echo "$lf_in_version1 is equal to $lf_in_version2"
  decho "F:OUT:cmp_versions"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
}

################################################
# Save a certificate in pem format
function save_certificate() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :save_certificate"

  local lf_in_ns=$1
  local lf_in_secret_name=$2
  local lf_in_destination_path=$3

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.pem"
  cert=$(oc -n cp4i get secret ${lf_in_secret_name} -o jsonpath='{.data.ca\.crt}')
  echo $cert | base64 --decode >"${lf_in_destination_path}${lf_in_secret_name}.pem"

  decho "F:OUT:save_certificate"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))

}

################################################
# Check that the CASE is already downloaded
# example pour filtrer avec conditions :
# avec jsonpath=$.[?(@.name=='ibm-licensing' && @.version=='4.2.1')]
# Pour tester une variable null : https://stackoverflow.com/questions/48261038/shell-script-how-to-check-if-variable-is-null-or-no
function is_case_downloaded() {
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN :is_case_downloaded"
  local lf_in_case=$1
  local lf_in_version_varid=$2

  local lf_directory lf_result lf_latestversion lf_cmp

  local lf_version=${!lf_in_version_varid}

  local lf_directory="${IBMPAKDIR}${lf_in_case}/${lf_version}"
  local lf_res

  if [ ! -d "${lf_directory}" ]; then
    decho "F:OUT:is_case_downloaded"
    SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
    lf_res=0
  else
    lf_result=$(oc ibm-pak list --downloaded -o json)

    # One of the simplest ways to check if a string is empty or null is to use the -z and -n operators.
    # The -z operator returns true if the string is null or empty, and false otherwise.
    # The -n operator returns true if the string is not null or empty, and false otherwise.
    if [ -z "$lf_result" ]; then
      decho "F:OUT:is_case_downloaded"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      lf_res=0
    else
      # Pb avec le passage de variables à jsonpath ; décision retour vers jq
      # lf_result=$(echo $lf_result | jsonpath '$.[?(@.name == "${lf_in_case}" && @.latestVersion == "${lf_version}")]')
      # lf_result=$(echo $lf_result | jq -r --arg case "$lf_in_case" --arg version "$lf_version" '.[] | select (.name == $case and .latestVersion == $version)')
      lf_result=$(echo $lf_result | jq -r --arg case "$lf_in_case" '[.[] | select (.name == $case )]')
      if [ -z "$lf_result" ]; then
        lf_res=0
      else
        lf_latestversion=$(echo $lf_result | jq -r max_by'(.latesVersion)|.latestVersion')

        cmp_versions $lf_latestversion $lf_version
        lf_cmp=$?
        case $lf_cmp in
        0) lf_res=1;;
        1) mylog info "newer version of case $lf_in_case is available. Current version=$lf_version. Latest version=$lf_latestversion"
           # sed -i "/$lf_in_version_varid/c$lf_in_version_varid=$lf_latestversion" "$sc_versions_file"
           lf_res=1;;
        esac
      fi
    fi
  fi

#  decho "F:OUT:is_case_downloaded"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
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
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN :is_cr_newer"
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

#  decho "F:OUT:is_cr_newer"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
}

################################################
# Check that all required executables are installed
function check_command_exist() {
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN :check_command_exist"

  local command=$1

  if ! command -v $command >/dev/null 2>&1; then
    mylog error "Executable $command does not exist or is not executable, exiting."
    exit 1
  fi

#  decho "F:OUT:check_command_exist"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the file exist, if no print a msg and exit
#
function check_file_exist() {
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN :check_file_exist"

  local file=$1
  if [ ! -e "$file" ]; then
    mylog error "No such file: $file" 1>&2
    exit 1
  fi

#  decho "F:OUT:check_file_exist"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the directory exist, if no print a msg and exit
#
function check_directory_exist() {
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN :check_directory_exist"

  local directory=$1
  if [ ! -d $directory ]; then
    mylog error "No such directory: $directory" 1>&2
    exit 1
  fi

#  decho "F:OUT:check_directory_exist"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the directory contains files, if no print a msg and exit
#
function check_directory_contains_files() {
  local directory=$1
  shopt -s nullglob dotglob # To include hidden files
  files=($directory/*)
  echo ${#files[@]}
}

######################################################
# checks if the directory exist, otherwise create it
#
function check_directory_exist_create() {
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN :check_directory_exist_create"

  local directory=$1
  if [ ! -d $directory ]; then
    mkdir -p $directory
  fi

#  decho "F:OUT:check_directory_exist_create"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
function read_config_file() {
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN  :read_config_file"

  local lf_config_file
  if test -n "$PC_CONFIG"; then
    lf_config_file="$PC_CONFIG"
  else
    lf_config_file="$1"
  fi
  if test -z "$lf_config_file"; then
    mylog error "Usage: $0 <config file>" 1>&2
    mylog info "Example: $0 ${MAINSCRIPTDIR}cp4i.conf"

#    decho "F:OUT:read_config_file"
#    SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
    exit 1
  fi

  check_file_exist $lf_config_file

  # load user specific variables, "set -a" so that variables are part of environment for envsubst
  set -a
  . "${lf_config_file}"
  set +a

#  decho "F:OUT:read_config_file"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check that all required executables are installed
function check_exec_prereqs() {
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
#  decho "F:IN :check_exec_prereqs"

  check_command_exist awk
  check_command_exist curl
  check_command_exist $MY_CONTAINER_ENGINE
  check_command_exist ibmcloud
  check_command_exist jq
  check_command_exist keytool
  check_command_exist oc
  check_command_exist openssl

#  decho "F:OUT:check_exec_prereqs"
#  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
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
  decho "F:IN :send_email"

  curl --url "smtp://$mail_def" \
    --mail-from cp4i-admin@ibm.com \
    --mail-rcpt cp4i-user@ibm.com \
    --upload-file ${MAINSCRIPTDIR}templates/emails/test-email.txt

  decho "F:OUT:send_email"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# wait for command to return specified value
# @param what description of waited state
# @param value expected state value from check command
# @param command executed command that returns some state
function wait_for_state() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :wait_for_state"

  local what=$1
  local value=$2
  local command=$3
  local start_time=$(date +%s)
  local current_time elapsed_time
  local bullets=('|' '/' '-' '\\')

  mylog check "Checking $what"
  #mylog check "Checking $what status until reaches value $value with command $command"
  last_state=''
  while true; do
    current_state=$(eval $command)
    if test "$current_state" = "$value"; then
      mylog ok ", $current_state"
      break
    fi
    # first time
    #if test -z "$last_state";then
    #	mylog
    #fi
    if test "$last_state" != "$current_state"; then
      mylog wait "$current_state"
      last_state=$current_state
    fi

    for bullet in "${bullets[@]}"; do
      # Use echo with -ne to print without newline and with escape sequences
      current_time=$(date +%s)
  
      # Calculate the elapsed time
      elapsed_time=$((current_time - start_time))
  
      # Display the elapsed time on the same line
      echo -ne "\rElapsed time: ${elapsed_time} seconds$bullet"      
      #echo -ne "\r$bullet Timer: $seconds seconds | Waiting...\033[0K\r"
      # Sleep for a short interval to control the speed of the animation
      sleep 0.1
    done 
  done
  decho "F:OUT:wait_for_state"
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
  decho "F:IN :check_create_oc_yaml"

  local lf_in_octype="$1"
  local lf_in_cr_name="$2"
  local lf_in_yaml_file="$3"
  local lf_in_ns="$4"

  export MY_NAMESPACE="$4"

  local newer

  check_file_exist $lf_in_yaml_file
  mylog check "Checking ${lf_in_octype} ${lf_in_cr_name} in ${lf_in_ns} project"
  decho "oc -n ${lf_in_ns} get ${lf_in_octype} ${lf_in_cr_name}"

  if oc -n ${lf_in_ns} get ${lf_in_octype} ${lf_in_cr_name} >/dev/null 2>&1; then
    is_cr_newer $lf_in_octype $lf_in_cr_name $lf_in_yaml_file $lf_in_ns
    newer=$?
    if [ $newer -eq 1 ]; then
      mylog info "OK: Custom Resource $lf_in_cr_name is newer than file $lf_in_yaml_file"
    else
      envsubst <"${lf_in_yaml_file}" | oc -n ${lf_in_ns} apply -f - || exit 1
    fi
  else
    envsubst <"${lf_in_yaml_file}" | oc -n ${lf_in_ns} apply -f - || exit 1
  fi

  decho "F:OUT:check_create_oc_yaml"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param namespace
function provision_persistence_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :provision_persistence_openldap"

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

  decho "F:OUT:provision_persistence_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "openldap"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
function deploy_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :deploy_openldap"

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

  decho "F:OUT:deploy_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "mailhog"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
# To add a user/password protection to the web UI: https://stackoverflow.com/questions/60162842/how-can-i-add-basic-authentication-to-the-mailhog-service-in-ddev-local
function deploy_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :deploy_mailhog"

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
  decho "F:OUT:deploy_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check if the service is already exposed
function is_service_exposed() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :is_service_exposed"

  local lf_in_namespace="$1"
  local lf_in_service_name="$2"
  local lf_in_port="$3"

  local lf_port_name lf_res

  lf_port_name=$(oc -n "${lf_in_namespace}" get service "${lf_in_service_name}" -o json | jq --argjson port "$lf_in_port" '.spec.ports[] | select(.nodePort == $port) |.name')
  if [ -z "$lf_port_name" ]; then
    lf_res=1
  else
    lf_res=0
  fi
  decho "F:OUT:is_service_exposed"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
}

#===========================================
# Function to add entry if it doesn't exist
function add_entry_if_not_exists() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :add_entry_if_not_exists"

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

  decho "F:OUT:add_entry_if_not_exists"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#========================================================
# Function to add ldif file entries if each doesn't exist
function add_ldif_file () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :add_ldif_file"

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

  decho "F:OUT:add_ldif_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param name: name of the resource, example: "openldap"
# @param namespace: the namespace to use
function expose_service_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :expose_service_openldap"

  local lf_in_name="$1" 
  local lf_in_namespace="$2"

  # expose service externaly and get host and port
  oc -n ${lf_in_namespace} get service ${lf_in_name} -o json | jq '.spec.ports |= map(if .name == "389-tcp" then . + { "nodePort": 30389 } else . end)' | jq '.spec.ports |= map(if .name == "636-tcp" then . + { "nodePort": 30686 } else . end)' >${WORKINGDIR}openldap-service.json
  lf_port0=$(oc -n ${lf_in_namespace} get service ${lf_in_name} -o jsonpath='{.spec.ports[0].nodePort}')
  lf_port1=$(oc -n ${lf_in_namespace} get service ${lf_in_name} -o jsonpath='{.spec.ports[1].nodePort}')

  is_service_exposed "${lf_in_namespace}" "${lf_in_name}" "${lf_port0}"
  if [ $? -eq 0 ]; then
    mylog info "Service ${lf_in_name} using port ${lf_port0} is already exposed."
  else
    mylog info "Service ${lf_in_name} using port ${lf_port0} is not exposed."
    oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port0}
  fi

  is_service_exposed "${lf_in_namespace}" "${lf_in_name}" "${lf_port1}"
  if [ $? -eq 0 ]; then
    mylog info "Service ${lf_in_name} using port ${lf_port1} is already exposed."
  else
    mylog info "Service ${lf_in_name} using port ${lf_port1} is not exposed."
    oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port1}
  fi

  lf_hostname=$(oc -n ${lf_in_namespace} get route openldap-external -o jsonpath='{.spec.host}')

  # load users and groups into LDAP
  #envsubst <"${YAMLDIR}ldap/ldap-users.ldif" >"${WORKINGDIR}ldap-users.ldif"
  mylog info "Adding LDAP entries with following command: "
  mylog info "$LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${WORKINGDIR}ldap-users.ldif"
  add_ldif_file ${WORKINGDIR}ldap-users.ldif "ldap://${lf_hostname}:${lf_port0}" "${ldap_admin_dn}" "${ldap_admin_password}"
  #$LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -c -f ${WORKINGDIR}ldap-users.ldif

  mylog info "You can search entries with the following command: "
  # ldapmodify -H ldap://$lf_hostname:$lf_port0 -D "$ldap_admin_dn" -w admin -f ${LDAPDIR}Import.ldiff
  mylog info "ldapsearch -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""

  decho "F:OUT:expose_service_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}
################################################
# @param name: name of the resource, example: "mailhog"
# @param namespace: the namespace to use
function expose_service_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :expose_service_mailhog"

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
  decho "MailHog accessible at ${lf_hostname}"

  decho "F:OUT:expose_service_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create namespace
# @param ns namespace to be created
function create_namespace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :create_namespace"

  local lf_in_ns=$1
  var_fail MY_OC_PROJECT "Please define project name in config"
  mylog check "Checking project $lf_in_ns"
  if oc get project $lf_in_ns >/dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $lf_in_ns"
    if ! oc new-project $lf_in_ns; then
      decho "F:OUT:create_namespace"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
  fi

  decho "F:OUT:create_namespace"
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
  decho "F:IN :check_resource_availability"

  local lf_in_type="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"

  decho "oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}'"
  var=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  while test -z $var; do
    var=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  done
  #SB]20231013 simulate a return value by echoing it
  #echo $var
  # SB]20240519 due to many problems with the return value, I will use an export variable to return the value
  export MY_RESOURCE=$var

  decho "F:OUT:check_resource_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
function check_add_cs_ibm_pak() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :check_add_cs_ibm_pak"

  local lf_in_case_name="$1"
  local lf_in_case_version_varid="$2"
  local lf_in_arch="$3"

  local lf_case_version=${!lf_in_case_version_varid}
  local file
  local downloaded

  SECONDS=0

  is_case_downloaded ${lf_in_case_name} ${lf_in_case_version_varid} #1>&2 > /dev/null
  downloaded=$?

  if [ $downloaded -eq 1 ]; then
    mylog info "case ${lf_in_case_name} ${lf_case_version} already downloaded"
  else
    oc ibm-pak get ${lf_in_case_name} --version ${lf_case_version}
    oc ibm-pak generate mirror-manifests ${lf_in_case_name} icr.io --version ${lf_case_version}
  fi

  file=~/.ibm-pak/data/mirror/${lf_in_case_name}/${lf_case_version}/catalog-sources.yaml
  if [ -e "$file" ]; then
    oc apply -f $file
  fi

  file=~/.ibm-pak/data/mirror/${lf_in_case_name}/${lf_case_version}/catalog-sources-linux-${lf_in_arch}.yaml
  if [ -e "$file" ]; then
    oc apply -f $file
  fi

  mylog info "Adding case $lf_in_case_name took $SECONDS seconds to execute." 1>&2

  decho "F:OUT:check_add_cs_ibm_pak"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20231201 create operator subscription
function create_operator_subscription() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :create_operator_subscription"

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  export MY_OPERATOR_NAME=$1
  export MY_CATALOG_SOURCE_NAME=$2
  export MY_OPERATOR_NAMESPACE=$3
  export MY_STRATEGY=$4
  local lf_in_wait=$5
  local lf_in_csv_name=$6

  local file path resource state type
  check_directory_exist ${OPERATORSDIR}

  SECONDS=0

  file="${OPERATORSDIR}subscription.yaml"
  type="Subscription"
  check_create_oc_yaml "${type}" "${MY_OPERATOR_NAME}" "${file}" "${MY_OPERATOR_NAMESPACE}"

  type="clusterserviceversion"
  path="{.status.phase}"
  state="Succeeded"
  decho "oc -n $MY_OPERATOR_NAMESPACE get $type -o json | jq -r --arg my_resource \"$lf_in_csv_name\" '.items[].metadata | select (.name | contains ($my_resource)).name'"

  seconds=0
  while [ -z "$resource" ]; do
    echo -ne "Timer: $seconds seconds | Creating csv...\033[0K\r"
    sleep 1
    resource=$(oc -n $MY_OPERATOR_NAMESPACE get $type -o json | jq -r --arg my_resource "$lf_in_csv_name" '.items[].metadata | select (.name | contains ($my_resource)).name')
    seconds=$((seconds + 1))
  done

  #resource=$(oc -n $MY_OPERATOR_NAMESPACE get $type -o json | jq -r  --arg my_resource "$lf_in_csv_name" '.items[].metadata | select (.name | contains ($my_resource)).name')
  decho "resource=$resource|lf_in_csv_name=$lf_in_csv_name"
  if [ $lf_in_wait ]; then
    wait_for_state "$type $resource $path is $state" "$state" "oc -n $MY_OPERATOR_NAMESPACE get $type $resource -o jsonpath='$path'"
  fi
  mylog info "Creation of $MY_OPERATOR_NAME operator took $SECONDS seconds to execute." 1>&2

  decho "F:OUT:create_operator_subscription"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20231204 create operand instance
function create_operand_instance() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :create_operand_instance"

  local lf_in_file=$1
  local lf_in_ns=$2
  local lf_in_path=$3
  local lf_in_resource=$4
  local lf_in_state=$5
  local lf_in_type=$6
  local lf_in_wait=$7

  SECONDS=0
  check_create_oc_yaml $lf_in_type $lf_in_resource $lf_in_file $lf_in_ns
  decho "wait_for_state | $lf_in_type $lf_in_resource $lf_in_path is $lf_in_state | $lf_in_state | oc -n $lf_in_ns get $lf_in_type $lf_in_resource -o jsonpath=$lf_in_path"
  if [ $lf_in_wait ]; then
    wait_for_state "$lf_in_type $lf_in_resource $lf_in_path is $lf_in_state" "$lf_in_state" "oc -n $lf_in_ns get $lf_in_type $lf_in_resource -o jsonpath='$lf_in_path'"
  fi
  mylog info "Creation of $lf_in_type instance took $SECONDS seconds to execute." 1>&2

  decho "F:OUT:create_operand_instance"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Get useful information to start using the stack
# Need to check that the resource exist.
function get_navigator_access() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :get_navigator_access"

  cp4i_url=$(oc -n $MY_OC_PROJECT get platformnavigator cp4i-navigator -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
  # cp4i_uid=$(oc -n $MY_OC_PROJECT get secret ibm-iam-bindinfo-platform-auth-idp-credentials -o jsonpath={.data.admin_username} | base64 -d)
  mylog info "CP4I Platform UI URL: " $cp4i_url
  # mylog info "CP4I admin user: " $cp4i_uid
  # mylog info "CP4I admin password: " $cp4i_pwd

  decho "F:OUT:get_navigator_access"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#########################################################################################################
##SB]20231109 Generate properties and yaml/json files
## input parameter the operand custom dir (and generated dir both with config and scripts subdirectories)
function generate_files() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :generate_files"

  local customdir=$1
  local gendir=$2
  local transform=$3
  local nfiles

  # generate the differents properties files
  # SB]20231109 some generated files (yaml/json) are based on other generated files (properties), so :
  # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml or .json)
  # - generate first the *.properties files to be sourced then generate the *.yaml/*.json files

  config_customdir="${customdir}config/"
  scripts_customdir="${customdir}scripts/"
  config_gendir="${gendir}config/"
  scripts_gendir="${gendir}scripts/"

  # set -a
  # Start with *.properties files
  nfiles=$(check_directory_contains_files $scripts_customdir)
  if [ $nfiles -gt 0 ]; then
    for file in ${scripts_customdir}*; do
      filename=$(basename -- "$file")
      cat $file | envsubst >"${scripts_gendir}${filename}"
      #  . "${scripts_gendir}${filename}"
    done
  fi

  # Continue *.yaml files
  nfiles=$(check_directory_contains_files $config_customdir)
  if [ $nfiles -gt 0 ]; then
    for file in ${config_customdir}*; do
      filename=$(basename -- "$file")
      if $transform; then
        # mylog info "Transform $file file"
        cat $file | envsubst >"${config_gendir}${filename}"
      else
        # mylog info "Copy $file file"
        cat $file >"${config_gendir}${filename}"
      fi
    done
  fi
  #set +a
  decho "F:OUT:generate_files"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#############################################################################################################################
function create_catalogsource() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :create_catalogsource"

  export CATALOG_SOURCE_NAMESPACE=$1
  export CATALOG_SOURCE_NAME=$2
  export CATALOG_SOURCE_DISPLAY_NAME=$3
  export CATALOG_SOURCE_IMAGE=$4
  export CATALOG_SOURCE_PUBLISHER=$5
  export CATALOG_SOURCE_INTERVAL=$6

  local newer
  local type="CatalogSource"
  local file="${RESOURCSEDIR}catalog_source.yaml"
  local path="{.status.connectionState.lastObservedState}"
  local state="READY"

  result=$(oc get $type -A -o json | jq -r --arg name $CATALOG_SOURCE_NAME --arg namespace $CATALOG_SOURCE_NAMESPACE '.items[] | select (.metadata.name == $name and .metadata.namespace == $namespace)')
  if [ -z "$result" ]; then
    mylog info "no catalogsource $CATALOG_SOURCE_NAME found in namespace $CATALOG_SOURCE_NAMESPACE"
    envsubst <"${file}" | oc -n ${CATALOG_SOURCE_NAMESPACE} apply -f - || exit 1
    wait_for_state "$type $CATALOG_SOURCE_NAME $path is $state" "$state" "oc -n ${CATALOG_SOURCE_NAMESPACE} get ${type} ${CATALOG_SOURCE_NAME} -o jsonpath='$path'"
  else
    is_cr_newer $type $CATALOG_SOURCE_NAME $file $CATALOG_SOURCE_NAMESPACE
    if [ $? -eq 1 ]; then
      mylog info "Custom Resource $CATALOG_SOURCE_NAME exists in ns $CATALOG_SOURCE_NAMESPACE and is newer than file $file"
    else
      envsubst <"${file}" | oc -n ${CATALOG_SOURCE_NAMESPACE} apply -f - || exit 1
      wait_for_state "$type $CATALOG_SOURCE_NAME $path is $state" "$state" "oc -n ${CATALOG_SOURCE_NAMESPACE} get ${type} ${CATALOG_SOURCE_NAME} -o jsonpath='$path'"
    fi
  fi

  decho "F:OUT:create_catalogsource"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#########################################################################################################
## adapt file into working dir
## called generate_files before
function adapt_file() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN :adapt_file"

  local sourcedir=$1
  local destdir=$2
  local filename=$3

  if [ ! -d ${destdir} ]; then
    mkdir -p ${destdir}
  fi
  if [ -e "${sourcedir}$filename" ]; then
    cat "${sourcedir}$filename" | envsubst >"${destdir}${filename}"
  fi

  decho "F:OUT:adapt_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}
