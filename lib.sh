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
# Print message with levels
# @param 1:
# @param 2:
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
# @param 1:
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
# Compare two version strings as arguments and compares them component-wise.
# It uses the IFS (Internal Field Separator) to split the versions into components based on the dot ('.') separator.
# It then compares each component, determining whether the first version is older, newer, or equal to the second version.
# The script will output whether the first version is older, newer, or equal to the second version.
# cmp_versions v1 v2 returns 0 if v1=v2, 1 if v1 is older than v2, 2 if v1 is newer than v2
function cmp_versions() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :cmp_versions"

  local lf_in_version1=$1
  local lf_in_version2=$2
  decho 3 "lf_in_version1=$lf_in_version1|lf_in_version2=$lf_in_version2"

  # Just try to compare the versions using string comparison if they are equal
  if [ "$lf_in_version1" == "$lf_in_version2" ]; then
    #echo "$lf_in_version1 is equal to $lf_in_version2"
    decho 3 "F:OUT:cmp_versions"
    SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
    return 0
  fi

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
# Save a certificate in pem format from secret
# @param 1: namespace where the secret exist
# @param 2: name of the secret
# @param 3: Data in the secret that contains the certificate
# @param 4: Directory where to save the certificate
function save_certificate() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :save_certificate"

  local lf_in_ns=$1
  local lf_in_secret_name=$2
  local lf_in_data_name=$3
  local lf_in_destination_path=$4

  local lf_data_normalised=$(sed 's/\./\\./g' <<< ${lf_in_data_name})

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"
  decho 6 "oc -n cp4i get secret ${lf_in_secret_name} -o jsonpath=\"{.data.$lf_data_normalised}\""
  cert=$(oc -n cp4i get secret ${lf_in_secret_name} -o jsonpath="{.data.$lf_data_normalised}")
  echo $cert | base64 --decode >"${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"

  decho 3 "F:OUT:save_certificate"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))

}

################################################
# Check that the CASE is already downloaded
# example pour filtrer avec conditions :
# avec jsonpath=$.[?(@.name=='ibm-licensing' && @.version=='4.2.1')]
# Pour tester une variable null : https://stackoverflow.com/questions/48261038/shell-script-how-to-check-if-variable-is-null-or-no
# @param 1:
# @param 2:
function is_case_downloaded() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :is_case_downloaded"
  local lf_in_case=$1
  local lf_in_version=$2

  decho 3 "lf_in_case=$lf_in_case|lf_in_version=$lf_in_version"

  local lf_result lf_latestversion lf_cmp lf_res
  local lf_directory="${MY_IBMPAK_CASESDIR}${lf_in_case}/${lf_in_version}"

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

  decho 3 "F:OUT:is_case_downloaded"
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
# @param 1:
# @param 2:
# @param 3:
# @param 4:
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
# @param 1:
function check_command_exist() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 5 "F:IN :check_command_exist"

  local command=$1

  if ! command -v $command >/dev/null 2>&1; then
    mylog error "Executable $command does not exist or is not executable, exiting."
    exit 1
  fi

  decho 5 "F:OUT:check_command_exist"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the file exist, if no print a msg and exit
# @param 1:
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
# @param 1:
function check_directory_exist() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :check_directory_exist"

  local directory=$1
  if [ ! -d $directory ]; then
    mylog error "No such directory: $directory" 1>&2
    exit 1
  fi

  decho 3 "F:OUT:check_directory_exist"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################
# checks if the directory contains files, if no print a msg and exit
# @param 1:
function check_directory_contains_files() {
  # SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  # decho 3 "F:IN :check_directory_contains_files"

  local lf_in_directory=$1
  local lf_files
  shopt -s nullglob dotglob # To include hidden files
  lf_files=$(find . -maxdepth 1 -type f | wc -l)

    # decho 3 "F:OUT:check_directory_contains_files"
  # SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))

  return $lf_files
}

######################################################
# checks if the directory exist, otherwise create it
# @param 1:
function check_directory_exist_create() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :check_directory_exist_create"

  local directory=$1
  if [ ! -d $directory ]; then
    mkdir -p $directory
  fi

  decho 4 "F:OUT:check_directory_exist_create"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# 
# @param 1:
function read_config_file() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 5 "F:IN :read_config_file"

  local lf_config_file=$1

  if test -z "$lf_config_file"; then
    mylog error "Usage: $0 <config file>" 1>&2
    mylog info "Example: $0 ${MAINSCRIPTDIR}cp4i.conf"

    decho 5 "F:OUT:read_config_file"
    SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
    exit 1
  fi

  check_file_exist $lf_config_file

  # load user specific variables, "set -a" so that variables are part of environment for envsubst
  set -a
  . "${lf_config_file}"
  set +a

  decho 5 "F:OUT:read_config_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check that all required executables are installed
# No parameters.
function check_exec_prereqs() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :check_exec_prereqs"

  check_command_exist awk
  check_command_exist tr
  check_command_exist curl
  check_command_exist $MY_CONTAINER_ENGINE
  check_command_exist ibmcloud
  check_command_exist jq
  check_command_exist keytool
  check_command_exist oc
  check_command_exist openssl
  check_command_exist helm
  if $MY_MQ_CUSTOM; then
    check_command_exist runmqakm
  fi

  if $MY_LDAP; then
    check_command_exist ldapsearch
  fi

  # check resource exist
  local lf_in_type=storageclass
  local lf_in_name=$MY_BLOCK_STORAGE_CLASS

  local res
  
  res=$(oc get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  if test -z $res; then
    mylog error "Resource $lf_in_name of type $lf_in_type does not exist, exiting."
    exit 1
  fi
  lf_in_name=$MY_FILE_STORAGE_CLASS
  res=$(oc get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  if test -z $res; then
    mylog error "Resource $lf_in_name of type $lf_in_type does not exist, exiting."
    exit 1
  fi
  lf_in_name=$MY_FILE_LDAP_STORAGE_CLASS
  res=$(oc get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  if test -z $res; then
    mylog error "Resource $lf_in_name of type $lf_in_type does not exist, exiting."
    exit 1
  fi
  
  decho 3 "F:OUT:check_exec_prereqs"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Wait n secs
# @param secs: number of seconds to wait for and displays it on the same line
# @param 1:

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
# @param 1: what description of waited state
# @param 2: value expected state value from check command
# @param 3: command executed command that returns some state
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
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
function add_ibm_entitlement() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :add_ibm_entitlement"

  local lf_in_ns=$1

  mylog check "Checking ibm-entitlement-key in $lf_in_ns"
  if oc -n $lf_in_ns get secret ibm-entitlement-key >/dev/null 2>&1; then
    mylog ok
  else
    var_fail MY_ENTITLEMENT_KEY "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    $MY_CONTAINER_ENGINE -h >/dev/null 2>&1
    if test $? -eq 0 && ! echo $MY_ENTITLEMENT_KEY | $MY_CONTAINER_ENGINE login cp.icr.io --username cp --password-stdin; then
      mylog error "Invalid entitlement key" 1>&2
      decho 3 "F:OUT:add_ibm_entitlement"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $lf_in_ns"
    if ! oc -n $lf_in_ns create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io; then
      decho 3 "F:OUT:add_ibm_entitlement"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
  fi

  decho 3 "F:OUT:add_ibm_entitlement"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# delete ibm entitlement key from namespace
# @param ns namespace where secret will be deleted
function delete_ibm_entitlement() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :delete_ibm_entitlement"

  local lf_in_ns=$1

  mylog check "Checking ibm-entitlement-key in $lf_in_ns"
  if oc -n $lf_in_ns get secret ibm-entitlement-key >/dev/null 2>&1; then
    oc -n $lf_in_ns delete secret ibm-entitlement-key 
  else
    mylog info "ibm-entitlement-key already deleted from namespace $lf_in_ns"
  fi

  decho 3 "F:OUT:delete_ibm_entitlement"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check if the resource of type octype with name name exists in the namespace ns.
# If it does not exist use the yaml file, with the appropriate variable.
# @param 1: octype: kubernetes resource class, example: "subscription"
# @param 2: name: name of the resource, example: "ibm-integration-platform-navigator"
# @param 3: yaml: the file with the definition of the resource, example: "${subscriptionsdir}Navigator-Sub.yaml"
# @param 4: ns: name space where the resource is created, example: $MY_OPERATORS_NAMESPACE
function check_create_oc_yaml() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :check_create_oc_yaml"

  local lf_in_octype="$1"
  local lf_in_cr_name="$2"
  local lf_in_yaml_file="$3"
  local lf_in_ns="$4"

  # Todo Why this line?
  export MY_OPERATORGROUP="$2"
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
# 
# @param 1: namespace
function provision_persistence_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :provision_persistence_openldap"

  local lf_in_namespace="$1"
  # handle persitence for Openldap
  # only check one, assume that if one is created the other one is also created (short cut to optimize time)
  mylog check "Checking persistent volume claim for LDAP in ${lf_in_namespace}"
  if oc -n ${lf_in_namespace} get "PersistentVolumeClaim" "pvc-ldap-main" >/dev/null 2>&1; then mylog ok; else
    envsubst <"${MY_YAMLDIR}ldap/ldap-pvc.main.yaml" >"${MY_WORKINGDIR}ldap-pvc.main.yaml"
    envsubst <"${MY_YAMLDIR}ldap/ldap-pvc.config.yaml" >"${MY_WORKINGDIR}ldap-pvc.config.yaml"
    oc -n ${lf_in_namespace} create -f ${MY_WORKINGDIR}ldap-pvc.main.yaml
    oc -n ${lf_in_namespace} create -f ${MY_WORKINGDIR}ldap-pvc.config.yaml
    wait_for_state "pvc pvc-ldap-config status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-config -o jsonpath='{.status.phase}'"
    wait_for_state "pvc pvc-ldap-main status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-main -o jsonpath='{.status.phase}'"
  fi

  decho 3 "F:OUT:provision_persistence_openldap"
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
  # check if deployment already performed
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
      oc -n ${lf_in_namespace} get deployment.apps/openldap -o json | jq '. | del(."status")' >${MY_WORKINGDIR}openldap.json
      envsubst <"${MY_YAMLDIR}ldap/ldap-config.json" >"${MY_WORKINGDIR}ldap-config.json"
      oc -n ${lf_in_namespace} patch deployment.apps/openldap --patch-file ${MY_WORKINGDIR}ldap-config.json
    fi
  fi

  decho 3 "F:OUT:deploy_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param 1: octype: kubernetes resource class, example: "deployment"
# @param 2: ocname: name of the resource, example: "mailhog"
# @param 3:
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
# To add a user/password protection to the web UI: https://stackoverflow.com/questions/60162842/how-can-i-add-basic-authentication-to-the-mailhog-service-in-ddev-local
function deploy_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :deploy_mailhog"

  local lf_in_octype="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"

  # check if deployment already performed
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
# @param 1:
# @param 2:
# @param 3:
function is_service_exposed() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :is_service_exposed"

  local lf_in_namespace="$1"
  local lf_in_service_name="$2"
  local lf_in_port="$3"

  local lf_port_name lf_res

  lf_port_name=$(oc -n "${lf_in_namespace}" get service "${lf_in_service_name}" -o json | jq --argjson port "$lf_in_port" '.spec.ports[] | select(.nodePort == $port) |.name')
  decho 3 "lf_port_name=$lf_port_name"
  
  if [ -z "$lf_port_name" ]; then
    lf_res=1
  else
    lf_res=0
  fi
  decho 3 "F:OUT:is_service_exposed"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  return $lf_res
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
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :add_ldap_entry_if_not_exists"

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
      mylog info "Entry $lf_in_entry_dn already exists. Skipping."
    else
      decho 3 "Entry $lf_in_entry_dn does not exist. Adding entry."
      mylog info "$lf_in_entry_content" > $lf_in_tmp_ldif_file
      ldapadd -x -H $lf_in_ldap_server -D "$lf_in_admin_dn" -w $lf_in_admin_password -f $lf_in_tmp_ldif_file
    fi
  fi

  decho 3 "F:OUT:add_ldap_entry_if_not_exists"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#========================================================
# add ldif file entries if each doesn't exist
# @param 1:
# @param 2:
# @param 3:
# @param 4:
function add_ldif_file () {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :add_ldif_file"

  local lf_in_ldif_file="$1"
  local lf_in_ldap_server="$2"
  local lf_in_admin_dn="$3"
  local lf_in_admin_password="$4"

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

  decho 3 "F:OUT:add_ldif_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# @param 1: name: name of the resource, example: "openldap"
# @param 2: namespace: the namespace to use
function expose_service_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :expose_service_openldap"

  local lf_in_name="$1" 
  local lf_in_namespace="$2"
  local lf_hostname

  decho 3 "lf_in_name=$lf_in_name|lf_in_namespace=$lf_in_namespace"

  # expose service externaly and get host and port
  oc -n ${lf_in_namespace} get service ${lf_in_name} -o json | jq '.spec.ports |= map(if .name == "389-tcp" then . + { "nodePort": 30389 } else . end)' | jq '.spec.ports |= map(if .name == "636-tcp" then . + { "nodePort": 30686 } else . end)' >${MY_WORKINGDIR}openldap-service.json

  # Saad there was a bug the openldap-service.json did not exist when those two calls were made in the deploy_openldap function, I moved them here
  # I do not think all this code is needed, what did you want to do?
  oc -n ${lf_in_namespace} patch service ${lf_in_name} -p='{"spec": {"type": "NodePort"}}'
  oc -n ${lf_in_namespace} patch service/${lf_in_name} --patch-file ${MY_WORKINGDIR}openldap-service.json

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
  envsubst <"${MY_YAMLDIR}ldap/ldap-users.ldif" >"${MY_WORKINGDIR}ldap-users.ldif"
  mylog info "Adding LDAP entries with following command: "
  mylog info "$MY_LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${MY_WORKINGDIR}ldap-users.ldif"
  add_ldif_file ${MY_WORKINGDIR}ldap-users.ldif "ldap://${lf_hostname}:${lf_port0}" "${ldap_admin_dn}" "${ldap_admin_password}"
  #$MY_LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -c -f ${MY_WORKINGDIR}ldap-users.ldif

  mylog info "You can search entries with the following command: "
  # ldapmodify -H ldap://$lf_hostname:$lf_port0 -D "$ldap_admin_dn" -w admin -f ${MY_LDAPDIR}Import.ldiff
  mylog info "ldapsearch -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""

  decho 3 "F:OUT:expose_service_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}
################################################
# @param 1: name: name of the resource, example: "mailhog"
# @param 2: namespace: the namespace to use
function expose_service_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :expose_service_mailhog"

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
  decho 3 "MailHog accessible at ${lf_hostname}"

  decho 3 "F:OUT:expose_service_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create namespace
# @param 1: ns namespace to be created
# @param 2: display name of the project
# @param 3: description of the project
function create_namespace() {
  local lf_in_name="$1"
  local lf_in_display_name="$2"
  local lf_in_description="$3"
  
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_namespace"

  lf_in_name=$1
  var_fail lf_in_name "Please define project name in config"
  mylog check "Checking project $lf_in_name"
  if oc get project $lf_in_name >/dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $lf_in_name"
    if ! oc new-project $lf_in_name --display-name="$lf_in_display_name" --description="$lf_in_description"; then
      decho 3 "F:OUT:create_namespace"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
  fi

  decho 3 "F:OUT:create_namespace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Delete namespace
# @param 1: ns namespace to be deleted
function delete_namespace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :delete_namespace"

  local lf_in_ns=$1
  var_fail lf_in_ns "Please define project name in config"
  mylog check "Checking project $lf_in_ns"
  if oc get project $lf_in_ns >/dev/null 2>&1; then oc delete project $lf_in_ns; else
    mylog info "project $lf_in_ns already deleted"
  fi

  decho 3 "F:OUT:delete_namespace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Check if the resource exists.
# @param 1: octype: kubernetes resource class, example: "subscription"
# @param 2: name: name of the resource, example: "ibm-integration-platform-navigator"
# @param 3: ns: namespace/project to perform the search
# TODO The var variable is initialised for another function, this is not good
function check_resource_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :check_resource_availability"

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

  decho 3 "F:OUT:check_resource_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
# @param 1:
# @param 2:
# @param 3: This is the version of the channel. It is an optional parameter, if ommited it is retrieved, else used values from invocation
function check_add_cs_ibm_pak() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :check_add_cs_ibm_pak"
  SECONDS=0

  local lf_in_case_name="$1"
  local lf_in_arch="$2"
  local lf_in_case_version="$3"

  local lf_case_version lf_file lf_downloaded

  #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
  if [ -z "$lf_in_case_version" ]; then
    lf_case_version=$(oc ibm-pak list -o json | jq -r --arg case "$lf_in_case_name" '.[] | select (.name == $case ) | .latestVersion')
  else
    lf_case_version=$lf_in_case_version
  fi

  #export MY_OPERATOR_CHL=$lf_case_version

  is_case_downloaded ${lf_in_case_name} ${lf_case_version} #1>&2 > /dev/null
  lf_downloaded=$?
  decho 4 "lf_downloaded=$lf_downloaded"

  if [ $lf_downloaded -eq 1 ]; then
    mylog info "case ${lf_in_case_name} ${lf_case_version} already downloaded"
  else
    oc ibm-pak get ${lf_in_case_name} --version ${lf_case_version}
    oc ibm-pak generate mirror-manifests ${lf_in_case_name} icr.io --version ${lf_case_version}
  fi

  lf_file=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources.yaml
  if [ -e "$lf_file" ]; then
    oc apply -f $lf_file
  fi

  # For Asset Repository (Exception)
  lf_file=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources-linux-${lf_in_arch}.yaml
  if [ -e "$lf_file" ]; then
    oc apply -f $lf_file
  fi

  mylog info "Adding case $lf_in_case_name took $SECONDS seconds to execute." 1>&2

  decho 3 "F:OUT:check_add_cs_ibm_pak"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
# @param 1:
# @param 2:
# @param 3: This is the version of the channel. It is an optional parameter, if ommited it is retrieved, else used values from invocation
function check_delete_cs_ibm_pak() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :check_delete_cs_ibm_pak"
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

  lf_file=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources.yaml
  if [ -e "$lf_file" ]; then
    oc delete -f $lf_file
  fi

  lf_file=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources-linux-${lf_in_arch}.yaml
  if [ -e "$lf_file" ]; then
    oc delete -f $lf_file
  fi

  mylog info "Deleting case $lf_in_case_name took $SECONDS seconds to execute." 1>&2

  decho 3 "F:OUT:check_delete_cs_ibm_pak"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20231201 create operator subscription
# @param 1: operator name 
# @param 2: namespace where the subscription is created (openshift-operators or others)
# @param 3: Operator channel
# @param 4: Control of the upgrade in the subscription, automatic or manual
# @param 5: name of the source catalog
# @param 6: Wait for the of subscription to be ready
# @param 7: csv Operator channel

function create_operator_subscription() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_operator_subscription"

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  export MY_OPERATOR_NAME=$1
  export MY_OPERATOR_NAMESPACE=$2
  export MY_OPERATOR_CHL=$3
  export MY_STRATEGY=$4
  export MY_CATALOG_SOURCE_NAME=$5
  local lf_in_wait=$6
  local lf_in_csv_name=$7

  local lf_file lf_path lf_resource lf_state lf_type
  check_directory_exist ${MY_OPERATORSDIR}

  SECONDS=0

  local lf_type="Subscription"
  local lf_cr_name="${MY_OPERATOR_NAME}"
  local lf_file="${MY_OPERATORSDIR}subscription.yaml"
  local lf_namespace="${MY_OPERATOR_NAMESPACE}"
  #lf_file="${MY_OPERATORSDIR}subscription-tekton.yaml"
  #lf_file="${MY_OPERATORSDIR}subscription_startingcsv.yaml"
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_file}" "${lf_namespace}"

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
  
  unset MY_OPERATOR_CHL

  decho 3 "F:OUT:create_operator_subscription"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
##SB]20231204 create operand instance
# @param 1:
# @param 2:
# @param 3:
# @param 4:
# @param 5:
# @param 6:
# @param 7: boolean to indicate if we are waiting for the operand to be running (defined by the combination of path and state, example respectively .status.phase and Ready)
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
  local lf_cr_name=$lf_in_resource
  check_create_oc_yaml "${lf_in_type}" "${lf_cr_name}" "${lf_in_file}" "${lf_in_ns}"

  decho 3 "wait_for_state | $lf_in_type $lf_cr_name $lf_in_path is $lf_in_state | $lf_in_state | oc -n $lf_in_ns get $lf_in_type $lf_cr_name -o jsonpath=$lf_in_path"
  if $lf_in_wait; then
    wait_for_state "$lf_in_type $lf_cr_name $lf_in_path is $lf_in_state" "$lf_in_state" "oc -n $lf_in_ns get $lf_in_type $lf_cr_name -o jsonpath='$lf_in_path'"
  fi
  mylog info "Creation of $lf_in_type instance took $SECONDS seconds to execute." 1>&2

  decho 3 "F:OUT:create_operand_instance"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#########################################################################################################
##SB]20231109 Generate properties and yaml/json files
## input parameter the operand custom dir (and generated dir both with config and scripts subdirectories)
# TODO Decide if it only works with files in the directory, or with subdirectories. Today just one level no subdirectories.
# @param 1:
# @param 2:
# @param 3:
function generate_files() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :generate_files"
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

  decho 3 "lf_config_customdir: $lf_config_customdir"
  decho 3 "lf_scripts_customdir: $lf_scripts_customdir"
  decho 3 "lf_config_gendir: $lf_config_gendir"
  decho 3 "lf_scripts_gendir: $lf_scripts_gendir"

  # set -a
  check_directory_contains_files $lf_scripts_customdir
  lf_nfiles=$?
  if [ $lf_nfiles -gt 0 ]; then
    for lf_file in ${lf_scripts_customdir}*; do
      if [ -f $lf_file ]; then
        filename=$(basename -- "$lf_file")
        cat $lf_file | envsubst >"${lf_scripts_gendir}${filename}"
        #  . "${lf_scripts_gendir}${filename}"
      fi
    done
  fi

  check_directory_contains_files $lf_scripts_customdir
  lf_nfiles=$?
  if [ $lf_nfiles -gt 0 ]; then
    for lf_file in ${lf_config_customdir}*; do
      if [ -f $lf_file ]; then
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
  decho 3 "F:OUT:generate_files"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#############################################################################################################################
# Create a catalog source
# @param 1: namespace
# @param 2: name of the catalog
# @param 3: 
# @param 4:
# @param 5:
# @param 6:
function create_catalogsource() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_catalogsource"

  export CATALOG_SOURCE_NAMESPACE=$1
  export CATALOG_SOURCE_NAME=$2
  export CATALOG_SOURCE_DISPLAY_NAME=$3
  export CATALOG_SOURCE_IMAGE=$4
  export CATALOG_SOURCE_PUBLISHER=$5
  export CATALOG_SOURCE_INTERVAL=$6

  local lf_type="CatalogSource"
  local lf_file="${MY_RESOURCESDIR}catalog_source.yaml"
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

  decho 3 "F:OUT:create_catalogsource"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

#########################################################################################################
## adapt file into working dir
## called generate_files before
# @param 1: Directory where the source file is located.
# @param 2: Target directory where the file is created.
# @param 3: name of the file (as source and for the target).
function adapt_file() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :adapt_file"

  local lf_in_sourcedir=$1
  local lf_in_destdir=$2
  local lf_in_filename=$3
  decho 4 "$lf_in_sourcedir | $lf_in_destdir | $lf_in_filename"

  if [ ! -d ${lf_in_destdir} ]; then
    mkdir -p ${lf_in_destdir}
  fi
  if [ -e "${lf_in_sourcedir}${lf_in_filename}" ]; then
    envsubst < "${lf_in_sourcedir}${lf_in_filename}" > "${lf_in_destdir}${lf_in_filename}"
  fi

  decho 3 "F:OUT:adapt_file"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
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
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_certificate_chain"
  local lf_namespace="$1"
  local lf_issuername="$2"
  local lf_root_cert_name="$3"
  local lf_tls_label1="$4"
  local lf_tls_certname="$5"
  
  local lf_type lf_cr_name lf_yaml_file
  
  mylog info "Create a certificate chain in ${lf_in_namespace} namespace"

  # For Self-signed issuer
  export TLS_CA_ISSUER_NAME=${lf_namespace}-${lf_issuername}-ca
  export TLS_NAMESPACE=${lf_namespace}

  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ Issuer_ca.yaml

  # For Self-signed Certificate and Root Certificate
  export TLS_ROOT_CERT_NAME=${lf_namespace}-${lf_root_cert_name}-ca
  export TLS_LABEL1=${lf_tls_label1}
  export TLS_CERT_ISSUER_NAME=${lf_namespace}-${lf_issuername}-tls

  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ CACertificate.yaml
  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ Issuer_non_ca.yaml

  # For TLS Certificate
  export TLS_CERT_NAME=${lf_namespace}-${lf_tls_certname}-tls
  export TLS_INGRESS=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

  adapt_file ${MY_TLS_SCRIPTDIR}config/ ${MY_TLS_GEN_CUSTOMDIR}config/ TLSCertificate.yaml

  # Create both Issuers and both Certificates
  lf_cert_namespace=${lf_namespace}
  lf_type="Issuer"
  lf_cr_name=${lf_namespace}-${lf_issuername}-ca
  lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/Issuer_ca.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

  lf_cert_namespace=${lf_namespace}
  lf_type="Certificate"
  lf_cr_name=${lf_namespace}-${lf_issuer_cert_name}-ca
  lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/CACertificate.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

  lf_cert_namespace=${lf_namespace}
  lf_type="Issuer"
  lf_cr_name=${lf_namespace}-${lf_issuername}-tls
  lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/Issuer_non_ca.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

  lf_cert_namespace=${lf_namespace}
  lf_type="Certificate"
  lf_cr_name=${lf_namespace}-${lf_tls_certname}-tls
  lf_yaml_file="${MY_TLS_GEN_CUSTOMDIR}config/TLSCertificate.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_cert_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_cert_namespace}"

  decho 3 "F:OUT:create_certificate_chain"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create openshift cluster using classic infrastructure
function create_openshift_cluster_classic() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_openshift_cluster_classic"

  SECONDS=0
  var_fail sc_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $sc_cluster_name"
  if ibmcloud ks cluster get --cluster $sc_cluster_name >/dev/null 2>&1; then
    mylog ok ", cluster exists"
    mylog info "Checking Openshift cluster took: $SECONDS seconds." 1>&2
  else
    mylog warn ", cluster does not exist"
    var_fail MY_OC_VERSION 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
    var_fail MY_CLUSTER_ZONE 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider classic'
    var_fail MY_CLUSTER_FLAVOR_CLASSIC 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $MY_CLUSTER_ZONE'
    var_fail MY_CLUSTER_WORKERS 'Speficy number of worker nodes in cluster'
    mylog info "Getting current version for OC: $MY_OC_VERSION"
    oc_version_full=$(check_openshift_version $MY_OC_VERSION)
    decho 4 "oc_version_full=$oc_version_full"

    if [ -z "$oc_version_full" ]; then
      mylog error "Failed to find full version for ${MY_OC_VERSION}" 1>&2
      #fix_oc_version
      decho 3 "F:OUT:create_openshift_cluster_classic"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
    oc_version_full=$(echo "[$oc_version_full]" | jq -r '.[] | (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) + "_openshift"')
    mylog info "Found: ${oc_version_full}"
    # create
    mylog info "Creating OpenShift cluster: $sc_cluster_name"

    SECONDS=0
    vlans=$(ibmcloud ks vlan ls --zone $MY_CLUSTER_ZONE --output json | jq -j '.[]|" --" + .type + "-vlan " + .id')
    if ! ibmcloud ks cluster create classic \
      --name $sc_cluster_name \
      --version $oc_version_full \
      --zone $MY_CLUSTER_ZONE \
      --flavor $MY_CLUSTER_FLAVOR_CLASSIC \
      --workers $MY_CLUSTER_WORKERS \
      --entitlement cloud_pak \
      --disable-disk-encrypt \
      $vlans; then
      mylog error "Failed to create cluster" 1>&2
      decho 3 "F:OUT:create_openshift_cluster_classic"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
    mylog info "Creation of the cluster took: $SECONDS seconds." 1>&2
  fi

  decho 3 "F:OUT:create_openshift_cluster_classic"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create openshift cluster using VPC infra
# use terraform because creation is more complex than classic
function create_openshift_cluster_vpc() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_openshift_cluster_vpc"

  # check vars from config file
  var_fail MY_OC_VERSION 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
  var_fail MY_CLUSTER_ZONE 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider vpc-gen2'
  var_fail MY_CLUSTER_FLAVOR_VPC 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $MY_CLUSTER_ZONE'
  var_fail MY_CLUSTER_WORKERS 'Speficy number of worker nodes in cluster'
  # set variables for terraform
  export TF_VAR_ibmcloud_api_key="$MY_IC_APIKEY"
  export TF_VAR_openshift_worker_pool_flavor="$MY_CLUSTER_FLAVOR_VPC"
  export TF_VAR_prefix="$MY_OC_PROJECT"
  export TF_VAR_region="$MY_CLUSTER_REGION"
  export TF_VAR_openshift_version=$(ibmcloud ks versions -q --show-version OpenShift | sed -Ene "s/^(${MY_OC_VERSION//./\\.}\.[^ ]*) .*$/\1/p")
  export TF_VAR_resource_group="rg-$MY_OC_PROJECT"
  export TF_VAR_openshift_cluster_name="$sc_cluster_name"
  pushd terraform
  terraform init
  terraform apply -var-file=var_override.tfvars
  popd

  decho 3 "F:OUT:create_openshift_cluster_vpc"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# TBC
function create_openshift_cluster() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_openshift_cluster"

  var_fail MY_CLUSTER_INFRA 'mylog warn "Choose one of: classic or vpc" 1>&2'
  case "${MY_CLUSTER_INFRA}" in
  classic)
    create_openshift_cluster_classic
    sc_ingress_hostname_filter=.ingressHostname
    sc_cluster_url_filter=.serverURL
    ;;
  vpc)
    create_openshift_cluster_vpc
    sc_ingress_hostname_filter=.ingress.hostname
    sc_cluster_url_filter=.masterURL
    ;;
  *)
    mylog error "Only classic and vpc for MY_CLUSTER_INFRA"
    ;;
  esac

  decho 3 "F:OUT:create_openshift_cluster"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# wait for Cluster availability
# set variable my_cluster_url
function wait_for_cluster_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :wait_for_cluster_availability"

  SECONDS=0
  wait_for_state 'Cluster state' 'normal-All Workers Normal' "ibmcloud oc cluster get --cluster $sc_cluster_name --output json|jq -r '(.state + \"-\" + .status)'"
  mylog info "Checking Cluster state took: $SECONDS seconds." 1>&2

  SECONDS=0
  mylog check "Checking Cluster URL"
  my_cluster_url=$(ibmcloud ks cluster get --cluster $sc_cluster_name --output json | jq -r "$sc_cluster_url_filter")
  case "$my_cluster_url" in
  https://*)
    mylog ok " -> $my_cluster_url"
    mylog info "Checking Cluster availability took: $SECONDS seconds." 1>&2
    ;;
  *)
    mylog error "Error getting cluster URL for $sc_cluster_name" 1>&2
    decho 4  "F:OUT:wait_for_cluster_availability"
    SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
    exit 1
    ;;
  esac

  decho 3 "F:OUT:wait_for_cluster_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# wait for ingress address availability
function wait_4_ingress_address_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :wait_4_ingress_address_availability"

  SECONDS=0
  local lf_ingress_address

  mylog check "Checking Ingress address"
  firsttime=true
  case $MY_CLUSTER_INFRA in
  classic)
    sc_ingress_hostname_filter=.ingressHostname
    ;;
  vpc)
    sc_ingress_hostname_filter=.ingress.hostname
    ;;
  *)
    mylog error "Only classic and vpc for MY_CLUSTER_INFRA"
    ;;
  esac

  while true; do
    lf_ingress_address=$(ibmcloud ks cluster get --cluster $sc_cluster_name --output json | jq -r "$sc_ingress_hostname_filter")
    if test -n "$lf_ingress_address"; then
      mylog ok ", $lf_ingress_address"
      break
    fi
    if $firsttime; then
      mylog warn "not ready"
      firsttime=false
    fi
    mylog wait "waiting for ingress address"
    # It takes about 15 minutes (21 Aug 2023)
    sleep 90
  done
  mylog info "Checking Ingress availability took $SECONDS seconds to execute." 1>&2

  decho 3 "F:OUT:wait_4_ingress_address_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# SB]20231215
# SB]20231130 patcher les foundational services en acceptant la license
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm
# 3.Setting the hardware profile and accepting the license
# License: Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
function accept_license_fs() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :accept_license_fs"

  local lf_in_namespace=$1

  local accept
  decho 5 "oc -n ${lf_in_namespace} get commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} -o jsonpath='{.spec.license.accept}'"
  accept=$(oc -n ${lf_in_namespace} get commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} -o jsonpath='{.spec.license.accept}')
  decho 5 "accept=$accept"
  if [ "$accept" == "true" ]; then
    mylog info "license already accepted." 1>&2
  else
    oc -n ${lf_in_namespace} patch commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} --type merge -p '{"spec": {"license": {"accept": true}}}'
  fi

  decho 4 "F:OUT:accept_license_fs"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
function generate_password() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :generate_password"

  local lf_in_length=$1

  local lf_pattern='A-Za-z0-9!@#$%^&*()_+'

  # Generate a password based on the pattern
  local lf_password=$(cat /dev/urandom | tr -dc "$lf_pattern" | head -c "$lf_in_length")
  export USER_PASSWORD_GEN=$lf_password

  decho 4 "F:OUT:generate_password"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}