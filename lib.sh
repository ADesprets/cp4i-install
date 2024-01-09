#########################################################################
# check if openshift version available 
# check_openshift_version v1 returns 0 if v1 does not exist 1 if v1 exist
function check_openshift_version() {
  local lf_in_version=$1

  IFS='.' read -ra v_components <<< "$lf_in_version"
  vmaj=${v_components[0]}
  vmin=${v_components[1]}
  #echo "vmaj=$vmaj|vmin=$vmin"
  res=$(ibmcloud ks versions -q --show-version Openshift --output json| jq --argjson vmaj "$vmaj" --argjson vmin "$vmin" '.openshift[] | select (.major == $vmaj and .minor == $vmin)')
  echo $res
  #if [ -z "$res" ]; then
  #  return 0
  #else return 1
  #fi
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
    version1=$1
    version2=$2

    IFS='.' read -ra v1_components <<< "$version1"
    IFS='.' read -ra v2_components <<< "$version2"
	
    len=${#v1_components[@]}


    for ((i=0; i<$len; i++)); do
        v1=${v1_components[i]:-0}
        v2=${v2_components[i]:-0}

        if [ "$v1" -lt "$v2" ]; then
            #echo "$version1 is older than $version2"
            return 2
        elif [ "$v1" -gt "$v2" ]; then
            #echo "$version1 is newer than $version2"
            return 1
        fi
    done

    #echo "$version1 is equal to $version2"
    return 0
}

################################################
# Check that the CASE is already downloaded
# example pour filtrer avec conditions : 
# avec jsonpath=$.[?(@.name=='ibm-licensing' && @.version=='4.2.1')]
# Pour tester une variable null : https://stackoverflow.com/questions/48261038/shell-script-how-to-check-if-variable-is-null-or-no
function is_case_downloaded() {
  local case=$1
  local version_varid=$2

  local directory res result latestversion cmp

  local version=${!version_varid}
  
  directory="${IBMPAKDIR}${case}/${version}"

  if [ ! -d "${directory}" ]; then
    return 0
  else
    result=$(oc ibm-pak list --downloaded -o json)
  
    # One of the simplest ways to check if a string is empty or null is to use the -z and -n operators. 
    # The -z operator returns true if the string is null or empty, and false otherwise. 
    # The -n operator returns true if the string is not null or empty, and false otherwise.
	  if [ -z "$result" ]; then
	  	return 0
    else
      # Pb avec le passage de variables à jsonpath ; décision retour vers jq
      # result=$(echo $result | jsonpath '$.[?(@.name == "${case}" && @.latestVersion == "${version}")]')
      #res=$(echo $result | jq -r --arg case "$case" --arg version "$version" '.[] | select (.name == $case and .latestVersion == $version)')
      result=$(echo $result | jq -r --arg case "$case"  '[.[] | select (.name == $case )]')
     	if [ -z "$result" ]; then
	  	  return 0
      else 
        latestversion=$(echo $result | jq -r max_by'(.latesVersion)|.latestVersion')
        #echo "latestversion=$latestversion|version=$version"
        
        # cmpversions v1 v2 returns 0 if v1=v2, 1 if v1 is newer than v2, 2 if v1 is older than v2
        cmp_versions $latestversion $version
        cmp=$?
        case $cmp in
          0) return 1 ;;
          1) sed -i "/$version_varid/c$version_varid=$latestversion" "$my_versions_file" 
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
  local type=$1
  local cr=$2
  local file=$3
  local ns=$4

  local path="{.metadata.creationTimestamp}"
  local cr_ts
  local file_ts

  cr_ts=$(oc get $type $cr -n $ns -o jsonpath='$path'| date -d - +%s)
  file_ts=$(stat -c %Y $file)

  if [ $cr_ts -gt $file_ts ]; then
    echo 1
  else
    echo 0
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
  #if [ ${#files[@]} -eq 0 ]; then
  #  mylog error "No files in directory: $directory" 1>&2
	#  exit 1
  #fi
}

################################################
function read_config_file() {
	if test -n "$PC_CONFIG";then
	  config_file="$PC_CONFIG"
	else
	  config_file="$1"
	fi
	if test -z "$config_file";then
		mylog error "Usage: $0 <config file>" 1>&2
		mylog info "Example: $0 ${MAINSCRIPTDIR}cp4i.conf"
		exit 1
	fi

	check_file_exist $config_file

	# load user specific variables, "set -a" so that variables are part of environment for envsubst
	set -a
	. "${config_file}"
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
	p=
	w=
	s=
	case $1 in
	  info) c=2;; #green
	  error) c=1;p='ERROR: ';; #red
	  warn) c=3;;#yellow
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
  check_command_exist docker
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
# wait for Cluster availability
# set variable my_cluster_url
function wait_for_cluster_availability () {
  SECONDS=0	
  wait_for_state 'Cluster state' 'normal-All Workers Normal' "ibmcloud oc cluster get --cluster $my_cluster_name --output json|jq -r '.state+\"-\"+.status'"
  mylog info "Checking Cluster state took: $SECONDS seconds." 1>&2

  SECONDS=0
  mylog check "Checking Cluster URL"
  my_cluster_url=$(ibmcloud ks cluster get --cluster $my_cluster_name --output json | jq -r "$gbl_cluster_url_filter")
  case "$my_cluster_url" in
	https://*)
	mylog ok " -> $my_cluster_url"
    mylog info "Checking Cluster availability took: $SECONDS seconds." 1>&2
	;;
	*)
	mylog error "Error getting cluster URL for $my_cluster_name" 1>&2
	exit 1
	;;
  esac
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

	if oc get ${lf_in_octype} ${lf_in_cr_name} -n ${lf_in_ns} > /dev/null 2>&1; then
    newer=$(is_cr_newer $lf_in_octype $lf_in_cr_name $lf_in_yaml_file $lf_in_ns)
    if [ $newer ]; then 
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
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "openldap"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
function check_create_oc_openldap() {
	read_config_file "${YAMLDIR}ldap/ldap.properties"
	local octype="$1"
	local name="$2"
	local ns="$3"

	# create namespace if needed
	create_namespace ${ns}

	#SB]20231207 checks if used directories and files exists
	check_directory_exist ${YAMLDIR}
	check_directory_exist ${WORKINGDIR}
	check_file_exist ${YAMLDIR}ldap/ldap-pvc.main.yaml
	check_file_exist ${YAMLDIR}ldap/ldap-pvc.config.yaml
	check_file_exist ${YAMLDIR}ldap/ldap-config.json
	check_file_exist ${YAMLDIR}ldap/ldap-users.ldif

	# check if deploment already performed
	mylog check "Checking ${octype} ${name} in ${ns}"
	if oc get ${octype} ${name} -n ${ns} > /dev/null 2>&1; then mylog ok;else
		mylog info "Creating LDAP server"
		oc adm policy add-scc-to-group anyuid system:serviceaccounts:${ns}
		
		# handle persitence for Openldap
		# only check one, assume that if one is created the other one is also created (short cut to optimize time)
		if oc get "PersistentVolumeClaim" "pvc-ldap-main" -n ${ns} > /dev/null 2>&1; then mylog ok;else
			envsubst < "${YAMLDIR}ldap/ldap-pvc.main.yaml" > "${WORKINGDIR}ldap-pvc.main.yaml"
			envsubst < "${YAMLDIR}ldap/ldap-pvc.config.yaml" > "${WORKINGDIR}ldap-pvc.config.yaml"
			oc create -f ${WORKINGDIR}ldap-pvc.main.yaml -n ${ns}
			oc create -f ${WORKINGDIR}ldap-pvc.config.yaml -n ${ns}
			wait_for_state "pvc pvc-ldap-config status.phase is Bound" "Bound" "oc get pvc pvc-ldap-config -n ${ns} -o jsonpath='{.status.phase}'"
			wait_for_state "pvc pvc-ldap-main status.phase is Bound" "Bound" "oc get pvc pvc-ldap-main -n ${ns} -o jsonpath='{.status.phase}'"
		fi

		# deploy openldap and take in account the PVCs just created
		# check that deployment of openldap was not done
		if oc get "deployment" "openldap" -n ${ns} > /dev/null 2>&1; then mylog ok;else
			oc -n ${ns} new-app osixia/${name}
			oc -n ${ns} get deployment.apps/openldap -o json | jq '. | del(."status")' > ${WORKINGDIR}openldap.json
			envsubst < "${YAMLDIR}ldap/ldap-config.json" > "${WORKINGDIR}ldap-config.json"
			oc -n ${ns} patch deployment.apps/openldap --patch-file ${WORKINGDIR}ldap-config.json

			# expose service externaly and get host and port
			oc -n ${ns} patch service openldap -p='{"spec": {"type": "NodePort"}}'
			oc -n ${ns} get service openldap -o json | jq '.spec.ports |= map(if .name == "389-tcp" then . + { "nodePort": 30389 } else . end)' | jq '.spec.ports |= map(if .name == "636-tcp" then . + { "nodePort": 30686 } else . end)' > ${WORKINGDIR}openldap-service.json
			oc -n ${ns} patch service/openldap --patch-file ${WORKINGDIR}openldap-service.json
			oc -n ${ns} expose service openldap --name=openldap-external --target-port=389

			port=`oc -n ${ns} get service ${name} -o jsonpath='{.spec.ports[0].nodePort}'`
			hostname=`oc -n ${ns} get route openldap-external -o jsonpath='{.spec.host}'`

			# load users and groups into LDAP
			envsubst < "${YAMLDIR}ldap/ldap-users.ldif" > "${WORKINGDIR}ldap-users.ldif"
			mylog info "Adding LDAP entries with following command: "
			mylog info "ldapadd -H ldap://${hostname}:${port} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${WORKINGDIR}ldap-users.ldif"
			ldapadd -H ldap://${hostname}:${port} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -f ${WORKINGDIR}ldap-users.ldif

			mylog info "You can search entries with the following command: "
			# ldapmodify -H ldap://$hostname:$port -D "$ldap_admin_dn" -w admin -f ${LDAPDIR}Import.ldiff
			mylog info "ldapsearch -H ldap://${hostname}:${port} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""
		fi
	fi
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
  local lf_type="$1"
  local lf_name="$2"
  local lf_namespace="$3"
  
  var=$(oc get -n $lf_namespace $lf_type $lf_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
  while test -z $var;  do
    var=$(oc get -n $lf_namespace $lf_type $lf_name --ignore-not-found=true -o jsonpath='{.metadata.name}')
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
  #echo "$lf_in_case_name|$lf_case_version|downloaded=$downloaded"
  
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
  export MY_STARTING_CSV=$6 # Optional

  local file installedcsv path resource state type
  check_directory_exist ${OPERATORSDIR}

  SECONDS=0
  
  file="${OPERATORSDIR}subscription.yaml"
  type="subscription"
  check_create_oc_yaml "${type}" "${MY_OPERATOR_NAME}" "${file}" "${MY_OPERATOR_NAMESPACE}"

  #echo "oc get subscription \"${MY_OPERATOR_NAME}\" -n ${MY_OPERATOR_NAMESPACE} -o jsonpath='{.status.installedCSV}'"
  if [ ! -z $MY_STARTING_CSV ]; then
    echo "startingcsv provided"
    type="subscription"
    path="{.status.installedCSV}"
    state="$MY_STARTING_CSV"
    resource=$(check_resource_availability "subscription" $MY_OPERATOR_NAME $MY_OPERATOR_NAMESPACE)
    echo "wait_for_state $type $resource $path is $state | $state | oc get $type $resource -n $MY_OPERATOR_NAMESPACE -o jsonpath=$path"
    wait_for_state "$type $resource $path is $state" "$state" "oc get $type $resource -n $MY_OPERATOR_NAMESPACE -o jsonpath='$path'"
  
    #echo "resource=$resource"
    #installed=$(oc get subscription "${MY_OPERATOR_NAME}" -n ${MY_OPERATOR_NAMESPACE} -o jsonpath='{.spec.name}')
    #echo "installed=$installed"
    #SB]20231013 the function check_resource_availability will "return" the resource
    #resource=$(check_resource_availability "clusterserviceversion" $installed $MY_OPERATOR_NAMESPACE)
    type="clusterserviceversion"
    path="{.status.phase}"
    state="Succeeded"
    startingcsv=$MY_STARTING_CSV
    echo "wait_for_state $type $startingcsv $path is $state | $state | oc get $type $startingcsv -n $MY_OPERATOR_NAMESPACE -o jsonpath=$path"
    wait_for_state "$type $startingcsv $path is $state" "$state" "oc get $type $startingcsv -n $MY_OPERATOR_NAMESPACE -o jsonpath='$path'"
  else
    #SB]20231013 the function check_resource_availability will "return" the resource 
    echo "startingcsv not provided"
    echo "check_resource_availability clusterserviceversion $MY_OPERATOR_NAME $MY_OPERATOR_NAMESPACE"
    resource=$(check_resource_availability "subscription" $MY_OPERATOR_NAME $MY_OPERATOR_NAMESPACE)
    #resource=$(check_resource_availability "clusterserviceversion" "${MY_OPERATOR_NAME}" $MY_OPERATOR_NAMESPACE)
    type="clusterserviceversion"
    path="{.status.phase}"
    state="Succeeded"
    wait_for_state "$type $resource $path is $state" "$state" "oc get $type $resource -n $MY_OPERATOR_NAMESPACE -o jsonpath='$path'"
  fi
  mylog info "Creation of $MY_OPERATOR_NAME operator took $SECONDS seconds to execute." 1>&2
}


#########################################################
##SB]20231205 create flink and event processing operators 
function create_ea_operators() {
  local inventory=$1
  local name=$2
  local ns=$3
  local path=$4
  local state=$5
  local type=$6
  local version=$7

  local case_name="${name}.v${version}"
  SECONDS=0

  mylog check "Checking ${type} ${case_name} in ${ns} project"
  if oc get ${type} ${case_name} -n ${ns} > /dev/null 2>&1; then mylog ok;else
    oc ibm-pak launch $name --version $version --inventory $inventory --action installOperator -n $ns
    resource=$(check_resource_availability "clusterserviceversion" "${case_name}" $ns)
    #echo "wait_for_state|$type $resource $path is $state|$state|oc get $type $resource -n $ns -o jsonpath=$path"
    wait_for_state "$type $resource $path is $state" "$state" "oc get $type $resource -n $ns -o jsonpath='$path'"
    mylog info "Creation of $case_name operator took $SECONDS seconds to execute." 1>&2
  fi
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

  SECONDS=0
  check_create_oc_yaml $lf_in_type $lf_in_resource $lf_in_file $lf_in_ns
  echo "wait_for_state | $lf_in_type $lf_in_resource $lf_in_path is $lf_in_state | $lf_in_state | oc get $lf_in_type $lf_in_resource -n $lf_in_ns -o jsonpath=$lf_in_path"
  wait_for_state "$lf_in_type $lf_in_resource $lf_in_path is $lf_in_state" "$lf_in_state" "oc get $lf_in_type $lf_in_resource -n $lf_in_ns -o jsonpath='$lf_in_path'"
  mylog info "Creation of $lf_in_type instance took $SECONDS seconds to execute." 1>&2
}

################################################
# Get useful information to start using the stack
# Need to check that the resource exist.
function get_navigator_access() {
	cp4i_url=$(oc get platformnavigator cp4i-navigator -n $MY_OC_PROJECT -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
	cp4i_uid=$(oc get secret ibm-iam-bindinfo-platform-auth-idp-credentials -n $MY_OC_PROJECT -o jsonpath={.data.admin_username} | base64 -d)
	cp4i_pwd=$(oc get secret ibm-iam-bindinfo-platform-auth-idp-credentials -n $MY_OC_PROJECT -o jsonpath={.data.admin_password} | base64 -d)
	mylog info "CP4I Platform UI URL: " $cp4i_url
	mylog info "CP4I admin user: " $cp4i_uid
	mylog info "CP4I admin password: " $cp4i_pwd
}

#########################################################################################################
##SB]20231109 Generate properties and yaml files
## input parameter the operand custom dir (and generated dir both with config and scripts subdirectories)
function generate_files () {
  local customdir=$1
  local gendir=$2
  local nfiles

  # generate the differents properties files
  # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
  # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
  # - generate first the *.properties files to be sourced then generate the *.yaml files

  config_customdir="${customdir}config/"
  scripts_customdir="${customdir}scripts/"
  config_gendir="${gendir}config/"
  scripts_gendir="${gendir}scripts/"

  #set -a
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
      cat  $file | envsubst >  "${config_gendir}${filename}"
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
    wait_for_state "$type $CATALOG_SOURCE_NAME $path is $state" "$state" "oc get ${type} ${CATALOG_SOURCE_NAME} -n ${CATALOG_SOURCE_NAMESPACE} -o jsonpath='$path'"
  else 
    newer=$(is_cr_newer $type $CATALOG_SOURCE_NAME $file $CATALOG_SOURCE_NAMESPACE)
    if [ $newer ]; then 
      mylog info "Custom Resource $CATALOG_SOURCE_NAME exists in ns $CATALOG_SOURCE_NAMESPACE and is newer than file $file"
    else
      envsubst < "${file}" | oc -n ${CATALOG_SOURCE_NAMESPACE} apply -f - || exit 1
      wait_for_state "$type $CATALOG_SOURCE_NAME $path is $state" "$state" "oc get ${type} ${CATALOG_SOURCE_NAME} -n ${CATALOG_SOURCE_NAMESPACE} -o jsonpath='$path'"
    fi
  fi
}

