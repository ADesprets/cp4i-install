#!/bin/bash

################################################
# Ensure internal registry is available
################################################
function prepare_internal_registry() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:prepare_internal_registry"

  decho "F:OUT:prepare_internal_registry"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Compile code
################################################
function compile_code() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:compile_code"
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
  $MY_CONTAINER_ENGINE build -t basicjaxrs:1.0 .
  decho "F:OUT:was_build_image"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Get token to access internal registry
################################################
function get_login_token() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:get_login_token"

  decho "F:OUT:get_login_token"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER-$SC_SPACES_INCR))
}

################################################
# Push image to internal registry
################################################
function push_image_to_registry() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER+$SC_SPACES_INCR))
  decho "F:IN:push_image_to_registry"
  
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

# backend J2EE applications
if $MY_OPENLIBERTY_CUSTOM; then
  mylog info "==== Customise OPEN Liberty." 1>&2

  # Handle private image registry
  # I'm using a service id associated to my email, information are configured in private/users.properties (See README.dm)
  # Creating the secret to access the images in the private registry
  local lf_octype='secret'
  local lf_name='my-image-registry-secret'

  # check if secret already created
  mylog check "Checking ${lf_octype} ${lf_name} in ${MY_BACKEND_NAMESPACE}"
  if oc -n ${MY_BACKEND_NAMESPACE} get ${lf_octype} ${lf_name} >/dev/null 2>&1; then
    mylog ok
  else
    kubectl -n ${MY_BACKEND_NAMESPACE} create secret docker-registry my-image-registry-secret \
      --docker-server=${MY_IMAGE_REGISTRY} \
      --docker-username=${MY_IMAGE_REGISTRY_USERNAME} \
      --docker-password=${MY_IMAGE_REGISTRY_PASSWORD} \
      --docker-email=${MY_USER_EMAIL}
  fi

  # Build and create image, then load it into registry, this is optional because images won't change very often
  if $MY_OPENLIBERTY_CUSTOM; then
    pushd ${OPENLIBERTY_SCRIPTDIR}system

    # Build the image
    if $MY_OPENLIBERTY_CUSTOM_BUILD; then
      mylog info "==== Compile code and build docker image." 1>&2
      ## compile_code
      mvn clean install
      ## olp_build_image
      mylog info "Build docker image oljaxrs:1.0"
      docker build -t oljaxrs:1.0 .
    fi

    ## prepare_internal_registry
    ## get_login_token
    mylog info "Login to docker registry"
    docker login -u $MY_IMAGE_REGISTRY_USERNAME -p $MY_IMAGE_REGISTRY_PASSWORD $MY_IMAGE_REGISTRY
    ibmcloud cr login --client docker -u myappscreds -p $MY_IMAGE_REGISTRY_PASSWORD $MY_IMAGE_REGISTRY

    ## push_image_to_registry
    mylog info "Push image to ${MY_IMAGE_REGISTRY}"
    # olo1 is a namespace that belongs to me, in my private registry
    docker image tag oljaxrs:1.0 ${MY_IMAGE_REGISTRY}/${MY_IMAGE_REGISTRY_NS1}/oljaxrs:1.0
    docker push ${MY_IMAGE_REGISTRY}/${MY_IMAGE_REGISTRY_NS1}/oljaxrs:1.0
    # Check everything is correct
    # docker images
    # ibmcloud cr login --client docker
    # ibmcloud cr image-inspect de.icr.io/${MY_IMAGE_REGISTRY_NS1}/oljaxrs:1.0
    popd
  fi

  # Deploy the image in the $MY_BACKEND_NAMESPACE namespace 
  ## create_application
  adapt_file ${OPENLIBERTY_SCRIPTDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ system-appdeploy.yaml
  kubectl -n ${MY_BACKEND_NAMESPACE} apply -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/system-appdeploy.yaml
  # kubectl run <service_name> --image=de.icr.io/olo1/oljaxrs
  # kubectl -n ${MY_BACKEND_NAMESPACE} get OpenLibertyApplications
  # kubectl -n ${MY_BACKEND_NAMESPACE} describe olapps/mysystem
fi

duration=$SECONDS
ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2