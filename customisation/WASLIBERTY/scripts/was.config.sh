#!/bin/bash

################################################
# Ensure internal registry is available
################################################
function prepare_internal_registry() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:prepare_internal_registry"
  # Expose service using default route
  oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

  # Get the default registry route:
  export IMAGE_REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')

  # Get the certificate of the Ingress Operator and add it in the trust store, need to check if this is in /usr/local/share/ca-certificates
  # oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt  > /dev/null
  # oc -n openshift-ingress get secret letsencrypt-certs -o go-template='{{index .data "tls.crt7"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt
  # For Ubuntu:  update-ca-certificates / For Mac: / For RH: update-ca-trust / For Windows: 
  # sudo update-ca-trust enable

  decho 3 "F:OUT:prepare_internal_registry"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Compile code
################################################
function compile_code() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:compile_code"
  mvn clean install
  # $MY_CONTAINER_ENGINE build -t basicjaxrs:1.0 .
  decho 3 "F:OUT:compile_code"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Build docker image
################################################
function was_build_image() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:was_build_image"
  $MY_CONTAINER_ENGINE build -t ${MY_WASLIBERTY_APP_NAME_VERSION} .
  decho 3 "F:OUT:was_build_image"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Login to internal registry
################################################
function login_to_registry() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:login_to_registry"

  decho 3 "Internal image registry host: $IMAGE_REGISTRY_HOST"
  local lf_cluster_server=$(oc whoami --show-server)
  decho 3 "Cluster server host: $lf_cluster_server"
  echo "kubeadmin password: $MY_TECHZONE_PASSWORD"
  oc login -u kubeadmin -p $MY_TECHZONE_PASSWORD $lf_cluster_server
  local lf_token=$(oc whoami -t)
  docker login -u kubeadmin -p $lf_token $IMAGE_REGISTRY_HOST
  
  decho 3 "F:OUT:login_to_registry"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Push image to internal registry
################################################
function push_image_to_registry() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:push_image_to_registry"
  
  #	tag the local image with details of image registry
  decho 3 "CMD: $MY_CONTAINER_ENGINE tag ${MY_WASLIBERTY_APP_NAME_VERSION} ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/${MY_WASLIBERTY_APP_NAME_VERSION}"
  $MY_CONTAINER_ENGINE tag ${MY_WASLIBERTY_APP_NAME_VERSION} ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/${MY_WASLIBERTY_APP_NAME_VERSION}
  $MY_CONTAINER_ENGINE push ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/${MY_WASLIBERTY_APP_NAME_VERSION}
    
  decho 3 "F:OUT:push_image_to_registry"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Create application from image
################################################
function create_application() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho 3 "F:IN:create_application"
    mylog info "Application:version ${MY_WASLIBERTY_APP_NAME_VERSION}"
    # Creating APIC instance
    lf_file="${MY_OPERANDSDIR}WAS-WLApp.yaml"
    lf_ns="${MY_BACKEND_NAMESPACE}"
    lf_path="{.status.phase}"
    lf_resource="$MY_WASLIBERTY_APP_NAME"
    lf_state="Ready"
    lf_type="WebSphereLibertyApplication"
    lf_wait_for_state=false
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  
  decho 3 "F:OUT:create_application"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
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
    login_to_registry
    push_image_to_registry
    create_application
  fi

duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2