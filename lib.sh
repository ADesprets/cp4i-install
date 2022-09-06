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

assert_args_fail(){
  if test "$1" -ne "$2";then
    mylog error "Wrong number of arguments, expect $1, have $2" 1>&2
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

################################################
# Log in IBM Cloud
Login2IBMCloud () {
  var_fail my_ic_apikey "Create and save API key JSON file from: https://cloud.ibm.com/iam/apikeys"
  mylog check "Login to IBM Cloud"
  if ! ibmcloud login -q --no-region --apikey $my_ic_apikey > /dev/null;then
    mylog error "Fail to login to IBM Cloud, check API key: $my_ic_apikey" 1>&2
    exit 1
  else mylog ok
  fi
}

# wait for Cluster availability
# set variable my_cluster_url
Wait4ClusterAvailability () {
  wait_for_state 'Cluster state' 'normal-All Workers Normal' "ibmcloud oc cluster get --cluster $my_ic_cluster_name --output json|jq -r '.state+\"-\"+.status'"

  mylog check "Checking Cluster URL"
  my_cluster_url=$(ibmcloud ks cluster get --cluster $my_ic_cluster_name --output json | jq -r "$gbl_cluster_url_filter")
  case "$my_cluster_url" in
  https://*)
  mylog ok " -> $my_cluster_url"
  ;;
  *)
  mylog error "Error getting cluster URL for $my_ic_cluster_name" 1>&2
  exit 1
  ;;
  esac
}

################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
# requires var my_cluster_url
Login2OpenshiftCluster () {
  mylog check "Login to cluster"
  while ! oc login -u apikey -p $my_ic_apikey --server=$my_cluster_url > /dev/null;do
  mylog error "$(date) Fail to login to Cluster, retry in a while (login using web to unblock)" 1>&2
  sleep 30
  done
  mylog ok
}

# wait for command to return specified value
# @param what description of waited state
# @param value expected state value from check command
# @param command executed command that returns some state
wait_for_state(){
  assert_args_fail 3 $#
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
  assert_args_fail 4 $#
  local octype=$1
  local ocname=$2
  local ocstate=$3
  local ocpath=$4
  wait_for_state "$octype $ocname $ocpath is $ocstate" "$ocstate" "oc get ${octype} ${ocname} -n $my_oc_project --output json|jq -r '${ocpath}'"
}

check_create_oc_yaml(){
  assert_args_fail 1 $#
  local yaml="$1"
  local ocns=$(envsubst < "${yaml}" | sed -n 's/^  namespace: *//p')
  local octype=$(envsubst < "${yaml}" | sed -n 's/^kind: *//p')
  local ocname=$(envsubst < "${yaml}" | sed -n 's/^  name: *//p'|head -n 1)
  mylog check "Checking ${octype} ${ocname} in ${ocns}"
  if oc get ${octype} ${ocname} -n ${ocns} > /dev/null 2>&1; then mylog ok;else
    envsubst < "${yaml}" | oc apply -f - || exit 1
  fi
}

check_create_wait_oc_yaml(){
  assert_args_fail 3 $#
  local yaml="$1"
  local state_path="$2"
  local state_value="$3"
  check_create_oc_yaml "${yaml}"
  local octype=$(envsubst < "${yaml}" | sed -n 's/^kind: *//p')
  local ocname=$(envsubst < "${yaml}" | sed -n 's/^  name: *//p'|head -n 1)
  wait_for_oc_state ${octype} ${ocname} "${state_value}" "${state_path}"
}

check_create_wait_sub_oc_yaml(){
  assert_args_fail 1 $#
  local yaml="$1"
  local ocname=$(envsubst < "${yaml}" | sed -n 's/^  name: *//p'|head -n 1)
  check_create_oc_yaml "${yaml}"
  check_resource_availability  ${ocname}
  wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
}

check_resource_availability () {
  assert_args_fail 1 $#
  local octype=clusterserviceversion
  local name="$1"
  var=''
  while true; do
    var=`oc get $octype -n $my_oc_project --ignore-not-found=true | grep $name | awk '{print $1}'`
    test -n "$var" && break
    mylog log "Waiting for $name"
    sleep 1
  done
}
