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

  IFS='.' read -ra v_components <<< "$lf_in_version"
  vmaj=${v_components[0]}
  vmin=${v_components[1]}
  res=$(ibmcloud ks versions -q --show-version Openshift --output json| jq --argjson vmaj "$vmaj" --argjson vmin "$vmin" '.openshift[] | select (.major == $vmaj and .minor == $vmin)')
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
    lf_in_version1=$1
    lf_in_version2=$2

    IFS='.' read -ra v1_components <<< "$lf_in_version1"
    IFS='.' read -ra v2_components <<< "$lf_in_version2"
	
    len=${#v1_components[@]}


    for ((i=0; i<$len; i++)); do
        v1=${v1_components[i]:-0}
        v2=${v2_components[i]:-0}

        if [ "$v1" -lt "$v2" ]; then
            #echo "$lf_in_version1 is older than $lf_in_version2"
            return 2
        elif [ "$v1" -gt "$v2" ]; then
            #echo "$lf_in_version1 is newer than $lf_in_version2"
            return 1
        fi
    done

    #echo "$lf_in_version1 is equal to $lf_in_version2"
    return 0
}

################################################
# Save a certificate in pem format
function save_certificate() {
  local lf_in_ns=$1
  local lf_in_secret_name=$2
  local lf_in_destination_path=$3

  mylog info "Save certificate ${lf_in_secret_name} to ${lf_in_destination_path}${lf_in_secret_name}.pem"
  cert=$(oc -n cp4i get secret ${lf_in_secret_name} -o jsonpath='{.data.ca\.crt}')
  echo $cert | base64 --decode > "${lf_in_destination_path}${lf_in_secret_name}.pem"
}


################################################
# Check that the CASE is already downloaded
# example pour filtrer avec conditions : 
# avec jsonpath=$.[?(@.name=='ibm-licensing' && @.version=='4.2.1')]
# Pour tester une variable null : https://stackoverflow.com/questions/48261038/shell-script-how-to-check-if-variable-is-null-or-no
function is_case_downloaded() {
  local lf_in_case=$1
  local lf_in_version_varid=$2

  local lf_directory lf_result lf_latestversion lf_cmp

  local lf_version=${!lf_in_version_varid}
  
  lf_directory="${IBMPAKDIR}${lf_in_case}/${lf_version}"

  if [ ! -d "${lf_directory}" ]; then
    return 0
  else
    lf_result=$(oc ibm-pak list --downloaded -o json)
  
    # One of the simplest ways to check if a string is empty or null is to use the -z and -n operators. 
    # The -z operator returns true if the string is null or empty, and false otherwise. 
    # The -n operator returns true if the string is not null or empty, and false otherwise.
	  if [ -z "$lf_result" ]; then
	  	return 0
    else
      # Pb avec le passage de variables à jsonpath ; décision retour vers jq
      # lf_result=$(echo $lf_result | jsonpath '$.[?(@.name == "${lf_in_case}" && @.latestVersion == "${lf_version}")]')
      # lf_result=$(echo $lf_result | jq -r --arg case "$lf_in_case" --arg version "$lf_version" '.[] | select (.name == $case and .latestVersion == $version)')
      lf_result=$(echo $lf_result | jq -r --arg case "$lf_in_case"  '[.[] | select (.name == $case )]')
     	if [ -z "$lf_result" ]; then
	  	  return 0
      else 
        lf_latestversion=$(echo $lf_result | jq -r max_by'(.latesVersion)|.latestVersion')
        
        cmp_versions $lf_latestversion $lf_version
        lf_cmp=$?
        case $lf_cmp in
          0) return 1 ;;
          1) mylog info "newer version of case $lf_in_case is available. Current version=$lf_version. Latest version=$lf_latestversion"
             # sed -i "/$lf_in_version_varid/c$lf_in_version_varid=$lf_latestversion" "$sc_versions_file" 
             return 1 ;;
        esac
      fi
    fi  
  fi
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
  local lf_in_type=$1
  local lf_in_customresource=$2
  local lf_in_file=$3
  local lf_in_namespace=$4

  local lf_customresource_timestamp
  local lf_file_timestamp
  local lf_path="{.metadata.creationTimestamp}"

  #oc -n $lf_in_namespace get $lf_in_type $lf_in_customresource -o jsonpath='$lf_path'| date -d - +%s
  lf_customresource_timestamp=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_customresource -o json | jq -r  '.metadata.creationTimestamp')
  lf_customresource_timestamp=$(echo "$lf_customresource_timestamp" | date -d - +%s )
  lf_file_timestamp=$(stat -c %Y $lf_in_file)

  if [ $lf_customresource_timestamp -gt $lf_file_timestamp ]; then
    return 1
  else
    return 0
  fi
}

################################################
# Check that all required executables are installed
function check_command_exist() {
  local command=$1

  if ! command -v $command >/dev/null 2>&1; then
		mylog error "Executable $command does not exist or is not executable, exiting."
		exit 1
  fi
}

######################################################
# checks if the file exist, if no print a msg and exit
#
function check_file_exist () {
	local file=$1
	if [ ! -e "$file" ];then
		mylog error "No such file: $file" 1>&2
		exit 1
	fi
}

######################################################
# checks if the directory exist, if no print a msg and exit
#
function check_directory_exist () {
  local directory=$1
  if [ ! -d $directory ]; then
    mylog error "No such directory: $directory" 1>&2
	  exit 1
  fi
}

######################################################
# checks if the directory contains files, if no print a msg and exit
#
function check_directory_contains_files () {
  local directory=$1
  shopt -s nullglob dotglob     # To include hidden files
  files=($directory/*)
  echo ${#files[@]}
}

################################################
function read_config_file() {
  local lf_config_file
	if test -n "$PC_CONFIG";then
	  lf_config_file="$PC_CONFIG"
	else
	  lf_config_file="$1"
	fi
	if test -z "$lf_config_file";then
		mylog error "Usage: $0 <config file>" 1>&2
		mylog info "Example: $0 ${MAINSCRIPTDIR}cp4i.conf"
		exit 1
	fi

	check_file_exist $lf_config_file

	# load user specific variables, "set -a" so that variables are part of environment for envsubst
	set -a
	. "${lf_config_file}"
	set +a
}

################################################
# assert that variable is defined
# @param 1 name of variable
# @param 2 error message, or name of method to call if begins with "fix"
function var_fail() {
	if eval test -z '$'$1;then
		mylog error "missing config variable: $1" 1>&2
		case "$2" in
			fix*|echo*) eval $2 ;;
			"") ;;
			*) mylog log "$2" 1>&2;;
		esac
		exit 1
	fi
}

################################################
# simple logging with colors
# @param 1 level (info/error/warn/wait/check/ok/no)
function mylog() {
  # prefix
	local p=
  # do not output the trailing newline
	local w=
  # suffix
	local s=
	case $1 in
	  info) c=2;; #green
	  error) c=1;p='ERROR: ';; #red
	  warn) c=3;;#yellow
	  debug) c=8;p='CMD: ';; #yellow
	  wait) c=4;p="$(date) ";; #blue
	  check) c=6;w=-n;s=...;; #cyan
	  ok) c=2;p=OK;; #green
	  no) c=3;p=NO;; #yellow
	  *) c=9;; #default
	esac
	shift
	echo $w "$(tput setaf $c)$p$@$s$(tput setaf 9)"
}

################################################
# Check that all required executables are installed
function check_exec_prereqs() {
  check_command_exist awk
  check_command_exist curl
  check_command_exist $MY_CONTAINER_ENGINE
  check_command_exist ibmcloud
  check_command_exist jq
  check_command_exist keytool
  check_command_exist oc
  check_command_exist openssl
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
  curl --url "smtp://$mail_def" \
    --mail-from cp4i-admin@ibm.com \
    --mail-rcpt cp4i-user@ibm.com \
    --upload-file ${MAINSCRIPTDIR}templates/emails/test-email.txt
}

################################################
# wait for command to return specified value
# @param what description of waited state
# @param value expected state value from check command
# @param command executed command that returns some state
function wait_for_state() {
	local what=$1
	local value=$2
	local command=$3
	mylog check "Checking $what"
	#mylog check "Checking $what status until reaches value $value with command $command"
	last_state=
	while true;do
		current_state=$(eval $command)
		if test "$current_state" = "$value";then
			mylog ok ", $current_state"
			break
		fi
		# first time
		if test -z "$last_state";then
			mylog no
		fi
		if test "$last_state" != "$current_state";then
			mylog wait "$current_state"
			last_state=$current_state
		fi
		sleep 5
	done
}

################################################
# Check if the resource of type octype with name name exists in the namespace ns.
# If it does not exist use the yaml file, with the appropriate variable.
# @param octype: kubernetes resource class, example: "subscription"
# @param name: name of the resource, example: "ibm-integration-platform-navigator"
# @param yaml: the file with the definition of the resource, example: "${subscriptionsdir}Navigator-Sub.yaml"
# @param ns: name space where the reousrce is created, example: $MY_OPERATORS_NAMESPACE
function check_create_oc_yaml() {
  local lf_in_octype="$1"
  local lf_in_cr_name="$2"
  local lf_in_yaml_file="$3"
  local lf_in_ns="$4"
	
  export MY_NAMESPACE="$4"

  local newer
  
	check_file_exist $lf_in_yaml_file
	mylog check "Checking ${lf_in_octype} ${lf_in_cr_name} in ${lf_in_ns} project"
  decho "oc -n ${lf_in_ns} get ${lf_in_octype} ${lf_in_cr_name}"

	if oc -n ${lf_in_ns} get ${lf_in_octype} ${lf_in_cr_name} > /dev/null 2>&1; then
    is_cr_newer $lf_in_octype $lf_in_cr_name $lf_in_yaml_file $lf_in_ns
    newer=$?
    if [ $newer -eq 1 ]; then 
      mylog ok
      mylog info "Custom Resource $lf_in_cr_name is newer than file $lf_in_yaml_file"
    else
      envsubst < "${lf_in_yaml_file}" | oc -n ${lf_in_ns} apply -f - || exit 1
    fi
  else
    envsubst < "${lf_in_yaml_file}" | oc -n ${lf_in_ns} apply -f - || exit 1
	fi
}

################################################
# @param namespace
function provision_persistence_openldap() {
  local lf_in_namespace="$1"
  # handle persitence for Openldap
  # only check one, assume that if one is created the other one is also created (short cut to optimize time)
  if oc -n ${lf_in_namespace} get "PersistentVolumeClaim" "pvc-ldap-main" > /dev/null 2>&1; then mylog ok;else
  	envsubst < "${YAMLDIR}ldap/ldap-pvc.main.yaml" > "${WORKINGDIR}ldap-pvc.main.yaml"
  	envsubst < "${YAMLDIR}ldap/ldap-pvc.config.yaml" > "${WORKINGDIR}ldap-pvc.config.yaml"
  	oc -n ${lf_in_namespace} create -f ${WORKINGDIR}ldap-pvc.main.yaml
  	oc -n ${lf_in_namespace} create -f ${WORKINGDIR}ldap-pvc.config.yaml
  	wait_for_state "pvc pvc-ldap-config status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-config -o jsonpath='{.status.phase}'"
  	wait_for_state "pvc pvc-ldap-main status.phase is Bound" "Bound" "oc -n ${lf_in_namespace} get pvc pvc-ldap-main -o jsonpath='{.status.phase}'"
  fi
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "openldap"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
function deploy_openldap(){
  local lf_in_octype="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"
  # check if deploment already performed
  mylog check "Checking ${lf_in_octype} ${lf_in_name} in ${lf_in_namespace}"
  if oc -n ${lf_in_namespace} get ${lf_in_octype} ${lf_in_name} > /dev/null 2>&1; then mylog ok
  else
    mylog check "Checking service ${lf_in_name} in ${lf_in_namespace}"
    if oc -n ${lf_in_namespace} get service ${lf_in_name} > /dev/null 2>&1; then mylog ok
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
	    oc -n ${lf_in_namespace} get deployment.apps/openldap -o json | jq '. | del(."status")' > ${WORKINGDIR}openldap.json
	    envsubst < "${YAMLDIR}ldap/ldap-config.json" > "${WORKINGDIR}ldap-config.json"
	    oc -n ${lf_in_namespace} patch deployment.apps/openldap --patch-file ${WORKINGDIR}ldap-config.json
	    oc -n ${lf_in_namespace} patch service ${lf_in_name} -p='{"spec": {"type": "NodePort"}}'
	    oc -n ${lf_in_namespace} patch service/${lf_in_name} --patch-file ${WORKINGDIR}openldap-service.json
    fi
  fi
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "mailhog"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
function deploy_mailhog(){
  local lf_in_octype="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"

  # check if deploment already performed
  mylog check "Checking ${lf_in_octype} ${lf_in_name} in ${lf_in_namespace}"
  if oc -n ${lf_in_namespace} get ${lf_in_octype} ${lf_in_name} > /dev/null 2>&1; then mylog ok
  else
    mylog check "Checking service ${lf_in_name} in ${lf_in_namespace}"
    if oc -n ${lf_in_namespace} get service ${lf_in_name} > /dev/null 2>&1; then mylog ok
    else
  	  mylog info "Creating mailhog server"
      oc -n ${lf_in_namespace} new-app ${lf_in_name}/${lf_in_name}
    fi
  fi
}

################################################
# @param name: name of the resource, example: "openldap"
# @param namespace: the namespace to use
function expose_service_openldap() {
  local lf_in_name="$1"
  local lf_in_namespace="$2"

  # expose service externaly and get host and port
  oc -n ${lf_in_namespace} get service ${lf_in_name} -o json | jq '.spec.ports |= map(if .name == "389-tcp" then . + { "nodePort": 30389 } else . end)' | jq '.spec.ports |= map(if .name == "636-tcp" then . + { "nodePort": 30686 } else . end)' > ${WORKINGDIR}openldap-service.json
  lf_port0=$(oc -n ${lf_in_namespace} get service ${lf_in_name} -o jsonpath='{.spec.ports[0].nodePort}')
  lf_port1=$(oc -n ${lf_in_namespace} get service ${lf_in_name}  -o jsonpath='{.spec.ports[1].nodePort}')
  oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port0}
  oc -n ${lf_in_namespace} expose service ${lf_in_name} --name=openldap-external --port=${lf_port1}
     
  lf_hostname=$(oc -n ${lf_in_namespace} get route openldap-external -o jsonpath='{.spec.host}')
     
  # load users and groups into LDAP
  envsubst < "${YAMLDIR}ldap/ldap-users.ldif" > "${WORKINGDIR}ldap-users.ldif"
  mylog info "Adding LDAP entries with following command: "
  mylog info "$LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${WORKINGDIR}ldap-users.ldif"
  $LDAP_COMMAND -H ldap://${lf_hostname}:${lf_port0} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -f ${WORKINGDIR}ldap-users.ldif
     
  mylog info "You can search entries with the following command: "
  # ldapmodify -H ldap://$lf_hostname:$lf_port0 -D "$ldap_admin_dn" -w admin -f ${LDAPDIR}Import.ldiff
  mylog info "ldapsearch -H ldap://${lf_hostname}:${lf_port0} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""
}
################################################
# @param name: name of the resource, example: "mailhog"
# @param namespace: the namespace to use
function expose_service_mailhog() {
  local lf_in_name="$1"
  local lf_in_namespace="$2"
  local lf_port="$3"

  # expose service externaly and get host and port
  oc -n ${lf_in_namespace} expose svc/${lf_in_name} --port=${lf_port} --name=${lf_in_name}
  lf_hostname=$(oc -n ${lf_in_namespace} get route ${lf_in_name} -o jsonpath='{.spec.host}')
  mylog info "MailHog accessible at ${lf_hostname}"
}

################################################
# Create namespace
# @param ns namespace to be created
function create_namespace () {
  local lf_in_ns=$1
  var_fail MY_OC_PROJECT "Please define project name in config"
  mylog check "Checking project $lf_in_ns"
  if oc get project $lf_in_ns > /dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $lf_in_ns"
    if ! oc new-project $lf_in_ns; then
      exit 1
    fi
  fi
}

################################################
# Check if the resource exists.
# @param octype: kubernetes resource class, example: "subscription"
# @param name: name of the resource, example: "ibm-integration-platform-navigator"
# @param ns: namespace/project to perform the search
# TODO The var variable is initialised for another function, this is not good
function check_resource_availability () {
  local lf_in_type="$1"
  local lf_in_name="$2"
  local lf_in_namespace="$3"
  
  decho "oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}'"
  var=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  while test -z $var;  do
    var=$(oc -n $lf_in_namespace get $lf_in_type $lf_in_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  done
  #SB]20231013 simulate a return value by echoing it
  echo $var
}

################################################
##SB]20230201 use ibm-pak oc plugin
# https://ibm.github.io/cloud-pak/
function check_add_cs_ibm_pak () {
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
  if [  -e "$file" ]; then
    oc apply -f $file
  fi
    
  file=~/.ibm-pak/data/mirror/${lf_in_case_name}/${lf_case_version}/catalog-sources-linux-${lf_in_arch}.yaml
  if [  -e "$file" ];then
    oc apply -f $file
  fi

  mylog info "Adding case $lf_in_case_name took $SECONDS seconds to execute." 1>&2
}

################################################
##SB]20231201 create operator subscription
function create_operator_subscription() {

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  export MY_OPERATOR_NAME=$1
  export MY_CURRENT_CHL=$2
  export MY_CATALOG_SOURCE_NAME=$3
  export MY_OPERATOR_NAMESPACE=$4
  export MY_STRATEGY=$5
  local lf_in_wait=$6
  export MY_STARTING_CSV=$7 # Optional

  local file installedcsv path resource state type
  check_directory_exist ${OPERATORSDIR}

  SECONDS=0
  
  file="${OPERATORSDIR}subscription.yaml"
  type="Subscription"
  check_create_oc_yaml "${type}" "${MY_OPERATOR_NAME}" "${file}" "${MY_OPERATOR_NAMESPACE}"

  if [ ! -z $MY_STARTING_CSV ]; then
    # type="Subscription"
    # path="{.status.installedCSV}"
    # state="$MY_STARTING_CSV"
    # decho "wait_for_state $type $resource $path is $state | $state | oc -n $MY_OPERATOR_NAMESPACE get $type $resource -o jsonpath=$path"
    # resource=$(check_resource_availability "${type}" "${MY_OPERATOR_NAME}" "${MY_OPERATOR_NAMESPACE}")
    # decho "wait_for_state $type $resource $path is $state | $state | oc -n $MY_OPERATOR_NAMESPACE get $type $resource -o jsonpath=$path"
    # if [ $lf_in_wait ]; then 
    #   wait_for_state "$type $resource $path is $state" "$state" "oc -n $MY_OPERATOR_NAMESPACE get $type $resource -o jsonpath='$path'"
    # fi

    type="ClusterServiceVersion"
    path="{.status.phase}"
    state="Succeeded"
    startingcsv=$MY_STARTING_CSV
    decho "wait_for_state $type $startingcsv $path is $state | $state | oc -n $MY_OPERATOR_NAMESPACE get $type $startingcsv -o jsonpath=$path"
    if [ $lf_in_wait ]; then 
      wait_for_state "$type $startingcsv $path is $state" "$state" "oc -n $MY_OPERATOR_NAMESPACE get $type $startingcsv -o jsonpath='$path'"
    fi
  else
    decho "check_resource_availability clusterserviceversion $MY_OPERATOR_NAME $MY_OPERATOR_NAMESPACE"
    resource=$(check_resource_availability "subscription" $MY_OPERATOR_NAME $MY_OPERATOR_NAMESPACE)
    type="clusterserviceversion"
    path="{.status.phase}"
    state="Succeeded"
    if [ $lf_in_wait ]; then 
      wait_for_state "$type $resource $path is $state" "$state" "oc -n $MY_OPERATOR_NAMESPACE get $type $resource -o jsonpath='$path'"
    fi
  fi
  mylog info "Creation of $MY_OPERATOR_NAME operator took $SECONDS seconds to execute." 1>&2
}

################################################
##SB]20231204 create operand instance
function create_operand_instance() {
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
}

################################################
# Get useful information to start using the stack
# Need to check that the resource exist.
function get_navigator_access() {
	cp4i_url=$(oc -n $MY_OC_PROJECT get platformnavigator cp4i-navigator -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
	# cp4i_uid=$(oc -n $MY_OC_PROJECT get secret ibm-iam-bindinfo-platform-auth-idp-credentials -o jsonpath={.data.admin_username} | base64 -d)
	mylog info "CP4I Platform UI URL: " $cp4i_url
	# mylog info "CP4I admin user: " $cp4i_uid
	# mylog info "CP4I admin password: " $cp4i_pwd
}

#########################################################################################################
##SB]20231109 Generate properties and yaml/json files
## input parameter the operand custom dir (and generated dir both with config and scripts subdirectories)
function generate_files () {
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
      cat  $file | envsubst >  "${scripts_gendir}${filename}"
    #  . "${scripts_gendir}${filename}"
    done
  fi

  # Continue *.yaml files
  nfiles=$(check_directory_contains_files $config_customdir)
  if [ $nfiles -gt 0 ]; then
    for file in ${config_customdir}*; do
      filename=$(basename -- "$file")
      if $transform;then
        # mylog info "Transform $file file"
        cat  $file | envsubst >  "${config_gendir}${filename}"
      else
        # mylog info "Copy $file file"
        cat  $file  >  "${config_gendir}${filename}"
      fi
    done
  fi
  #set +a
}

#############################################################################################################################
function create_catalogsource () {
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

  result=$(oc get $type -A -o json| jq -r  --arg name $CATALOG_SOURCE_NAME --arg namespace $CATALOG_SOURCE_NAMESPACE '.items[] | select (.metadata.name == $name and .metadata.namespace == $namespace)')
 	if [ -z "$result" ]; then
		mylog info "no catalogsource $CATALOG_SOURCE_NAME found in namespace $CATALOG_SOURCE_NAMESPACE"
    envsubst < "${file}" | oc -n ${CATALOG_SOURCE_NAMESPACE} apply -f - || exit 1
    wait_for_state "$type $CATALOG_SOURCE_NAME $path is $state" "$state" "oc -n ${CATALOG_SOURCE_NAMESPACE} get ${type} ${CATALOG_SOURCE_NAME} -o jsonpath='$path'"
  else 
    is_cr_newer $type $CATALOG_SOURCE_NAME $file $CATALOG_SOURCE_NAMESPACE
    if [ $? -eq 1 ]; then 
      mylog info "Custom Resource $CATALOG_SOURCE_NAME exists in ns $CATALOG_SOURCE_NAMESPACE and is newer than file $file"
    else
      envsubst < "${file}" | oc -n ${CATALOG_SOURCE_NAMESPACE} apply -f - || exit 1
      wait_for_state "$type $CATALOG_SOURCE_NAME $path is $state" "$state" "oc -n ${CATALOG_SOURCE_NAMESPACE} get ${type} ${CATALOG_SOURCE_NAME} -o jsonpath='$path'"
    fi
  fi
}

#########################################################################################################
## adapt file into working dir
## called generate_files before
function adapt_file () {
  local sourcedir=$1
  local destdir=$2
  local filename=$3
  
  if [ ! -d ${destdir} ]; then
    mkdir -p ${destdir}
  fi
  if [ -e "${sourcedir}$filename" ];then
    cat  "${sourcedir}$filename" | envsubst >  "${destdir}${filename}"
  fi
}

