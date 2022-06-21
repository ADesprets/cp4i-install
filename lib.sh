read_config_file(){
	if test -n "$PC_CONFIG";then
	  config_file="$PC_CONFIG"
	else
	  config_file="$1"
	fi
	if test -z "$config_file";then
		mylog error "Usage: $0 <config file>" 1>&2
		mylog info "Example: $0 ${scriptdir}cp4i.conf"
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

# assert that variable is defined
# @param 1 name of variable
# @param 2 error message, or name of method to call if begins with "fix"
var_fail(){
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

# simple logging with colors
# @param 1 level (info/error/warn/wait/check/ok/no)
mylog(){
	p=
	w=
	s=
	case $1 in
	info)c=2;;#green
	error)c=1;p='ERROR: ';;#red
	warn)c=3;;#yellow
	wait)c=4;p="$(date) ";;#blue
	check)c=6;w=-n;s=...;;#cyan
	ok)c=2;p=OK;;#green
	no)c=3;p=NO;;#yellow
	*) c=9;;#default
	esac
	shift
	echo $w "$(tput setaf $c)$p$@$s$(tput setaf 9)";
}

Login2IBMCloud () {
################################################
# Log in IBM Cloud
  var_fail my_ic_apikey "Create and save API key JSON file from: https://cloud.ibm.com/iam/apikeys"
  mylog check "Login to IBM Cloud"
  if ! ibmcloud login -q --no-region --apikey $my_ic_apikey > /dev/null;then
    mylog error "Fail to login to IBM Cloud, check API key: $my_ic_apikey" 1>&2
    exit 1
  else mylog ok
  fi
}

Login2OpenshiftCluster () {
################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
  mylog check "Login to cluster"
  while ! oc login -u apikey -p $my_ic_apikey --server=$my_server_url > /dev/null;do
	mylog error "$(date) Fail to login to Cluster, retry in a while (login using web to unblock)" 1>&2
	sleep 30
  done
  mylog ok
}

# set variable my_server_url
Wait4ClusterAvailability () {
# wait for Cluster availability
  wait_for_state 'Cluster state' 'normal-All Workers Normal' "ibmcloud oc cluster get --cluster $my_ic_cluster_name --output json|jq -r '.state+\"-\"+.status'"

  mylog check "Checking Cluster URL"
  my_server_url=$(ibmcloud ks cluster get --cluster $my_ic_cluster_name --output json | jq -r .serverURL)
  case "$my_server_url" in
	https://*)
	mylog ok " -> $my_server_url"
	;;
	*)
	mylog error "Error getting cluster URL for $my_ic_cluster_name" 1>&2
	exit 1
	;;
  esac
}

# wait for command to return specified value
# @param what description of waited state
# @param value expected state value from check command
# @param command executed command that returns some state
wait_for_state(){
	local what=$1
	local value=$2
	local command=$3
	# wait for HSTS availability
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

# wait for openshift entity to reach specified state
wait_for_oc_state(){
	local octype=$1
	local ocname=$2
	local ocstate=$3
	local ocpath=$4
	wait_for_state "$octype $ocname $ocpath is $ocstate" "$ocstate" "oc get ${octype} ${ocname} -n $my_oc_project --output json|jq -r '${ocpath}'"
}

check_create_oc_yaml(){
	local octype="$1"
	local name="$2"
	local yaml="$3"
	local ns="$4"
	mylog check "Checking ${octype} ${name}"
	if oc get ${octype} ${name} -n ${ns} > /dev/null 2>&1; then mylog ok;else
		envsubst < "${yaml}" | oc apply -f - || exit 1
	fi
}

check_create_oc_openldap(){
	local octype="$1"
	local name="$2"
	mylog check "Checking ${octype} ${name}"
	if oc get ${octype} ${name} > /dev/null 2>&1; then mylog ok;else
      oc new-app openshift/${name}
      oc expose service/${name}
      oc get service ${name} -o json  | jq '.spec.ports[0] += {"Nodeport":30389}' | jq '.spec.ports[1] += {"Nodeport":30686}' | jq '.spec.type |= "NodePort"' | oc apply -f -
      port=`oc get service ${name} -o json  | jq -r '.spec.ports[0].nodePort'`
      hostname=`oc get route ${name} -o json | jq -r '.spec.host'`
      envsubst < "${ldapdir}Import.tmpl" > "${ldapdir}Import.ldiff"
      ldapmodify -H ldap://$hostname:$port -D "$my_dn_openldap" -w admin -f ${ldapdir}Import.ldiff
	fi
}

check_create_oc_yaml_redis(){
	local octype="$1"
	local name="$2"
	local yaml="$3"
	mylog check "Checking ${octype} ${name} in openshift-operators"
	if oc get ${octype} ${name} -n openshift-operators > /dev/null 2>&1; then mylog ok;else
		envsubst < "${yaml}" | oc apply -f - || exit 1
	fi
}

check_resource_availability () {
  local octype="$1"
  local name="$2"
  var=`oc get $octype -n $my_oc_project --ignore-not-found=true | grep $name | awk '{print $1}'`
  while [ -z "$var" ]; do
    var=`oc get $octype -n $my_oc_project --ignore-not-found=true | grep $name | awk '{print $1}'`;
    #sleep 5
  done
}
