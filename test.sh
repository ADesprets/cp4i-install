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
  
  res=$(ibmcloud ks versions -q --show-version Openshift --output json| jq --argjson vmaj "$vmaj" --argjson vmin "$vmin" '.openshift[] | select (.major == $vmaj and .minor == $vmin)' | jq -c | jq -R)
  #res=$(ibmcloud ks versions -q --show-version Openshift --output json| jq --argjson vmaj "$vmaj" --argjson vmin "$vmin" '.openshift[] | select (.major == $vmaj and .minor == $vmin)')
  echo $res
}



MY_OC_VERSION="4.14"
ADEBUG=1

mylog info "Getting current version for OC: $MY_OC_VERSION"
oc_version_full=$(check_openshift_version $MY_OC_VERSION)
decho "oc_version_full=$oc_version_full"

if [ -z "$oc_version_full" ]; then
  mylog error "Failed to find full version for ${MY_OC_VERSION}" 1>&2
  #fix_oc_version
  exit 1
fi

oc_version_full=$(echo $oc_version_full|jq .)
oc_version_full=$(echo "[$oc_version_full]" | jq -r '.[] | (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) + "_openshift"')
mylog info "Found: ${oc_version_full}"

