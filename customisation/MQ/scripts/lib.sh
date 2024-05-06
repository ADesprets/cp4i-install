################################################
# Help function 
################################################
function print_help () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :print_help"

  mylog "info" "Usage: for installation           : $sc_script -i properties_file version_file qmgr applyflag(y|n)"
  mylog "info" "Usage: for cleaning/deleting      : $sc_script -d properties_file version_file qmgr applyflag(y|n)"
  mylog "info" "Usage: for monitoring connections : $sc_script -c properties_file version_file qmgr"
  mylog "info" "Usage: for running applications   : $sc_script -a properties_file version_file qmgr queue p|g appcount"
  mylog "info" "Usage: to print help              : $sc_script -h"
  mylog "info" "option possible values            : -a|-c|-d|-h|-i"

  decho "F:OUT:print_help"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# encode_b64_file function 
# return the encoded (base64) input parameter
#
function encode_b64_file () {
  local lf_in_file=$1
  local lf_encoded=""

  lf_encoded=$(cat $lf_in_file | base64 -w 0)
  echo $lf_encoded
}

################################################
#########################################################################
# function to print message if debug is set to 1

################################################
# assert that variable is defined
# @param 1 name of variable
# @param 2 error message, or name of method to call if begins with "fix"
function var_fail () {
	if eval test -z '$'$1;then
		mylog error "missing config variable: $1" 1>&2
		case "$2" in
			fix*|echo*) eval $2 ;;
			"") ;;
			default) mylog log "$2" 1>&2;;
		esac
		exit 1
	fi
}

################################################
# simple logging with colors
# @param 1 level (info/error/warn/wait/check/ok/no)
function mylog () {
  local lf_spaces=$(printf "%0.s " $(seq 1 $sc_spaces_counter))

	local p=
	local w=
	local s=
	case $1 in
	  info)    c=2               ;; #green
	  error)   c=1; p='ERROR: '  ;; #red
	  warn)    c=3               ;; #yellow
      debug)   c=8; p='CMD: '    ;; #yellow
	  wait)    c=4; p="$(date) " ;; #blue
	  check)   c=6; w=-n; s=...  ;; #cyan
	  ok)      c=2; p=OK         ;; #green
	  no)      c=3; p=NO         ;; #yellow
	  default) c=9               ;; #default
	esac
	shift
  echo $w "$(tput setaf $c)$lf_spaces$p$@$s$(tput setaf 9)"
}

# wait for command to return specified value
# @param what description of waited state
# @param value expected state value from check command
# @param command executed command that returns some state
function wait_for_state () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :wait_for_state"

	local what=$1
	local value=$2
	local command=$3

  decho "what=$what|value=$value|command=$command"

	mylog "check" "Checking $what"
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
  decho "F:OUT:wait_for_state"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# Check that all required executables are installed
function check_command_exist () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_command_exist"

  local lf_in_command=$1

  if ! command -v $lf_in_command >/dev/null 2>&1; then
		mylog "error" "Executable $lf_in_command does not exist or is not executable, exiting."
		exit 1
  fi

  decho "F:OUT:check_command_exist"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

######################################################
# checks if the file exist, if no print a msg and exit
#
function check_file_exist () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_file_exist"

	local lf_in_file=$1
	if [ ! -e "$lf_in_file" ]; then
		mylog "error" "No such file: $lf_in_file" 1>&2
		exit 1
	fi

  decho "F:OUT:check_file_exist"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

######################################################
# checks if the directory exist, if no print a msg and exit
#
function check_directory_exist () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_directory_exist"

  local directory=$1
  if [ ! -d $directory ]; then
    mylog error "No such directory: $directory" 1>&2
	  exit 1
  fi

  decho "F:OUT:check_directory_exist"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

######################################################
# checks if the directory exist, otherwise create it
#
function check_directory_exist_create () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_directory_exist_create"

  local directory=$1
  if [ ! -d $directory ]; then
    mkdir -p $directory
  fi

  decho "F:OUT:check_directory_exist_create"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# check_connect_runmqsc function 
# See if runmqsc connected, i.e. the queue manager is running
#
function check_connect_runmqsc() {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_connect_runmqsc"

  local lf_in_qmgr=$1

  # SB]20221207 en cas d'authentification le profil suivant doit être activé sinon pas de connexion
  # pour compter le nombre de connexions 
  # SET AUTHREC PRINCIPAL('${clnt1}') OBJTYPE(QMGR) AUTHADD(ALL)
  #echo "dis qmgr"|runmqsc -c $sb_in_qmgr
  echo "dis qmgr"|runmqsc -c $lf_in_qmgr >/dev/null 2>&1
  if [ $? -ne 0 ]; then 
      mylog error "$lf_in_qmgr not available"
      exit 1
  fi

  decho "F:OUT:check_connect_runmqsc"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# check_queue_exist function 
# See if the queue exist on the QMGR
################################################
function check_queue_exist () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_queue_exist"

  local lf_in_queue=$1
  local lf_in_qmgr=$2

  local lf_amq_msg
  local lf_strarray
  local lf_amq_mesg_first
  
  # SB]20221207 en cas d'authentification le profil suivant doit être activé sinon pas de connexion
  # pour compter le nombre de connexions 
  # SET AUTHREC PRINCIPAL('${clnt1}') OBJTYPE(QMGR) AUTHADD(ALL)
  #echo "dis qmgr"|runmqsc -c $lf_qmgr
  lf_amq_msg=$(echo "dis ql($lf_in_queue)" | runmqsc -c $lf_in_qmgr | grep '^AMQ')

  if [ $? -ne 0 ]; then 
    IFS=':'
    read -a lf_strarray <<< "$lf_amq_msg"
    lf_amq_mesg_first=${lf_strarray[0]}

  	case $lf_amq_mesg_first in
  	  AMQ8135E) mylog "error" "$lf_amq_mesg Check authorizations for this queue : $lf_in_queue";;
  	  AMQ8147E) mylog "error" "$lf_amq_mesg Check the existence of queue : $lf_in_queue"
                mylog "info" "use one of the following queues"
                echo "dis ql(*)" | runmqsc edf | tail -n +6 | grep -oP '(?<=[(])[^)]*' | grep -v -E "^SYSTEM|^AMQ|^QLOCAL";; # https://www.baeldung.com/linux/extract-text-between-two-characters
  	  AMQ9708E) mylog "error" "A problem with the client keystore or stash file was encountered";;
  	esac
    exit 1
  fi

  decho "F:OUT:check_queue_exist"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# check_config_and_version_files function 
################################################
function check_config_and_version_files () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_config_and_version_files"

  local lf_in_config_file=$1
  local lf_in_versions_file=$2

  ## load user specific variables,
  check_file_exist $lf_in_config_file
  
  # load specific versions for cp4i
  check_file_exist $lf_in_versions_file
  
  # load user specific variables, "set -a" so that variables are part of environment for envsubst
	set -a
	. "${lf_in_config_file}"
  . "${lf_in_versions_file}"
	set +a

  decho "F:OUT:check_config_and_version_files"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

#############################################################
# check_qmgr_running function 
# check that the qmgr is running
#
function check_qmgr_running () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_qmgr_running"

  # Check that the queue manager name is valid and available (the one provided as an argument for this script !!!)
  local lf_qmgrtype="QueueManager"
  local lf_qmgrstate="Running"
  local lf_qmgrstatuspath=".status.phase"
  
  local lf_current_state=$(oc -n $OC_PROJECT get ${lf_qmgrtype} ${QMGR} --output json|jq -r ${lf_qmgrstatuspath})
  
  if [ "$lf_current_state" != "$lf_qmgrstate" ]; then  
    mylog "info" "$QMGR not available"
    exit 1
  fi

  decho "F:OUT:check_qmgr_running"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

#################################################################
# check_appchoice_appcount function 
# check that appcount has the correct value : p (put) or g (get)
#
function check_appchoice_appcount () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_appchoice_appcount"

  local lf_in_appchoice=$1
  local lf_in_appcount=$2
  
  decho "lf_in_appchoice=$lf_in_appchoice|lf_in_appcount=$lf_in_appcount"

  if [ "$lf_in_appchoice" != "g" ] && [ "$lf_in_appchoice" != "p" ]; then 
    print_help
    mylog "error" "choose p for amqsphac application and g for amqsghac application"
    exit 1
  fi

  is_int $lf_in_appcount
  if [ $? -eq 1 ]; then 
    print_help
    mylog "error" "the appcount must be a integer"
    exit 1
  fi

  decho "F:OUT:check_appchoice_appcount"
  sc_spaces_counter=$((sc_spaces_counter-$sc_spaces_incr))
}

################################################
# check_putgetflag function 
# check that the flag has correct value : p|g|pg
#
function check_putgetflag () {
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
  decho "F:IN :check_putgetflag"

  local lf_in_flag=$1

	case $lf_in_flag in
	  p|g|pg) ;;
	  default) print_help
             mylog error "flag possibles values : p|g|pg"
             exit 1
            ;; 
	esac

  decho "F:OUT:check_putgetflag"
  sc_spaces_counter=$((sc_spaces_counter+$sc_spaces_incr))
}
