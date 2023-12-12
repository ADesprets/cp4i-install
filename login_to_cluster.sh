#!/bin/bash

################################################
# simple logging with colors
# @param 1 level (info/error/warn/wait/check/ok/no)
# function
mylog() {
	p=
	w=
	s=
	case $1 in
		"info" ) c=2;; # green
		"error" ) c=1;p='ERROR: ';; # red
		"warn" ) c=3;; # yellow
		"wait" ) c=4;p="$(date) ";; # blue
		"check" ) c=6;w=-n;s=...;; # cyan
		"ok" ) c=2;p=OK;; # green
		"no" ) c=3;p=NO;; # yellow
		* ) c=9;; # default
	esac
	shift
	echo $w "$(tput setaf $c)$p$@$s$(tput setaf 9)";
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
    # SB]20231208 The following command sets your command line context for the cluster and download the TLS certificates and permission files for the administrator.
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

################################################################################################
# Start of the script main entry
################################################################################################
# This is the default value for the cluster if no argument is passed, change it to your favorite cluster
my_cluster_name=cp4iad22023

if (($# == 1)); then
  my_cluster_name=$1
elif (($# > 1)); then
  echo "the number of arguments should be 0 or 1"
  exit 1
fi

mylog info "Attempt to log to $my_cluster_name cluster."

mainscriptdir=$(dirname "$0")/
privatedir="${mainscriptdir}private/"

my_ic_apikey=$(jq -r .apikey < "${privatedir}apikey.json")
SECONDS=0
Login2IBMCloud
mylog info "Login in to IBM Cloud took $SECONDS seconds to execute." 1>&2
ibmcloud target -r eu-de
ibmcloud target -g default

# Check billing directory exist
if [ ! -d ~/billing ]; then
  mkdir ~/billing
fi

cost=$(ibmcloud billing account-usage --output json | jq .Summary.resources.billable_cost)
mylog info "Updating ~/billing/ibmcloud-cost.txt, current cost is $cost." 1>&2
echo "`date` : $cost" >> ~/billing/ibmcloud-cost.txt

if ! ibmcloud ks cluster get --cluster $my_cluster_name --output json > /dev/null 2>&1; then
  mylog info "Cluster $my_cluster_name does not exist, do not attempt to login"
else
  gbl_cluster_url_filter=.serverURL
  my_cluster_url=$(ibmcloud ks cluster get --cluster $my_cluster_name --output json | jq -r "$gbl_cluster_url_filter")
  SECONDS=0
  mylog info "my_cluster_url: $my_cluster_url"
  Login2OpenshiftCluster
  mylog info "Login in to Openshift cluster took $SECONDS seconds to execute." 1>&2
fi
