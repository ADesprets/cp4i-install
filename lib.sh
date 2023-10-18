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

	if test ! -e "${config_file}";then
		mylog error "No such file: $config_file" 1>&2
		exit 1
	fi

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
	info) c=2;;#green
	error) c=1;p='ERROR: ';;#red
	warn) c=3;;#yellow
	wait) c=4;p="$(date) ";;#blue
	check) c=6;w=-n;s=...;;#cyan
	ok) c=2;p=OK;;#green
	no) c=3;p=NO;;#yellow
	*) c=9;;#default
	esac
	shift
	echo $w "$(tput setaf $c)$p$@$s$(tput setaf 9)";
}

################################################
# Check that all required executables are installed
# function
check_exec_prereqs() {
	if ! command -v oc >/dev/null 2>&1; then
		echo "Executable 'oc' does not exist or is not executable, exiting."
		exit 1
	fi

	if ! command -v docker >/dev/null 2>&1; then
		echo "Executable 'docker' does not exist or is not executable, exiting."
		exit 1
	fi

	if ! command -v jq >/dev/null 2>&1; then
		echo "Executable 'jq' does not exist or is not executable, exiting."
		exit 1
	fi

	if ! command -v curl >/dev/null 2>&1; then
		echo "Executable 'curl' does not exist or is not executable, exiting."
		exit 1
	fi

	if ! command -v ibmcloud >/dev/null 2>&1; then
		echo "Executable 'ibmcloud' does not exist or is not executable, exiting."
		exit 1
	fi

	if ! command -v keytool >/dev/null 2>&1; then
		echo "Executable 'keytool' does not exist or is not executable, exiting."
		exit 1
	fi

	if ! command -v openssl >/dev/null 2>&1; then
		echo "Executable 'openssl' does not exist or is not executable, exiting."
		exit 1
	fi

	if ! command -v awk >/dev/null 2>&1; then
		echo "Executable 'awk' does not exist or is not executable, exiting."
		exit 1
	fi
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
  var_fail my_ic_apikey "Create and save API key JSON file from: https://cloud.ibm.com/iam/apikeys"
  mylog check "Login to IBM Cloud"
  if ! ibmcloud login -q --no-region --apikey $my_ic_apikey > /dev/null;then
    mylog error "Fail to login to IBM Cloud, check API key: $my_ic_apikey" 1>&2
    exit 1
  else mylog ok
  fi
}

################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
# requires var my_cluster_url
# function
Login2OpenshiftCluster () {
  mylog check "Login to cluster"
  while ! oc login -u apikey -p $my_ic_apikey --server=$my_cluster_url > /dev/null;do
	mylog error "$(date) Fail to login to Cluster, retry in a while (login using web to unblock)" 1>&2
	sleep 30
  done
  mylog ok
}

################################################
# wait for Cluster availability
# set variable my_cluster_url
# function
wait_for_cluster_availability () {
  wait_for_state 'Cluster state' 'normal-All Workers Normal' "ibmcloud oc cluster get --cluster $my_cluster_name --output json|jq -r '.state+\"-\"+.status'"

  mylog check "Checking Cluster URL"
  my_cluster_url=$(ibmcloud ks cluster get --cluster $my_cluster_name --output json | jq -r "$gbl_cluster_url_filter")
  case "$my_cluster_url" in
	https://*)
	mylog ok " -> $my_cluster_url"
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
# Wait for openshift entity to reach specified state
# @param octype: kubernetes resource class, example: "clusterserviceversion"
# @param ocname: name of the resource, example: ""
# @param ocstate: Value in the json of the status of a resource, example: "Succeeded"
# @param ocpath: path in the json to get the state of the resource, example: ".status.phase"
# @param ns: namespace/project
# function
wait_for_oc_state() {
	local octype=$1
	local ocname=$2
	local ocstate=$3
	local ocpath=$4
	local ns=$5
	wait_for_state "$octype $ocname $ocpath is $ocstate" "$ocstate" "oc get ${octype} ${ocname} -n ${ns} --output json|jq -r '${ocpath}'"
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
	local octype="$1"
	local name="$2"
	local ns="$3"

	# create namespace if needed
	CreateNameSpace ${ns}

	# check if deploment already performed
	mylog check "Checking ${octype} ${name} in ${ns}"
	if oc get ${octype} ${name} -n ${ns} > /dev/null 2>&1; then mylog ok;else
		mylog info "Creating LDAP server"
		oc adm policy add-scc-to-group anyuid system:serviceaccounts:${ns}
		
		# handle persitence for Openldap
		# only check one, assume that if one is created the other one is also created (short cut to optimize time)
		if oc get "PersistentVolumeClaim" "pvc-ldap-main" -n ${ns} > /dev/null 2>&1; then mylog ok;else
			oc create -f ${yamldir}kube_resources/ldap-pvc.main.yaml -n ${ns}
			oc create -f ${yamldir}kube_resources/ldap-pvc.config.yaml -n ${ns}
			wait_for_state "pvc pvc-ldap-config status.phase is Bound" "Bound" "oc get pvc pvc-ldap-config -n ${ns} --output json|jq -r '.status.phase'"
			wait_for_state "pvc pvc-ldap-main status.phase is Bound" "Bound" "oc get pvc pvc-ldap-main -n ${ns} --output json|jq -r '.status.phase'"
		fi

		# deploy openldap and take in account the PVCs just created
		# check that deployment of openldap was not done
		if oc get "deployment" "openldap" -n ${ns} > /dev/null 2>&1; then mylog ok;else
			oc -n ${ns} new-app osixia/${name}
			oc -n ${ns} get deployment.apps/openldap -o json | jq '. | del(."status")' > ${workingdir}openldap.json
			jq -s '.[0] * .[1] ' ${workingdir}openldap.json ${yamldir}kube_resources/ldap-config.json > ${workingdir}openldap.new.json
			oc apply -n ldap -f ${workingdir}openldap.new.json

			# expose service externaly and get host and port
			oc -n ${ns} expose service/${name} --target-port=389 --name=openldap-external
			oc -n ${ns} get service ${name} -o json  | jq '.spec.ports[0] += {"Nodeport":30389}' | jq '.spec.ports[1] += {"Nodeport":30686}' | jq '.spec.type |= "NodePort"' | oc apply -f -
			port=`oc -n ${ns} get service ${name} -o json  | jq -r '.spec.ports[0].nodePort'`
			# oc -n ${ns} create route simple ldap-route --service=${openldap-external} --port=389
			hostname=`oc -n ${ns} get route openldap-external -o json | jq -r '.spec.host'`

			# load users and groups into LDAP
			envsubst < "${yamldir}config/Import.tmpl" > "${yamldir}config/Import.ldiff"
			ldapadd -H ldap://$hostname:$port -D "$ldap_admin_dn" -w "$ldap_admin_password" -f ${yamldir}kube_resources/ldap-users.ldif

			mylog info "You can search entries with the following command: "
			# ldapmodify -H ldap://$hostname:$port -D "$ldap_admin_dn" -w admin -f ${ldapdir}Import.ldiff
			# ldapsearch -H ldap://${host}:${port} -x -D "$ldap_admin_dn" -w "$ldap_admin_password" -b "$ldap_base_dn" -s sub -a always -z 1000 "(objectClass=*)"
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
  # TODO check files exist, if both are missing error, exit, some are specific to architecture some are not
  oc apply -f ~/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources.yaml
  oc apply -f ~/.ibm-pak/data/mirror/${CASE_NAME}/${CASE_VERSION}/catalog-sources-linux-${ARCH}.yaml
  oc get catalogsource -n openshift-marketplace
  mylog info "Adding case $CASE_NAME took $SECONDS seconds to execute." 1>&2
}

################################################
# Get useful information to start using the stack
# Need to check that the resource exist.
# function
get_navigator_access() {
	cp4i_url=$(oc get platformnavigator cp4i-navigator -n $my_oc_project -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
	cp4i_uid=$(oc get secret ibm-iam-bindinfo-platform-auth-idp-credentials -n $my_oc_project -o jsonpath={.data.admin_username} | base64 -d)
	cp4i_pwd=$(oc get secret ibm-iam-bindinfo-platform-auth-idp-credentials -n $my_oc_project -o jsonpath={.data.admin_password} | base64 -d)
	echo "CP4I Platform UI URL: " $cp4i_url
	echo "CP4I admin user: " $cp4i_uid
	echo "CP4I admin password: " $cp4i_pwd
}