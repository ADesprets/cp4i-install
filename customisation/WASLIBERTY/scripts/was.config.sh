#!/bin/bash

################################################
# Ensure internal registry is available
################################################
function prepare_internal_registry() {
  trace_in 3 prepare_internal_registry

  # Expose service using default route
  oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

  # Get the default registry route:
  export IMAGE_REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')

  # Get the certificate of the Ingress Operator and add it in the trust store, need to check if this is in /usr/local/share/ca-certificates
  # oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt  > /dev/null
  # oc -n openshift-ingress get secret letsencrypt-certs -o go-template='{{index .data "tls.crt7"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt
  # For Ubuntu:  update-ca-certificates / For Mac: / For RH: update-ca-trust / For Windows: 
  # sudo update-ca-trust enable

  trace_out 3 prepare_internal_registry
}

################################################
# Compile code
################################################
function compile_code() {
  trace_in 3 compile_code

  mvn clean install
  # $MY_CONTAINER_ENGINE build -t basicjaxrs:1.0 .

  trace_out 3 compile_code
}

################################################
# Build docker image
################################################
function was_build_image() {
  trace_in 3 was_build_image

  $MY_CONTAINER_ENGINE build -t ${MY_WASLIBERTY_APP_NAME_VERSION} .

  trace_out 3 was_build_image
}

################################################
# Login to internal registry
################################################
function login_to_registry() {
  trace_in 3 login_to_registry

  decho 3 "Internal image registry host: $IMAGE_REGISTRY_HOST"
  local lf_cluster_server=$(oc whoami --show-server)
  decho 3 "Cluster server host: $lf_cluster_server"
  echo "kubeadmin password: $MY_TECHZONE_PASSWORD"
  oc login -u kubeadmin -p $MY_TECHZONE_PASSWORD $lf_cluster_server
  local lf_token=$(oc whoami -t)
  docker login -u kubeadmin -p $lf_token $IMAGE_REGISTRY_HOST
  
  trace_out 3 login_to_registry
}

################################################
# Push image to internal registry
################################################
function push_image_to_registry() {
  trace_in 3 push_image_to_registry
  
  #	tag the local image with details of image registry
  decho 3 "CMD: $MY_CONTAINER_ENGINE tag ${MY_WASLIBERTY_APP_NAME_VERSION} ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/${MY_WASLIBERTY_APP_NAME_VERSION}"
  $MY_CONTAINER_ENGINE tag ${MY_WASLIBERTY_APP_NAME_VERSION} ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/${MY_WASLIBERTY_APP_NAME_VERSION}
  $MY_CONTAINER_ENGINE push ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/${MY_WASLIBERTY_APP_NAME_VERSION}
    
  trace_out 3 push_image_to_registry
}

################################################
# Create application from image
################################################
function create_application() {
  trace_in 3 create_application

  mylog info "Application:version ${MY_WASLIBERTY_APP_NAME_VERSION}"

  local lf_working_directory="${MY_WASLIBERTY_WORKINGDIR}"
  check_directory_exist_create "${lf_working_directory}"

  local lf_namespace=$MY_BACKEND_NAMESPACE

  local lf_type="WebSphereLibertyApplication"
  local lf_cr_name="${MY_WASLIBERTY_APP_NAME}"
  local lf_source_directory="${MY_OPERANDSDIR}"
  local lf_target_directory="${lf_working_directory}"
  local lf_yaml_file="WAS-WLApp.yaml"

  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"
  
  local lf_cr_name=$(oc -n $lf_namespace get $lf_type -o jsonpath="{.items[0].metadata.name}")
  local lf_path="{.status.conditions[-1].type}"
  local lf_state="ResourcesReady"
  decho 3 "wait_for_state \"$lf_type $lf_cr_name is $lf_state\" \"$lf_state\" \"oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'\""
  wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
  
  trace_out 3 create_application
}

################################################################################################
# Start of the script main entry
# main
# This script needs to be started in the same directory as this script.

mylog info "Create back end applications"

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
# scriptdir=$(dirname "$0")/
scriptdir=${PWD}/
lf_was_config_dir=${MY_WASLIBERTY_SCRIPTDIR}config/
decho 5 "WAS configuration directory: ${lf_was_config_dir}"

# load helper functions
. "${scriptdir}"lib.sh

  # load config file
  read_config_file "${lf_was_config_dir}was.properties"

  if $MY_WASLIBERTY_CUSTOM; then
    prepare_internal_registry
    # Build the image
    if $MY_WASLIBERTY_CUSTOM_BUILD; then
      pushd ${MY_WASLIBERTY_SCRIPTDIR} > /dev/null 2>&1
      mylog info "==== Compile code and build docker image." 1>&2
      compile_code
      was_build_image
      popd > /dev/null 2>&1
    fi
    # save the current cluster config context
    sc_current_context=$(oc config current-context)
    login_to_registry
    push_image_to_registry
    create_application
    oc logout
    # back to the saved context
    oc config use-context $sc_current_context
  fi

duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2