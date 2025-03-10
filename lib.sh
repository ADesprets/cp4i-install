################################################
# append text to the beginning of the file 
# 
function prepend_to_file() {
  trace_in 5 prepend_to_file

  local lf_in_text="$1"
  local lf_in_file="$2"

  if [[ -f "$lf_in_file" ]]; then
    { echo "${lf_in_text}" ; echo ; cat $lf_in_file; } > temp && mv temp $lf_in_file
  else
    { echo "#!/bin/bash"; echo ; echo $lf_in_text ; echo ;} > $lf_in_file
  fi

  trace_out 5 prepend_to_file
}

################################################
# append text to end of the file 
# 
function append_to_file() {
  trace_in 5 append_to_file

  local lf_in_text="$1"
  local lf_in_file="$2"

  if [[ -f "$lf_in_file" ]]; then
    echo "${lf_in_text}\n" >> $lf_in_file
  else
    { echo "#!/bin/bash"; echo ; echo "${lf_in_text}" ; echo ;} > $lf_in_file
  fi

  trace_out 5 append_to_file
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

  if [ -n "$lf_deny_all" ] || [ -n "$lf_allow_same_namespace" ]; then
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
  trace_in 5 cmp_versions

  local lf_in_version1=$1
  local lf_in_version2=$2
  decho 3 "lf_in_version1=$lf_in_version1|lf_in_version2=$lf_in_version2"

  # Just try to compare the versions using string comparison if they are equal
  if [ "$lf_in_version1" == "$lf_in_version2" ]; then
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

  local lf_data_normalised=$(sed 's/\./\\./g' <<< ${lf_in_data_name})

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"
  decho 6 "oc -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath=\"{.data.$lf_data_normalised}\""
  local lf_cert=$(oc -n $lf_in_ns get secret ${lf_in_secret_name} -o jsonpath="{.data.$lf_data_normalised}")

  local lf_apply_cmd="echo $lf_cert | base64 --decode > ${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"
  local lf_delete_cmd="rm ${lf_in_destination_path}${lf_in_secret_name}.${lf_in_data_name}.pem"
  append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
  prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
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

  trace_out 5 is_case_downloaded
  return $lf_res
}

################################################
# Check that all required executables are installed
# @param 1:
function check_command_exist() {
  trace_in 5 check_command_exist

  local lf_in_command=$1

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
  if [ ! -e "$lf_in_file" ]; then
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
  if [ ! -d $lf_in_directory ]; then
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
  if [ ! -d $lf_in_directory ]; then
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

  if test -z "$lf_in_config_file"; then
    mylog error "Usage: $0 <config file>" 1>&2
    mylog info "Example: $0 ${MAINSCRIPTDIR}cp4i.conf"

    trace_out 5 read_config_file
    exit 1
  fi

  check_file_exist $lf_in_config_file

  # load user specific variables, "set -a" so that variables are part of environment for envsubst
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
  trace_in 3 check_resource_exist

  local lf_in_type=$1
  local lf_in_name=$2

  # check resource exist
  local lf_res
  
  lf_res=$(oc get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  if test -z $lf_res; then
    mylog error "Resource $lf_in_name of type $lf_in_type does not exist, exiting."
    return 1
  fi

  trace_out 3 check_resource_exist
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
# Send email
# @param mail_def, exemple 159.8.70.38:2525
function send_email() {
  trace_in 3 send_email

  curl --url "smtp://$mail_def" \
    --mail-from cp4i-admin@ibm.com \
    --mail-rcpt cp4i-user@ibm.com \
    --upload-file ${MAINSCRIPTDIR}templates/emails/test-email.txt

  trace_out 3 send_email
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
  local lf_start_time=$(date +%s)
  local lf_current_time lf_elapsed_time lf_last_state lf_current_state lf_bullet
  local lf_bullets=('|' '/' '-' '\\')

  mylog check "Checking $lf_in_what with $lf_in_command"
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
  trace_out 3 wait_for_state
}

################################################
# Log in IBM Cloud
function login_2_ibm_cloud() {
  trace_in 4 login_2_ibm_cloud

  if ! ${TECHZONE}; then
    SECONDS=0

    if ibmcloud resource groups -q >/dev/null 2>&1; then
      mylog info "user already logged to IBM Cloud."
    else
      mylog info "user not logged to IBM Cloud." 1>&2
      var_fail MY_IC_APIKEY "Create and save API key JSON file from: https://cloud.ibm.com/iam/apikeys"
      mylog check "Login to IBM Cloud"
      if ! ibmcloud login -q --no-region --apikey $MY_IC_APIKEY >/dev/null; then
        mylog error "Fail to login to IBM Cloud, check API key: $MY_IC_APIKEY" 1>&2
        trace_out 4 login_2_ibm_cloud
        exit 1
      else
        mylog ok
        mylog info "Connecting to IBM Cloud took: $SECONDS seconds." 1>&2
      fi
    fi
  fi

  trace_out 4 login_2_ibm_cloud
}

######################################################################
# Create openshift cluster if it does not exist
# and wait for both availability of the cluster and the ingress address
function create_openshift_cluster_wait_4_availability() {
  trace_in 3 create_openshift_cluster_wait_4_availability

  if ! ${TECHZONE}; then
    # Create openshift cluster
    create_openshift_cluster

    # Wait for Cluster availability
    wait_for_cluster_availability

    # Wait for ingress address availability
    wait_4_ingress_address_availability
  fi

  trace_out 3 create_openshift_cluster_wait_4_availability
}

################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
# requires var my_cluster_url
function login_2_openshift_cluster() {
  trace_in 4 login_2_openshift_cluster

  SECONDS=0

  if oc whoami >/dev/null 2>&1; then
    mylog info "user already logged to openshift cluster."
  else
    if $TECHZONE; then
      oc login -u ${MY_TECHZONE_USERNAME} -p ${MY_TECHZONE_PASSWORD} ${MY_TECHZONE_OPENSHIFT_API_URL}
    else
      mylog check "Login to cluster"
      # SB 20231208 The following command sets your command line context for the cluster and download the TLS certificates and permission files for the administrator.
      # more details here : https://cloud.ibm.com/docs/openshift?topic=openshift-access_cluster#access_public_se
      ibmcloud ks cluster config --cluster ${sc_cluster_name} --admin
      while ! oc login -u apikey -p $MY_IC_APIKEY --server=$my_cluster_url >/dev/null; do
        mylog error "$(date) Fail to login to Cluster, retry in a while (login using web to unblock)" 1>&2
        sleep 30
      done
      mylog ok
      mylog info "Logging to Cluster took: $SECONDS seconds." 1>&2
    fi
  fi

  trace_out 4 login_2_openshift_cluster
}

################################################
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
function add_ibm_entitlement() {
  trace_in 3 add_ibm_entitlement

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
      trace_out 3 add_ibm_entitlement
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $lf_in_ns"

    local lf_apply_cmd="oc -n $lf_in_ns create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io"
    local lf_delete_cmd="oc -n $lf_in_ns delete secret ibm-entitlement-key"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    if ! oc -n $lf_in_ns create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io; then
      trace_out 3 add_ibm_entitlement
      exit 1
    fi
  fi

  trace_out 3 add_ibm_entitlement
}

################################################
# Check if the resource of type octype with name name exists in the namespace ns.
# If it does not exist use the yaml file, with the appropriate variable.
# @param 1: octype: kubernetes resource class, example: "subscription"
# @param 2: name: name of the resource, example: "ibm-integration-platform-navigator"
# @param 3: dir: the source directory example: "${subscriptionsdir}"
# @param 4: dir: the target directory example: "${workingdir}apic/"
# @param 5: yaml: the file with the definition of the resource, example: "Navigator-Sub.yaml"
function check_create_oc_yaml() {
  trace_in 3 check_create_oc_yaml

  local lf_in_type="$1"
  local lf_in_cr_name="$2"
  local lf_in_source_directory="$3"
  local lf_in_target_directory="$4"
  local lf_in_yaml_file="$5"

  local lf_source_yaml_file lf_target_yaml_file lf_apply_cmd lf_delete_cmd

  lf_source_yaml_file="${lf_in_source_directory}${lf_in_yaml_file}"
  lf_target_yaml_file="${lf_in_target_directory}${lf_in_yaml_file}"
  
  check_file_exist "${lf_source_yaml_file}"
  adapt_file $lf_in_source_directory $lf_in_target_directory $lf_in_yaml_file

  mylog check "Creating or Updating ${lf_in_cr_name}/${lf_in_type}"
  lf_apply_cmd="oc apply -f $lf_target_yaml_file"
  lf_delete_cmd="oc delete -f $lf_target_yaml_file"
  append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
  prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file

  if $MY_APPLY_FLAG; then 
    oc apply -f $lf_target_yaml_file || exit 1
  fi

  trace_out 3 check_create_oc_yaml
}

################################################
# 
# @param 1: namespace
function provision_persistence_openldap() {
  trace_in 3 provision_persistence_openldap

  local lf_in_namespace="$1"

  # handle persitence for Openldap
  # only check one, assume that if one is created the other one is also created (short cut to optimize time)
  mylog check "Checking persistent volume claim for LDAP in ${lf_in_namespace}"

  export MY_PROJECT=$lf_in_namespace

  adapt_file "${MY_YAMLDIR}ldap/" $MY_LDAP_WORKINGDIR "ldap-pvc.main.yaml"
  oc apply -f "${MY_LDAP_WORKINGDIR}ldap-pvc.main.yaml" || exit 1
  wait_for_state "pvc pvc-ldap-main status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-main -o jsonpath='{.status.phase}'"

  adapt_file "${MY_YAMLDIR}ldap/" $MY_LDAP_WORKINGDIR "ldap-pvc.config.yaml"
  unset MY_PROJECT
  oc apply -f "${MY_LDAP_WORKINGDIR}ldap-pvc.config.yaml" || exit 1
  wait_for_state "pvc pvc-ldap-config status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-config -o jsonpath='{.status.phase}'"

  trace_out 3 provision_persistence_openldap
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "openldap"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
function deploy_openldap() {
  trace_in 3 deploy_openldap

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
      adapt_file "${MY_YAMLDIR}ldap/" "${MY_WORKINGDIR}" "ldap-config.json" 
      oc -n ${lf_in_namespace} patch deployment.apps/openldap --patch-file ${MY_WORKINGDIR}ldap-config.json
    fi
  fi

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
      local lf_apply_cmd="oc -n ${lf_in_namespace} new-app ${lf_in_name}/${lf_in_name}"
      local lf_delete_cmd="oc -n ${lf_in_namespace} delete -f ${lf_in_name}/${lf_in_name}"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc -n ${lf_in_namespace} new-app ${lf_in_name}/${lf_in_name}
    fi
  fi
  trace_out 3 deploy_mailhog
}

################################################
# Check if the service is already exposed
# @param 1:
# @param 2:
# @param 3:
function is_service_exposed() {
  trace_in 3 is_service_exposed

  local lf_in_namespace="$1"
  local lf_in_service_name="$2"
  local lf_in_port="$3"

  local lf_port_name lf_res

  lf_port_name=$(oc -n "${lf_in_namespace}" get service "${lf_in_service_name}" -o json | jq --argjson port "$lf_in_port" '.spec.ports[] | select(.nodePort == $port) |.name')
  decho 3 "lf_port_name=$lf_port_name"

  # This fuction needed to be re-written. The oc expose function creates a route.
  
  if [ -z "$lf_port_name" ]; then
    lf_res=1
  else
    lf_res=0
  fi
  trace_out 3 is_service_exposed
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
  trace_in 3 add_ldap_entry_if_not_exists

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
      echo "$lf_in_entry_content" > $lf_in_tmp_ldif_file
      ldapadd -x -H $lf_in_ldap_server -D "$lf_in_admin_dn" -w $lf_in_admin_password -f $lf_in_tmp_ldif_file
    fi
  fi

  trace_out 3 add_ldap_entry_if_not_exists
}

#========================================================
# add ldif file entries if each doesn't exist
# @param 1:
# @param 2:
# @param 3:
# @param 4:
function add_ldif_file () {
  trace_in 3 add_ldif_file

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

  trace_out 3 add_ldif_file
}

################################################
# @param 1: name: name of the resource, example: "openldap"
# @param 2: namespace: the namespace to use
function expose_service_openldap() {
  trace_in 3 expose_service_openldap

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

  mylog info "Expose service ${lf_in_name} using port ${lf_port0} to the route openldap-external-http."
  oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external-http --port=${lf_port0}

  # mylog info "Expose service ${lf_in_name} using port ${lf_port1} to the route openldap-external-https."
  # oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external-https --port=${lf_port1}

  # is_service_exposed "${lf_in_namespace}" "${lf_in_name}" "${lf_port0}"
  # if [ $? -eq 0 ]; then
  #   mylog info "Service ${lf_in_name} using port ${lf_port0} is already exposed."
  # else
  #   mylog info "Service ${lf_in_name} using port ${lf_port0} is not exposed."
  #   oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port0}
  # fi
# 
  # is_service_exposed "${lf_in_namespace}" "${lf_in_name}" "${lf_port1}"
  # if [ $? -eq 0 ]; then
  #   mylog info "Service ${lf_in_name} using port ${lf_port1} is already exposed."
  # else
  #   mylog info "Service ${lf_in_name} using port ${lf_port1} is not exposed."
  #   oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port1}
  # fi

  lf_hostname=$(oc -n ${lf_in_namespace} get route openldap-external-http -o jsonpath='{.spec.host}')

  # load users and groups into LDAP
  adapt_file "${MY_YAMLDIR}ldap/" "${MY_WORKINGDIR}" "ldap-users.ldif"
  mylog info "Adding LDAP entries with following command: "
  mylog info "$MY_LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${MY_WORKINGDIR}ldap-users.ldif"
  # add_ldif_file ${MY_WORKINGDIR}ldap-users.ldif "ldap://${lf_hostname}:${lf_port0}" "${ldap_admin_dn}" "${ldap_admin_password}"
  $MY_LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -c -f ${MY_WORKINGDIR}ldap-users.ldif

  mylog info "You can search entries with the following command: "
  mylog info "ldapsearch -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""

  trace_out 3 expose_service_openldap
}

################################################
# @param 1: name: name of the resource, example: "mailhog"
# @param 2: namespace: the namespace to use
function expose_service_mailhog() {
  trace_in 3 expose_service_mailhog

  local lf_in_name="$1"
  local lf_in_namespace="$2"
  local lf_in_port="$3"

  # expose service externaly and get host and port
  # Check if the service is already exposed
  if oc -n ${lf_in_namespace} get route ${lf_in_name} >/dev/null 2>&1; then
    mylog info "Service ${lf_in_name} is already exposed."
  else
    mylog info "Service ${lf_in_name} is not exposed."
    local lf_apply_cmd="oc -n ${lf_in_namespace} expose svc/${lf_in_name} --port=${lf_in_port} --name=${lf_in_name}"
    local lf_delete_cmd="oc -n ${lf_in_namespace} delete route ${lf_in_name}"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc -n ${lf_in_namespace} expose svc/${lf_in_name} --port=${lf_in_port} --name=${lf_in_name}
  fi
  lf_hostname=$(oc -n ${lf_in_namespace} get route ${lf_in_name} -o jsonpath='{.spec.host}')
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
  local lf_in_workingdir="$4"
  
  export MY_PROJECT=$lf_in_name
  export MY_PROJECT_DISPLAYNAME=$lf_in_display_name
  export MY_PROJECT_DESCRIPTION=$lf_in_description

  var_fail lf_in_name "Please define project name in config"
  mylog check "Checking project $lf_in_name"
  if oc get project $lf_in_name >/dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $lf_in_name"
    adapt_file ${MY_RESOURCESDIR} ${lf_in_workingdir} project.yaml
    local lf_apply_cmd="oc apply -f ${lf_in_workingdir}project.yaml"
    local lf_delete_cmd="oc delete -f ${lf_in_workingdir}project.yaml"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    if $MY_APPLY_FLAG; then
      oc apply -f "${lf_in_workingdir}project.yaml"
      if [ $? -ne 0 ]; then 
        unset MY_PROJECT MY_PROJECT_DISPLAYNAME MY_PROJECT_DESCRIPTION
        trace_out 3 create_project
       exit 1
      fi
    fi    
  fi

  unset MY_PROJECT MY_PROJECT_DISPLAYNAME MY_PROJECT_DESCRIPTION
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
  local lf_in_resource_name=$2
  local lf_in_namespace=$3

  local lf_resource=""
  seconds=0
  while [ -z "$lf_resource" ]; do
    echo -ne "Timer: $seconds seconds | waiting for $lf_in_resource_name/$lf_in_type in project $lf_in_namespace...\033[0K\r"
    sleep 1
    #lf_resource=$(oc -n $lf_in_namespace get $lf_in_type -o json | jq -r --arg my_resource "$lf_in_resource_name" '.items[].metadata | select (.name | contains ($my_resource)).name')
    lf_resource=$(oc -n $lf_in_namespace get $lf_in_type -o json | jq -r --arg my_resource "$lf_in_resource_name" '.items[].metadata | select (.name == $my_resource).name')
    seconds=$((seconds + 1))
  done
  echo 
  export MY_RESOURCE=$lf_resource

  trace_out 3 wait_for_resource
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
# @param 1:
# @param 2:
# @param 3: This is the version of the channel. It is an optional parameter, if ommited it is retrieved, else used values from invocation
function check_add_cs_ibm_pak() {
  trace_in 3 check_add_cs_ibm_pak

  local lf_in_case_name="$1"
  local lf_in_arch="$2"
  local lf_in_case_version="$3"
  decho 3 "lf_in_case_name=$lf_in_case_name|lf_in_arch=$lf_in_arch|lf_in_case_version=$lf_in_case_version"

  local lf_case_version lf_app_version lf_type lf_file lf_file_tmp1 lf_file_tmp2 lf_downloaded lf_display_name

  #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
  if [ -z "$lf_in_case_version" ]; then
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

  if [ $lf_downloaded -eq 1 ]; then
    mylog info "case ${lf_in_case_name} ${lf_case_version} already downloaded"
  else
    local lf_apply_cmd="oc ibm-pak get ${lf_in_case_name} --version ${lf_case_version}"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    oc ibm-pak get ${lf_in_case_name} --version ${lf_case_version}

    local lf_appy_cmd="oc ibm-pak generate mirror-manifests ${lf_in_case_name} icr.io --version ${lf_case_version}"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    oc ibm-pak generate mirror-manifests ${lf_in_case_name} icr.io --version ${lf_case_version}
  fi

  lf_file_tmp1=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources.yaml
  lf_file_tmp2=${MY_IBMPAK_MIRRORDIR}${lf_in_case_name}/${lf_case_version}/catalog-sources-linux-${lf_in_arch}.yaml

  if [ -e "$lf_file_tmp1" ]; then
    lf_file=$lf_file_tmp1
    lf_display_name="${lf_in_case_name}-${lf_case_version}"
  elif [ -e "$lf_file_tmp2" ]; then
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
  local lf_apply_cmd="oc apply -f $lf_file"
  local lf_delete_cmd="oc delete -f $lf_file"
  append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
  prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
  if $MY_APPLY_FLAG; then 
    oc apply -f $lf_file || exit 1
  fi

  trace_out 3 check_add_cs_ibm_pak
}

################################################
##SB]20231201 create operator subscription
# @param 1: operator name 
# @param 2: namespace where the subscription is created (openshift-operators or others)
# @param 3: Operator channel
# @param 4: Control of the upgrade in the subscription, automatic or manual
# @param 5: name of the source catalog
# @param 6: csv Operator channel
# @param 7: working directory

function create_operator_subscription() {
  trace_in 3 create_operator_subscription

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  export MY_OPERATOR_NAME=$1
  export MY_OPERATOR_NAMESPACE=$2
  export MY_OPERATOR_CHL=$3
  export MY_STRATEGY=$4
  export MY_CATALOG_SOURCE_NAME=$5
  local lf_in_csv_name=$6
  local lf_in_workingdir=$7

  local lf_file lf_path lf_resource lf_state lf_type
  check_directory_exist ${MY_OPERATORSDIR}

  #SECONDS=0

  local lf_type="Subscription"
  local lf_cr_name="${MY_OPERATOR_NAME}"
  local lf_source_directory="${MY_OPERATORSDIR}"
  local lf_target_directory="${lf_in_workingdir}"
  local lf_yaml_file="subscription.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  lf_type="clusterserviceversion"
  decho 3 "wait_for_resource $lf_type $lf_in_csv_name $MY_OPERATOR_NAMESPACE"
  wait_for_resource $lf_type $lf_in_csv_name $MY_OPERATOR_NAMESPACE
  lf_resource=$MY_RESOURCE
  unset MY_RESOURCE

  decho 3 "lf_resource=$lf_resource|lf_in_csv_name=$lf_in_csv_name"
  lf_type="clusterserviceversion"
  lf_path="{.status.phase}"
  lf_state="Succeeded"
  wait_for_state "$lf_type $lf_resource $lf_path is $lf_state" "$lf_state" "oc -n $MY_OPERATOR_NAMESPACE get $lf_type $lf_resource -o jsonpath='$lf_path'"

  unset MY_OPERATOR_NAME MY_OPERATOR_NAMESPACE MY_OPERATOR_CHL MY_STRATEGY MY_CATALOG_SOURCE_NAME

  trace_out 3 create_operator_subscription
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
  if [ $lf_nfiles -gt 0 ]; then
    for lf_file in ${lf_scripts_customdir}*; do
      if [ -f $lf_file ]; then
        lf_filename=$(basename -- "$lf_file")
        adapt_file "$lf_scripts_customdir" "$lf_scripts_gendir" "$lf_filename"
        #  . "${lf_scripts_gendir}${filename}"
      fi
    done
  fi

  check_directory_contains_files $lf_config_customdir
  lf_nfiles=$?
  if [ $lf_nfiles -gt 0 ]; then
    for lf_file in ${lf_config_customdir}*; do
      if [ -f $lf_file ]; then
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

  local lf_in_sourcedir=$1
  local lf_in_destdir=$2
  local lf_in_filename=$3
  decho 5 "$lf_in_sourcedir | $lf_in_destdir | $lf_in_filename"

  if [ ! -d ${lf_in_destdir} ]; then
    mkdir -p ${lf_in_destdir}
  fi
  if [ -e "${lf_in_sourcedir}${lf_in_filename}" ]; then
    envsubst < "${lf_in_sourcedir}${lf_in_filename}" > "${lf_in_destdir}${lf_in_filename}"
  fi

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
  lf_type="Issuer"
  lf_cr_name=${lf_in_namespace}-${lf_in_issuername}-ca
  lf_source_directory="${MY_TLS_GEN_CUSTOMDIR}config/"
  lf_target_directory="${lf_in_workingdir}"
  lf_yaml_file="Issuer_ca.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  lf_type="Certificate"
  lf_cr_name=${lf_in_namespace}-${lf_issuer_cert_name}-ca
  lf_yaml_file="CACertificate.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  lf_type="Issuer"
  lf_cr_name=${lf_in_namespace}-${lf_in_issuername}-tls
  lf_yaml_file="Issuer_non_ca.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  lf_type="Certificate"
  lf_cr_name=${lf_in_namespace}-${lf_in_tls_certname}-tls
  lf_yaml_file="TLSCertificate.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"
  
  unset TLS_CA_ISSUER_NAME TLS_NAMESPACE TLS_ROOT_CERT_NAME TLS_LABEL1 TLS_INGRESS

  trace_out 3 create_certificate_chain
}

################################################
# Create openshift cluster using classic infrastructure
function create_openshift_cluster_classic() {
  trace_in 3 create_openshift_cluster_classic

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
      trace_out 3 create_openshift_cluster_classic
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
      trace_out 3 create_openshift_cluster_classic
      exit 1
    fi
    mylog info "Creation of the cluster took: $SECONDS seconds." 1>&2
  fi

  trace_out 3 create_openshift_cluster_classic
}

################################################
# Create openshift cluster using VPC infra
# use terraform because creation is more complex than classic
function create_openshift_cluster_vpc() {
  trace_in 3 create_openshift_cluster_vpc

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

  trace_out 3 create_openshift_cluster_vpc
}

################################################
# TBC
function create_openshift_cluster() {
  trace_in 3 create_openshift_cluster

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

  trace_out 3 create_openshift_cluster
}

################################################
# wait for Cluster availability
# set variable my_cluster_url
function wait_for_cluster_availability() {
  trace_in 3 wait_for_cluster_availability

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
    trace_out 3 wait_for_cluster_availability
    exit 1
    ;;
  esac

  trace_out 3 wait_for_cluster_availability
}

################################################
# wait for ingress address availability
function wait_4_ingress_address_availability() {
  trace_in 3 wait_4_ingress_address_availability

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

  trace_out 3 wait_4_ingress_address_availability
}

################################################
# SB]20231215
# SB]20231130 patcher les foundational services en acceptant la license
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm
# 3.Setting the hardware profile and accepting the license
# License: Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
# 20250110 : add two more parameters to the function, to use it also for License Service instance which needs also the same patching
function accept_license_fs() {
  trace_in 4 accept_license_fs

  local lf_in_namespace=$1
  local lf_in_octype=$2
  local lf_in_cr_name=$3

  decho 5 "oc -n ${lf_in_namespace} get ${lf_in_octype} ${lf_in_cr_name} -o jsonpath='{.spec.license.accept}'"
  local lf_accept=$(oc -n ${lf_in_namespace} get ${lf_in_octype} ${lf_in_cr_name} -o jsonpath='{.spec.license.accept}')
  decho 5 "accept=$accept"
  if [ "$lf_accept" == "true" ]; then
    mylog info "license already accepted." 1>&2
  else
    local lf_apply_cmd="oc -n ${lf_in_namespace} patch ${lf_in_octype} ${lf_in_cr_name} --type merge -p '{\"spec\": {\"license\": {\"accept\": true}}}'"
    local lf_delete_cmd="oc -n ${lf_in_namespace} patch ${lf_in_octype} ${lf_in_cr_name} --type merge -p '{\"spec\": {\"license\": {\"accept\": false}}}'"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc -n ${lf_in_namespace} patch ${lf_in_octype} ${lf_in_cr_name} --type merge -p '{"spec": {"license": {"accept": true}}}'
  fi

  trace_out 4 accept_license_fs
}

################################################
function generate_password() {
  trace_in 5 generate_password

  local lf_in_length=$1

  local lf_pattern='A-Za-z0-9!@#$%^&*()_+'

  # Generate a password based on the pattern
  local lf_password=$(cat /dev/urandom | tr -dc "$lf_pattern" | head -c "$lf_in_length")
  export USER_PASSWORD_GEN=$lf_password

  trace_out 5 generate_password
}
