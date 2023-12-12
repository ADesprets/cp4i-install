################################################
# Check that all required executables are installed
# function
check_command_exist() {
  local command=$1

  if ! command -v $command >/dev/null 2>&1; then
		mylog error "Executable $command does not exist or is not executable, exiting."
		exit 1
  fi
}

######################################################
# function
# checks if the file exist, if no print a msg and exit
#
check_file_exist () {
	local file=$1
	if test ! -e "$file";then
		mylog error "No such file: $file" 1>&2
		exit 1
	fi
}

######################################################
# function
# checks if the directory exist, if no print a msg and exit
#
check_directory_exist () {
  local directory=$1
  if [ ! -d $directory ]; then
    mylog error "No such directory: $directory" 1>&2
	exit 1
  fi
}

######################################################
# function
# checks if the directory contains files, if no print a msg and exit
#
check_directory_contains_files () {
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
# function
read_config_file() {
	if test -n "$PC_CONFIG";then
	  config_file="$PC_CONFIG"
	else
	  config_file="$1"
	fi
	if test -z "$config_file";then
		mylog error "Usage: $0 <config file>" 1>&2
		mylog info "Example: $0 ${mainscriptdir}cp4i.conf"
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
# function
var_fail() {
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
# function
mylog() {
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
# function
check_exec_prereqs() {
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
# function 
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
# function
send-email() {
  curl --url "smtp://$mail_def" \
    --mail-from cp4i-admin@ibm.com \
    --mail-rcpt cp4i-user@ibm.com \
    --upload-file ${mainscriptdir}templates/emails/test-email.txt
}

################################################
# Log in IBM Cloud
# function
Login2IBMCloud () {
  SECONDS=0
  
  if ibmcloud resource groups -q > /dev/null 2>&1;then
    mylog info "user already logged to IBM Cloud." 
  else
    mylog info "user not logged to IBM Cloud." 1>&2
    var_fail my_ic_apikey "Create and save API key JSON file from: https://cloud.ibm.com/iam/apikeys"
    mylog check "Login to IBM Cloud"
    if ! ibmcloud login -q --no-region --apikey $my_ic_apikey > /dev/null;then
      mylog error "Fail to login to IBM Cloud, check API key: $my_ic_apikey" 1>&2
      exit 1
    else mylog ok
    mylog info "Connecting to IBM Cloud took: $SECONDS seconds." 1>&2
    fi
  fi 
}

################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
# requires var my_cluster_url
# function
Login2OpenshiftCluster () {
  SECONDS=0

  if oc whoami > /dev/null 2>&1;then
    mylog info "user already logged to openshift cluster." 
  else
    mylog check "Login to cluster"
    # SB 20231208 The following command sets your command line context for the cluster and download the TLS certificates and permission files for the administrator.
    # more details here : https://cloud.ibm.com/docs/openshift?topic=openshift-access_cluster#access_public_se
    ibmcloud ks cluster config --cluster ${my_cluster_name} --admin
    while ! oc login -u apikey -p $my_ic_apikey --server=$my_cluster_url > /dev/null;do
      mylog error "$(date) Fail to login to Cluster, retry in a while (login using web to unblock)" 1>&2
      sleep 30
    done
    mylog ok
    mylog info "Logging to Cluster took: $SECONDS seconds." 1>&2
  fi
}

################################################
# wait for Cluster availability
# set variable my_cluster_url
# function
wait_for_cluster_availability () {
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
# function
wait_for_state() {
	local what=$1
	local value=$2
	local command=$3
	mylog check "Checking $what"
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
# @param ns: name space where the reousrce is created, example: $operators_project
# function
check_create_oc_yaml() {
	local octype="$1"
	local name="$2"
	local yaml="$3"
	local ns="$4"

	check_file_exist $yaml
	mylog check "Checking ${octype} ${name} in ${ns} project"
	if oc get ${octype} ${name} -n ${ns} > /dev/null 2>&1; then mylog ok;else
		envsubst < "${yaml}" | oc -n ${ns} apply -f - || exit 1
	fi
}

################################################
# @param octype: kubernetes resource class, example: "deployment"
# @param ocname: name of the resource, example: "openldap"
# See https://github.com/osixia/docker-openldap for more details especialy all the configurations possible
# function
check_create_oc_openldap() {
	read_config_file "${yamldir}ldap/ldap.properties"
	local octype="$1"
	local name="$2"
	local ns="$3"

	# create namespace if needed
	CreateNameSpace ${ns}

	#SB]20231207 checks if used directories and files exists
	check_directory_exist ${yamldir}
	check_directory_exist ${workingdir}
	check_file_exist ${yamldir}ldap/ldap-pvc.main.yaml
	check_file_exist ${yamldir}ldap/ldap-pvc.config.yaml
	check_file_exist ${yamldir}ldap/ldap-config.json
	check_file_exist ${yamldir}ldap/ldap-users.ldif

	# check if deploment already performed
	mylog check "Checking ${octype} ${name} in ${ns}"
	if oc get ${octype} ${name} -n ${ns} > /dev/null 2>&1; then mylog ok;else
		mylog info "Creating LDAP server"
		oc adm policy add-scc-to-group anyuid system:serviceaccounts:${ns}
		
		# handle persitence for Openldap
		# only check one, assume that if one is created the other one is also created (short cut to optimize time)
		if oc get "PersistentVolumeClaim" "pvc-ldap-main" -n ${ns} > /dev/null 2>&1; then mylog ok;else
			envsubst < "${yamldir}ldap/ldap-pvc.main.yaml" > "${workingdir}ldap-pvc.main.yaml"
			envsubst < "${yamldir}ldap/ldap-pvc.config.yaml" > "${workingdir}ldap-pvc.config.yaml"
			oc create -f ${workingdir}ldap-pvc.main.yaml -n ${ns}
			oc create -f ${workingdir}ldap-pvc.config.yaml -n ${ns}
			wait_for_state "pvc pvc-ldap-config status.phase is Bound" "Bound" "oc get pvc pvc-ldap-config -n ${ns} -o jsonpath='{.status.phase}'"
			wait_for_state "pvc pvc-ldap-main status.phase is Bound" "Bound" "oc get pvc pvc-ldap-main -n ${ns} -o jsonpath='{.status.phase}'"
		fi

		# deploy openldap and take in account the PVCs just created
		# check that deployment of openldap was not done
		if oc get "deployment" "openldap" -n ${ns} > /dev/null 2>&1; then mylog ok;else
			oc -n ${ns} new-app osixia/${name}
			oc -n ${ns} get deployment.apps/openldap -o json | jq '. | del(."status")' > ${workingdir}openldap.json
			envsubst < "${yamldir}ldap/ldap-config.json" > "${workingdir}ldap-config.json"
			oc -n ${ns} patch deployment.apps/openldap --patch-file ${workingdir}ldap-config.json

			# expose service externaly and get host and port
			oc -n ${ns} patch service openldap -p='{"spec": {"type": "NodePort"}}'
			oc -n ${ns} get service openldap -o json | jq '.spec.ports |= map(if .name == "389-tcp" then . + { "nodePort": 30389 } else . end)' | jq '.spec.ports |= map(if .name == "636-tcp" then . + { "nodePort": 30686 } else . end)' > ${workingdir}openldap-service.json
			oc -n ${ns} patch service/openldap --patch-file ${workingdir}openldap-service.json
			oc -n ${ns} expose service openldap --name=openldap-external --target-port=389

			port=`oc -n ${ns} get service ${name} -o jsonpath='{.spec.ports[0].nodePort}'`
			hostname=`oc -n ${ns} get route openldap-external -o jsonpath='{.spec.host}'`

			# load users and groups into LDAP
			envsubst < "${yamldir}ldap/ldap-users.ldif" > "${workingdir}ldap-users.ldif"
			mylog info "Adding LDAP entries with following command: "
			mylog info "ldapadd -H ldap://${hostname}:${port} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -f ${workingdir}ldap-users.ldif"
			ldapadd -H ldap://${hostname}:${port} -D "${ldap_admin_dn}" -w "${ldap_admin_password}" -f ${workingdir}ldap-users.ldif

			mylog info "You can search entries with the following command: "
			# ldapmodify -H ldap://$hostname:$port -D "$ldap_admin_dn" -w admin -f ${ldapdir}Import.ldiff
			mylog info "ldapsearch -H ldap://${hostname}:${port} -x -D \"$ldap_admin_dn\" -w \"$ldap_admin_password\" -b \"$ldap_base_dn\" -s sub -a always -z 1000 \"(objectClass=*)\""
		fi
	fi
}

################################################
# Create namespace
# @param ns namespace to be created
# function
CreateNameSpace () {
  local ns=$1
  var_fail my_oc_project "Please define project name in config"
  mylog check "Checking project $ns"
  if oc get project $ns > /dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $ns"
    if ! oc new-project $ns; then
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
# function
check_resource_availability () {
  local octype="$1"
  local name="$2"
  local ns="$3"
  var=`oc get $octype -n $ns --ignore-not-found=true | grep $name | awk '{print $1}'`
  while [ -z "$var" ]; do
    var=`oc get $octype -n $ns --ignore-not-found=true | grep $name | awk '{print $1}'`;
    #sleep 5
  done
  #SB]20231013 simulate a return value by echoing it
  echo $var
}

################################################
##SB]20230201 use ibm-pak oc plugin
# function
check_add_cs_ibm_pak() {
  local CASE_NAME="$1"
  local CASE_VERSION="$2"
  local ARCH="$3"

  SECONDS=0
  oc ibm-pak get ${CASE_NAME} --version ${CASE_VERSION}
  oc ibm-pak generate mirror-manifests ${CASE_NAME} icr.io --version ${CASE_VERSION}
  if test -f  "~/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources.yaml";then
    oc apply -f ~/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources.yaml
  fi
  if test -f  "~/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources-linux-${ARCH}.yaml";then
    oc apply -f ~/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources-linux-${ARCH}.yaml
  fi
  # oc get catalogsource -n openshift-marketplace
  mylog info "Adding case $CASE_NAME took $SECONDS seconds to execute." 1>&2
}

################################################
##SB]20231201 create operator subscription
# function
create_operator_subscription() {

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  export operator_name=$1
  export current_channel=$2
  export catalog_source_name=$3
  export operator_ns=$4
  export strategy=$5

  check_directory_exist ${operatorsdir}

  SECONDS=0
  check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $operator_ns
  #SB]20231013 the function check_resource_availability will "return" the resource 
  resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $operator_ns)
  type="clusterserviceversion"
  path="{.status.phase}"
  state="Succeeded"
  wait_for_state "$type $resource $path is $state" "$state" "oc get $type $resource -n $operator_ns -o jsonpath='$path'"
  mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
}

#########################################################
##SB]20231205 create flink and event processing operators 
# function
create_ea_operators(){
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
    wait_for_state "$type $resource $path is $state" "$state" "oc get $type $resource -n $ns -o jsonpath='$path'"
    mylog info "Creation of $case_name operator took $SECONDS seconds to execute." 1>&2
  fi
}

################################################
##SB]20231204 create operand instance
# function
create_operand_instance() {
  local file=$1
  local ns=$2
  local path=$3
  local resource=$4
  local state=$5
  local type=$6

  SECONDS=0
  check_create_oc_yaml $type $resource $file $ns
  wait_for_state "$type $resource $path is $state" "$state" "oc get $type $resource -n $ns -o jsonpath='$path'"
  mylog info "Creation of $type instance took $SECONDS seconds to execute." 1>&2
}

################################################
# Get useful information to start using the stack
# Need to check that the resource exist.
# function
get_navigator_access() {
	cp4i_url=$(oc get platformnavigator cp4i-navigator -n $my_oc_project -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
	cp4i_uid=$(oc get secret ibm-iam-bindinfo-platform-auth-idp-credentials -n $my_oc_project -o jsonpath={.data.admin_username} | base64 -d)
	cp4i_pwd=$(oc get secret ibm-iam-bindinfo-platform-auth-idp-credentials -n $my_oc_project -o jsonpath={.data.admin_password} | base64 -d)
	mylog info "CP4I Platform UI URL: " $cp4i_url
	mylog info "CP4I admin user: " $cp4i_uid
	mylog info "CP4I admin password: " $cp4i_pwd
}

#########################################################################################################
##SB]20231109 Generate properties and yaml files
## input parameter the operand custom dir (and generated dir both with config and scripts subdirectories)
# function
generate_files () {
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