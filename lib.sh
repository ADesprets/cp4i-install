# asset that variablke is defined
# @param 1 name of variable
# @param 2 error message, or name of method to call if begins with "fix"
var_fail(){
	if eval test -z '$'$1;then
		mylog error "ERROR: missing config variable: $1" 1>&2
		case "$2" in
			fix*|echo*) eval $2 ;;
			"") ;;
			*) mylog log "$2" 1>&2;;
		esac
		exit 1
	fi
}

# simple logging with colors
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
	wait_for_state "$octype $ocname $ocpath is $ocstate" "$ocstate" "oc get ${octype} ${ocname} --output json|jq -r '${ocpath}'"
}

check_create_oc_yaml(){
	local octype="$1"
	local name="$2"
	local yaml="$3"
	mylog check "Checking ${octype} ${name}"
	if oc get ${octype} ${name} > /dev/null 2>&1; then mylog ok;else
		envsubst < "${yaml}" | oc apply -f - || exit 1
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
  var=`oc get $octype --ignore-not-found=true | grep $name | awk '{print $1}'`
  while [ -z "$var" ]; do
    var=`oc get $octype --ignore-not-found=true | grep $name | awk '{print $1}'`;
    #sleep 5
  done
}
