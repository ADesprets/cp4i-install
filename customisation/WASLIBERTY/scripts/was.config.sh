#!/bin/bash

################################################
# Ensure internal registry is available
################################################
function prepare_internal_registry() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:prepare_internal_registry"
  # Expose service using default route
  oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

  # Get the default registry route:
  export IMAGE_REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')

  # Get the certificate of the Ingress Operator and add it in the trust store, need to check if this is in /usr/local/share/ca-certificates
  # oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt  > /dev/null
  # oc -n openshift-ingress get secret letsencrypt-certs -o go-template='{{index .data "tls.crt7"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt
  # For Ubuntu:  update-ca-certificates / For Mac: / For RH: update-ca-trust / For Windows: 
  # sudo update-ca-trust enable

  decho "F:OUT:prepare_internal_registry"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Compile code
################################################
function compile_code() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:compile_code"
  mvn clean install
  # $MY_CONTAINER_ENGINE build -t basicjaxrs:1.0 .
  decho "F:OUT:compile_code"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Build docker image
################################################
function was_build_image() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:was_build_image"
  $MY_CONTAINER_ENGINE build -t demo:1.0 .
  decho "F:OUT:was_build_image"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Get token to access internal registry
################################################
function get_login_token() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:get_login_token"
  mylog info "For now, you need to be logged in to the image registry before running the script"
  decho "F:OUT:get_login_token"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Push image to internal registry
################################################
function push_image_to_registry() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:push_image_to_registry"
  
  #	tag the local image with details of image registry
  $MY_CONTAINER_ENGINE tag demo:1.0 ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/demo:1.0
  $MY_CONTAINER_ENGINE push ${IMAGE_REGISTRY_HOST}/${MY_BACKEND_NAMESPACE}/demo:1.0
    
  decho "F:OUT:push_image_to_registry"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Create application from image
################################################
function create_application() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:create_application"
  
  decho "F:OUT:create_application"
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

# load helper functions
. "${scriptdir}"lib.sh

  if $MY_WASLIBERTY_CUSTOM; then
    mylog info "==== Customise WAS." 1>&2
    # prepare_internal_registry
    # Build the image
    if $MY_WASLIBERTY_CUSTOM_BUILD; then
      pushd ${WASLIBERTY_SCRIPTDIR} > /dev/null 2>&1
      mylog info "==== Compile code and build docker image." 1>&2
      compile_code
      was_build_image
      popd > /dev/null 2>&1
    fi
    get_login_token
    push_image_to_registry
    # create_application
  fi

duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2