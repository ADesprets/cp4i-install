#!/bin/bash
# Main program to install CP4I end to end with customisation
# Laurent 2021
# Updated July 2023 Saad / Arnauld
################################################
# @param $1 cp4i.properties file path
# @param $2 namespace
# @param $3 cluster_name
################################################
################################################
# Create openshift cluster using classic infrastructure
function create_openshift_cluster_classic() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:create_openshift_cluster_classic"

  SECONDS=0
  var_fail sc_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $sc_cluster_name"
  if ibmcloud ks cluster get --cluster $sc_cluster_name >/dev/null 2>&1; then
    mylog ok ", cluster exists"
    mylog info "Checking Openshift cluster took: $SECONDS seconds." 1>&2
  else
    mylog warn ", cluster does not exist"
    var_fail MY_OC_VERSION 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
    var_fail MY_CLUSTER_ZONE 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider classic'
    var_fail MY_CLUSTER_FLAVOR_CLASSIC 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $MY_CLUSTER_ZONE'
    var_fail MY_CLUSTER_WORKERS 'Speficy number of worker nodes in cluster'
    mylog info "Getting current version for OC: $MY_OC_VERSION"
    oc_version_full=$(check_openshift_version $MY_OC_VERSION)
    decho "oc_version_full=$oc_version_full"

    if [ -z "$oc_version_full" ]; then
      mylog error "Failed to find full version for ${MY_OC_VERSION}" 1>&2
      #fix_oc_version
      decho "F:OUT:create_openshift_cluster_classic"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
    oc_version_full=$(echo "[$oc_version_full]" | jq -r '.[] | (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) + "_openshift"')
    mylog info "Found: ${oc_version_full}"
    # create
    mylog info "Creating OpenShift cluster: $sc_cluster_name"

    SECONDS=0
    vlans=$(ibmcloud ks vlan ls --zone $MY_CLUSTER_ZONE --output json | jq -j '.[]|" --" + .type + "-vlan " + .id')
    if ! ibmcloud ks cluster create classic \
      --name $sc_cluster_name \
      --version $oc_version_full \
      --zone $MY_CLUSTER_ZONE \
      --flavor $MY_CLUSTER_FLAVOR_CLASSIC \
      --workers $MY_CLUSTER_WORKERS \
      --entitlement cloud_pak \
      --disable-disk-encrypt \
      $vlans; then
      mylog error "Failed to create cluster" 1>&2
      decho "F:OUT:create_openshift_cluster_classic"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
    mylog info "Creation of the cluster took: $SECONDS seconds." 1>&2
  fi

  decho "F:OUT:create_openshift_cluster_classic"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create openshift cluster using VPC infra
# use terraform because creation is more complex than classic
function create_openshift_cluster_vpc() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:create_openshift_cluster_vpc"

  # check vars from config file
  var_fail MY_OC_VERSION 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
  var_fail MY_CLUSTER_ZONE 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider vpc-gen2'
  var_fail MY_CLUSTER_FLAVOR_VPC 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $MY_CLUSTER_ZONE'
  var_fail MY_CLUSTER_WORKERS 'Speficy number of worker nodes in cluster'
  # set variables for terraform
  export TF_VAR_ibmcloud_api_key="$MY_IC_APIKEY"
  export TF_VAR_openshift_worker_pool_flavor="$MY_CLUSTER_FLAVOR_VPC"
  export TF_VAR_prefix="$MY_OC_PROJECT"
  export TF_VAR_region="$MY_CLUSTER_REGION"
  export TF_VAR_openshift_version=$(ibmcloud ks versions -q --show-version OpenShift | sed -Ene "s/^(${MY_OC_VERSION//./\\.}\.[^ ]*) .*$/\1/p")
  export TF_VAR_resource_group="rg-$MY_OC_PROJECT"
  export TF_VAR_openshift_cluster_name="$sc_cluster_name"
  pushd terraform
  terraform init
  terraform apply -var-file=var_override.tfvars
  popd

  decho "F:OUT:create_openshift_cluster_vpc"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
function add_ibm_entitlement() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:add_ibm_entitlement"

  local lf_in_ns=$1

  mylog check "Checking ibm-entitlement-key in $lf_in_ns"
  if oc -n $lf_in_ns get secret ibm-entitlement-key >/dev/null 2>&1; then
    mylog ok
  else
    var_fail MY_ENTITLEMENT_KEY "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    $MY_CONTAINER_ENGINE -h >/dev/null 2>&1
    if test $? -eq 0 && ! echo $MY_ENTITLEMENT_KEY | $MY_CONTAINER_ENGINE login cp.icr.io --username cp --password-stdin; then
      mylog error "Invalid entitlement key" 1>&2
      decho "F:OUT:add_ibm_entitlement"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $lf_in_ns"
    if ! oc -n $lf_in_ns create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io; then
      decho "F:OUT:add_ibm_entitlement"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
  fi

  decho "F:OUT:add_ibm_entitlement"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# start customization
# Takes all the templates associated with the capabilities and generate the files from the context variables
# The files are generated into ./customisation/working/<capability>/config
# @param ns namespace where operands were instantiated
function start_customization() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:start_customization"

  local ns=$1
  local varb64

  mylog info "Copy template files to the working directory"

  decho "F:OUT:start_customization"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# launch customization
# Takes all the templates associated with the capabilities and generate the files from the context variables
# The files are generated into ./customisation/working/<capability>/config
# @param ns namespace where operands were instantiated
# TODO Check if we nned this one
function launch_customization() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:launch_customization"

  local ns=$1

  mylog info "Customisation of the capabilities"
  decho "F:OUT:launch_customization"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# TBC
function create_openshift_cluster() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:create_openshift_cluster"

  var_fail MY_CLUSTER_INFRA 'mylog warn "Choose one of: classic or vpc" 1>&2'
  case "${MY_CLUSTER_INFRA}" in
  classic)
    create_openshift_cluster_classic
    sc_ingress_hostname_filter=.ingressHostname
    sc_cluster_url_filter=.serverURL
    ;;
  vpc)
    create_openshift_cluster_vpc
    sc_ingress_hostname_filter=.ingress.hostname
    sc_cluster_url_filter=.masterURL
    ;;
  *)
    mylog error "Only classic and vpc for MY_CLUSTER_INFRA"
    ;;
  esac

  decho "F:OUT:create_openshift_cluster"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# wait for Cluster availability
# set variable my_cluster_url
function wait_for_cluster_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:wait_for_cluster_availability"

  SECONDS=0
  wait_for_state 'Cluster state' 'normal-All Workers Normal' "ibmcloud oc cluster get --cluster $sc_cluster_name --output json|jq -r '(.state + \"-\" + .status)'"
  mylog info "Checking Cluster state took: $SECONDS seconds." 1>&2

  SECONDS=0
  mylog check "Checking Cluster URL"
  my_cluster_url=$(ibmcloud ks cluster get --cluster $sc_cluster_name --output json | jq -r "$sc_cluster_url_filter")
  case "$my_cluster_url" in
  https://*)
    mylog ok " -> $my_cluster_url"
    mylog info "Checking Cluster availability took: $SECONDS seconds." 1>&2
    ;;
  *)
    mylog error "Error getting cluster URL for $sc_cluster_name" 1>&2
    decho "F:OUT:wait_for_cluster_availability"
    SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
    exit 1
    ;;
  esac

  decho "F:OUT:wait_for_cluster_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# wait for ingress address availability
function wait_4_ingress_address_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:wait_4_ingress_address_availability"

  SECONDS=0
  local lf_ingress_address

  mylog check "Checking Ingress address"
  firsttime=true
  case $MY_CLUSTER_INFRA in
  classic)
    sc_ingress_hostname_filter=.ingressHostname
    ;;
  vpc)
    sc_ingress_hostname_filter=.ingress.hostname
    ;;
  *)
    mylog error "Only classic and vpc for MY_CLUSTER_INFRA"
    ;;
  esac

  while true; do
    lf_ingress_address=$(ibmcloud ks cluster get --cluster $sc_cluster_name --output json | jq -r "$sc_ingress_hostname_filter")
    if test -n "$lf_ingress_address"; then
      mylog ok ", $lf_ingress_address"
      break
    fi
    if $firsttime; then
      mylog warn "not ready"
      firsttime=false
    fi
    mylog wait "waiting for ingress address"
    # It takes about 15 minutes (21 Aug 2023)
    sleep 90
  done
  mylog info "Checking Ingress availability took $SECONDS seconds to execute." 1>&2

  decho "F:OUT:wait_4_ingress_address_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################################
# Create openshift cluster if it does not exist
# and wait for both availability of the cluster and the ingress address
function create_openshift_cluster_wait_4_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:create_openshift_cluster_wait_4_availability"

  if ! ${TECHZONE}; then
    # Create openshift cluster
    create_openshift_cluster

    # Wait for Cluster availability
    wait_for_cluster_availability

    # Wait for ingress address availability
    wait_4_ingress_address_availability
  fi

  decho "F:OUT:create_openshift_cluster_wait_4_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Add OpenLdap app to openshift
function install_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_openldap"

  if $MY_LDAP; then
    mylog info "==== Installing OpenLdap." 1>&2
    local lf_type="deployment"
    local lf_name="openldap"

    read_config_file "${YAMLDIR}ldap/ldap.properties"

    # create namespace if needed
    create_namespace ${MY_LDAP_NAMESPACE}

    #SB]20231207 checks if used directories and files exists
    check_file_exist ${YAMLDIR}ldap/ldap-pvc.main.yaml
    check_file_exist ${YAMLDIR}ldap/ldap-pvc.config.yaml
    check_file_exist ${YAMLDIR}ldap/ldap-config.json
    check_file_exist ${YAMLDIR}ldap/ldap-users.ldif

    provision_persistence_openldap ${MY_LDAP_NAMESPACE}
    deploy_openldap ${lf_type} ${lf_name} ${MY_LDAP_NAMESPACE}
    expose_service_openldap ${lf_name} ${MY_LDAP_NAMESPACE}
  fi

  decho "F:OUT:install_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise ldap adding users and groups
function customise_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_openldap"

  if $MY_LDAP_CUSTOM; then
    mylog info "==== Customise ldap." 1>&2
    read_config_file "${YAMLDIR}ldap/ldap.properties"
    check_file_exist ${YAMLDIR}ldap/ldap-config.json
    check_file_exist ${YAMLDIR}ldap/ldap-users.ldif
  fi

  decho "F:OUT:customise_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Add mailhog app to openshift
# Port is hard coded to 8025 and is defined by mailhog (default port)
function install_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_mailhog"

  if $MY_MAILHOG; then
    mylog info "==== Installing mailhog (server and client)." 1>&2
    local lf_type="deployment"
    local lf_name="mailhog"

    # May need some properties
    # read_config_file "${YAMLDIR}ldap/ldap.properties"

    # create namespace if needed
    create_namespace ${MY_MAIL_SERVER_NAMESPACE}

    deploy_mailhog ${lf_type} ${lf_name} ${MY_MAIL_SERVER_NAMESPACE}
    expose_service_mailhog ${lf_name} ${MY_MAIL_SERVER_NAMESPACE} '8025'
  fi

  decho "F:OUT:install_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Display information to access CP4I
function display_access_info() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN  :display_access_info"

  mylog info "==== Displaying Access Info to CP4I." 1>&2
  # Temporary access with Keycloack
  temp_integration_admin_pwd=$(oc -n $MY_COMMON_SERVICES_NAMESPACE get secret integration-admin-initial-temporary-credentials -o jsonpath={.data.password} | base64 -d)
  mylog info "Integration admin password: ${temp_integration_admin_pwd}"

  mailhog_hostname=$(oc -n ${MY_MAIL_SERVER_NAMESPACE} get route mailhog -o jsonpath='{.spec.host}')
  mylog info "MailHog accessible at http://${mailhog_hostname}"

  if $MY_NAVIGATOR_INSTANCE; then
    get_navigator_access
  fi

  if $MY_ACE; then
    ace_ui_db_url=$(oc -n $MY_OC_PROJECT get Dashboard -o=jsonpath='{.items[?(@.kind=="Dashboard")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Dahsboard UI endpoint: " $ace_ui_db_url
    ace_ui_dg_url=$(oc -n $MY_OC_PROJECT get DesignerAuthoring -o=jsonpath='{.items[?(@.kind=="DesignerAuthoring")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Designer UI endpoint: " $ace_ui_dg_url
  fi

  if $MY_APIC; then
    gtw_url=$(oc -n $MY_OC_PROJECT get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "APIC Gateway endpoint: ${gtw_url}"
    apic_gtw_admin_pwd_secret_name=$(oc -n $MY_OC_PROJECT get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].spec.adminUser.secretName}')
    cm_admin_pwd=$(oc -n $MY_OC_PROJECT get secret ${apic_gtw_admin_pwd_secret_name} -o jsonpath={.data.password} | base64 -d)
    mylog info "APIC Gateway admin password: ${cm_admin_pwd}"
    cm_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "APIC Cloud Manager endpoint: ${cm_url}"
    cm_admin_pwd_secret_name=$(oc -n $MY_OC_PROJECT get ManagementCluster -o=jsonpath='{.items[?(@.kind=="ManagementCluster")].spec.adminUser.secretName}')
    cm_admin_pwd=$(oc -n $MY_OC_PROJECT get secret ${cm_admin_pwd_secret_name} -o jsonpath='{.data.password}' | base64 -d)
    mylog info "APIC Cloud Manager admin password: ${cm_admin_pwd}"
    mgr_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "APIC API Manager endpoint: ${mgr_url}"
    ptl_url=$(oc -n $MY_OC_PROJECT get PortalCluster -o=jsonpath='{.items[?(@.kind=="PortalCluster")].status.endpoints[?(@.name=="portalWeb")].uri}')
    mylog info "APIC Web Portal root endpoint: ${ptl_url}"
  fi

  if $MY_EEM; then
    eem_ui_url=$(oc -n $MY_OC_PROJECT get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Endpoint Management UI endpoint: ${eem_ui_url}"
    eem_gtw_url=$(oc -n $MY_OC_PROJECT get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "Event Endpoint Management Gateway endpoint: ${eem_gtw_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi

  if $MY_ES; then
    es_ui_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Streams Management UI endpoint: ${es_ui_url}"
    es_admin_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "Event Streams Management admin endpoint: ${es_admin_url}"
    es_apicurioregistry_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="apicurioregistry")].uri}')
    mylog info "Event Streams Management apicurio registry endpoint: ${es_apicurioregistry_url}"
    es_restproducer_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="restproducer")].uri}')
    mylog info "Event Streams Management REST Producer endpoint: ${es_restproducer_url}"
    es_bootstrap_urls=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.kafkaListeners[*].bootstrapServers}')
    mylog info "Event Streams Bootstraps servers endpoints: ${es_bootstrap_urls}"
  fi

  if $MY_LDAP; then
    mylog info "LDAP info"
  fi

  if $MY_ASSETREPO; then
    mylog info "AR info"
  fi

  if $MY_DPGW; then
    mylog info "DataPower info"
  fi

  if $MY_MQ; then
    mylog info "MQ info"
  fi

  if $MY_LIC_SRV; then
    licensing_service_url=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-licensing-service-instance")].spec.host}')
    mylog info "Licensing service endpoint: ${licensing_service_url}"
  fi

  decho "F:OUT:display_access_info"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# SB]20231215
# SB]20231130 patcher les foundational services en acceptant la license
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm
# 3.Setting the hardware profile and accepting the license
# License: Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
function accept_license_fs() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:accept_license_fs"

  lf_in_namespace=$1

  local accept
  decho "oc -n ${lf_in_namespace} get commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} -o jsonpath='{.spec.license.accept}'"
  accept=$(oc -n ${lf_in_namespace} get commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} -o jsonpath='{.spec.license.accept}')
  decho "accept=$accept"
  if [ "$accept" == "true" ]; then
    mylog info "license already accepted." 1>&2
  else
    oc -n ${lf_in_namespace} patch commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} --type merge -p '{"spec": {"license": {"accept": true}}}'
  fi

  decho "F:OUT:accept_license_fs"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Log in IBM Cloud
function login_2_ibm_cloud() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:login_2_ibm_cloud"

  if ! ${TECHZONE}; then
    SECONDS=0

    if ibmcloud resource groups -q >/dev/null 2>&1; then
      mylog info "user already logged to IBM Cloud."
    else
      mylog info "user not logged to IBM Cloud." 1>&2
      var_fail MY_IC_APIKEY "Create and save API key JSON file from: https://cloud.ibm.com/iam/apikeys"
      mylog check "Login to IBM Cloud"
      if ! ibmcloud login -q --no-region --apikey $MY_IC_APIKEY >/dev/null; then
        mylog error "Fail to login to IBM Cloud, check API key: $MY_IC_APIKEY" 1>&2
        decho "F:OUT:login_2_ibm_cloud"
        SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
        exit 1
      else
        mylog ok
        mylog info "Connecting to IBM Cloud took: $SECONDS seconds." 1>&2
      fi
    fi
  fi

  decho "F:OUT:login_2_ibm_cloud"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
# requires var my_cluster_url
function login_2_openshift_cluster() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:login_2_openshift_cluster"

  SECONDS=0

  if oc whoami >/dev/null 2>&1; then
    mylog info "user already logged to openshift cluster."
  else
    if $TECHZONE; then
      oc login -u ${MY_TECHZONE_USERNAME} -p ${MY_TECHZONE_PASSWORD} ${MY_TECHZONE_OPENSHIFT_API_URL}
    else
      mylog check "Login to cluster"
      # SB 20231208 The following command sets your command line context for the cluster and download the TLS certificates and permission files for the administrator.
      # more details here : https://cloud.ibm.com/docs/openshift?topic=openshift-access_cluster#access_public_se
      ibmcloud ks cluster config --cluster ${sc_cluster_name} --admin
      while ! oc login -u apikey -p $MY_IC_APIKEY --server=$my_cluster_url >/dev/null; do
        mylog error "$(date) Fail to login to Cluster, retry in a while (login using web to unblock)" 1>&2
        sleep 30
      done
      mylog ok
      mylog info "Logging to Cluster took: $SECONDS seconds." 1>&2
    fi
  fi

  decho "F:OUT:login_2_openshift_cluster"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install GitOps
function install_gitops() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_gitops"

  # https://docs.openshift.com/gitops/1.12/installing_gitops/installing-openshift-gitops.html

  #mylog info "==== Redhat Openshift GitOps." 1>&2
  #create_namespace $MY_GITOPS_NAMESPACE
  # Error: Checking project openshift-gitops-operator...Creating project openshift-gitops-operator
  #        Error from server (Forbidden): project.project.openshift.io "openshift-gitops-operator" is forbidden: cannot request a project starting with "openshift-"
  # Le problème provient aussi d'une certaine confusion concernant le ns dans lequel cet operateur doit être installé : openshift-operators ou openshift-gitops-operator
  # Le ns openshift-gitops-operator n'est pas crée automatiquement dans le cluster comme l'est openshift-operators !!!
  # L'installation depuis la console à partir de "OperatorHub", crée le ns openshift-gitops-operator et si on supprime l'operator et qu'on relance le script : cette fois-ci
  # ça fonctionne parceque le ns opeshift-gitops-operator existe.
  # Après j'ai essayé de suivre dans la mesure du possible la procédure https://github.com/IBM/cloudpak-gitops/blob/main/docs/install.md

  #ls_type="OperatorGroup"
  #ls_cr_name="${MY_GITOPS_OPERATORGROUP}"
  #ls_yaml_file="${RESOURCSEDIR}operator-group-gitops.yaml"
  #ls_namespace=$MY_GITOPS_NAMESPACE
  #check_create_oc_yaml "${ls_type}" "${ls_cr_name}" "${ls_yaml_file}" "${ls_namespace}"

  lf_operator_name="$MY_GITOPS_OPERATORGROUP"
  lf_catalog_source_name="redhat-operators"
  lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  lf_strategy="Automatic"
  lf_wait_for_state=1
  lf_csv_name=$MY_GITOPS_CSV_NAME
  decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho "F:OUT:install_gitops"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Cert Manager
function install_cert_manager() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_cert_manager"

  mylog info "==== Redhat Cert Manager catalog." 1>&2
  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="redhat-operators"
  lf_catalogsource_dspname="Red Hat Operators"
  lf_catalogsource_image="registry.redhat.io/redhat/redhat-operator-index:v4.12"
  lf_catalogsource_publisher="Red Hat"
  lf_catalogsource_interval="10m"
  decho "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
  create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

  # SB]20231215 Pour obtenir le template de l'operateur cert-manager de Redhat, je l'ai installé avec la console, j'ai récupéré le Yaml puis désinstallé.
  lf_operator_name="openshift-cert-manager-operator"
  lf_catalog_source_name="redhat-operators"
  lf_operator_namespace=$MY_CERT_MANAGER_NAMESPACE
  lf_strategy="Automatic"
  lf_wait_for_state=1
  lf_csv_name=$MY_CERT_MANAGER_CSV_NAME
  decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho "F:OUT:install_cert_manager"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Licensing Server
function install_lic_srv() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_lic_srv"

  # ibm-license-server
  if $MY_LIC_SRV; then
    mylog info "==== IBM License Server." 1>&2
    check_add_cs_ibm_pak ibm-licensing MY_LIC_SRV_CASE amd64

    #mylog info "==== Adding Licensing service catalog source in ns : openshift-marketplace." 1>&2
    lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
    lf_catalogsource_name="ibm-licensing-catalog"
    lf_catalogsource_dspname="ibm-licensing"
    lf_catalogsource_image="icr.io/cpopen/ibm-licensing-catalog"
    lf_catalogsource_publisher="IBM"
    lf_catalogsource_interval="45m"
    decho "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
    create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

    # ATTENTION : pour le licensing server ajouter dans la partie spec.startingCSV: ibm-licensing-operator.v4.2.1 (sinon erreur).
    lf_operator_name="ibm-licensing-operator-app"
    lf_catalog_source_name="ibm-licensing-catalog"
    lf_operator_namespace=$MY_LICENSE_SERVER_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_LIC_SRV_CSV_NAME
    decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

  decho "F:OUT:install_lic_srv"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

############################################################################################################################################
#SB]20231214 Installing Foundational services v4.3
# Referring to https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=whats-new-in-cloud-pak-integration-202341
# "The IBM Cloud Pak foundational services operator is no longer installed automatically.
#  Install this operator manually if you need to create an instance that uses identity and access management.
#  Also, make sure you have a certificate manager; otherwise, the IBM Cloud Pak foundational services operator installation will not complete."
# This function implements the following steps described here :
############################################################################################################################################
function install_fs() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_fs"

  mylog info "==== IBM Common Services." 1>&2
  # ibm-cp-common-services
  check_add_cs_ibm_pak ibm-cp-common-services MY_COMMONSERVICES_CASE amd64

  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="opencloud-operators"
  lf_catalogsource_dspname="IBMCS Operators"
  lf_catalogsource_image="icr.io/cpopen/ibm-common-service-catalog:4.3"
  lf_catalogsource_publisher="IBM"
  lf_catalogsource_interval="45m"
  decho "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
  create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

  # Pour les operations suivantes : utiliser un seul namespace
  #lf_namespace=$MY_COMMON_SERVICES_NAMESPACE
  lf_operator_namespace=$MY_OPERATORS_NAMESPACE

  #create_operator_subscription "ibm-common-service-operator" $MY_COMMONSERVICES_CHL "opencloud-operators" $MY_COMMON_SERVICES_NAMESPACE "Automatic" $MY_STARTING_CSV
  lf_operator_name="ibm-common-service-operator"
  lf_catalog_source_name="opencloud-operators"
  #lf_operator_namespace=$MY_COMMON_SERVICES_NAMESPACE
  lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  lf_strategy="Automatic"
  lf_wait_for_state=1
  lf_csv_name=$MY_COMMONSERVICES_CSV_NAME
  decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

  ## Setting hardware  Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
  #accept_license_fs $MY_OPERATORS_NAMESPACE
  accept_license_fs $lf_operator_namespace

  # Configuring foundational services by using the CommonService custom resource.
  lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  lf_type="CommonService"
  lf_cr_name=$MY_COMMONSERVICES_INSTANCE_NAME
  lf_yaml_file="${RESOURCSEDIR}foundational-services-cr.yaml"
  decho "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

  decho "F:OUT:install_fs"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Navigator (depending on two boolean)
function install_navigator() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_navigator"

  ## ibm-integration-platform-navigator
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  # Creating Navigator operator subscription
  if $MY_NAVIGATOR; then
    mylog info "==== Installing Navigator." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-integration-platform-navigator MY_NAVIGATOR_CASE amd64

    # Creating Navigator operator subscription
    lf_operator_name="ibm-integration-platform-navigator"
    lf_catalog_source_name="ibm-integration-platform-navigator-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_NAVIGATOR_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

  if $MY_NAVIGATOR_INSTANCE; then
    # Creating Navigator instance
    lf_file="${OPERANDSDIR}Navigator-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_NAVIGATOR_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="PlatformNavigator"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_navigator"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Integration Assembly
function install_intassembly() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_intassembly"

  # Creating Integration Assembly instance
  if $MY_INTASSEMBLY; then
    mylog info "==== Installing Integration Assembly." 1>&2
    lf_file="${OPERANDSDIR}IntegrationAssembly-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_INTASSEMBLY_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IntegrationAssembly"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_intassembly"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Asset Repository
function install_assetrepo() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_assetrepo"

  if $MY_ASSETREPO; then
    mylog info "==== Installing Asset Repository." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-integration-asset-repository MY_ASSETREPO_CASE amd64

    # Creating Asset Repository operator subscription
    lf_operator_name="ibm-integration-asset-repository"
    lf_catalog_source_name="ibm-integration-asset-repository-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_ASSETREPO_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating Asset Repository instance
    lf_file="${OPERANDSDIR}AR-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_ASSETREPO_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="AssetRepository"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_assetrepo"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install ACE
function install_ace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_ace"

  # ibm-appconnect
  if $MY_ACE; then
    mylog info "==== Installing ACE." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-appconnect MY_ACE_CASE amd64

    # Creating ACE operator subscription
    lf_operator_name="ibm-appconnect"
    lf_catalog_source_name="appconnect-operator-catalogsource"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_csv_name=$MY_ACE_CSV_NAME
    lf_wait_for_state=1
    decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating ACE Dashboard instance
    lf_file="${OPERANDSDIR}ACE-Dashboard-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DASHBOARD_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="Dashboard"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Creating ACE Designer instance
    lf_file="${OPERANDSDIR}ACE-Designer-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DESIGNER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="DesignerAuthoring"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_ace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise ACE
function customise_ace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_ace"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_ACE_CUSTOM; then
    mylog info "==== Customise ACE." 1>&2
    . ${ACE_SCRIPTDIR}scripts/ace.config.sh
  fi

  decho "F:OUT:customise_ace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install APIC
function install_apic() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_apic"

  # ibm-apiconnect
  if $MY_APIC; then
    mylog info "==== Installing APIC." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-apiconnect MY_APIC_CASE amd64

    # Creating APIC operator subscription
    lf_operator_name="ibm-apiconnect"
    lf_catalog_source_name="ibm-apiconnect-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_APIC_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating APIC instance
    lf_file="${OPERANDSDIR}APIC-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_APIC_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="APIConnectCluster"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    save_certificate ${MY_OC_PROJECT} cp4i-apic-ingress-ca ${WORKINGDIR}
    save_certificate ${MY_OC_PROJECT} cp4i-apic-gw-gateway ${WORKINGDIR}
  fi

  decho "F:OUT:install_apic"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise APIC
function customise_apic() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_apic"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_APIC_CUSTOM; then
    mylog info "==== Customise APIC." 1>&2
    . ${APIC_SCRIPTDIR}scripts/apic.config.sh
  fi

  decho "F:OUT:customise_apic"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Open Liberty
function install_openliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_openliberty"

  # backend J2EE applications
  if $MY_OPENLIBERTY; then
    mylog info "==== Installing OPEN Liberty." 1>&2

    create_namespace $MY_BACKEND_NAMESPACE

    # TODO other approach is to use the catalog which already inludes the Open Liberty operator and use a subscription
    # Case exists 1.3.1, and IBM/RedHat Catalog

    export OPEN_LIBERTY_OPERATOR_NAMESPACE=$MY_BACKEND_NAMESPACE
    export OPEN_LIBERTY_OPERATOR_WATCH_NAMESPACE=$MY_BACKEND_NAMESPACE

    # TODO Check that is this value
    export WATCH_NAMESPACE='""'
    adapt_file ${OPENLIBERTY_SCRIPTDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-rbac-watch-all.yaml
    adapt_file ${OPENLIBERTY_SCRIPTDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-crd.yaml
    adapt_file ${OPENLIBERTY_SCRIPTDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-operator.yaml

    # Creating Open Liberty operator subscription (Check arbitrarely one resource, the deployment of the operator)
    local lf_octype='deployment'
    local lf_name='olo-controller-manager'

    # check if deployment of the operator already performed
    mylog check "Checking ${lf_octype} ${lf_name} in ${MY_BACKEND_NAMESPACE}"
    if oc -n ${MY_BACKEND_NAMESPACE} get ${lf_octype} ${lf_name} >/dev/null 2>&1; then
      mylog ok
    else
      oc apply --server-side -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml
      oc apply -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml
      oc apply -n ${MY_BACKEND_NAMESPACE} -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml
    fi

  fi

  decho "F:OUT:install_openliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Open Liberty
function customise_openliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_openliberty"

  if $MY_OPENLIBERTY_CUSTOM; then
  mylog info "==== Customise Open Liberty." 1>&2
    . ${OPENLIBERTY_SCRIPTDIR}scripts/olp.config.sh
  fi
  decho "F:OUT:customise_openliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}


################################################
# Install WebSphere Liberty
function install_wasliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_wasliberty"

  if $MY_WASLIBERTY; then

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-websphere-liberty MY_WL_CASE amd64

    # Creating WebSphere Liberty operator subscription
    lf_operator_name="ibm-websphere-liberty"
    lf_catalog_source_name="ibm-websphere-liberty-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_WL_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

  decho "F:OUT:install_wasliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise WebSphere Liberty
function customise_wasliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_wasliberty"

  if $MY_WASLIBERTY_CUSTOM; then
  mylog info "==== Customise WAS Liberty." 1>&2
    . ${WASLIBERTY_SCRIPTDIR}scripts/was.config.sh
  
  fi

  decho "F:OUT:customise_wasliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install DataPower Gateway
function install_dpgw() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_dpgw"

  # add catalog sources using ibm_pak plugin
  check_add_cs_ibm_pak ibm-websphere-liberty MY_WL_CASE amd64

  # Creating MQ operator subscription
  lf_operator_name="ibm-websphere-liberty"
  lf_catalog_source_name="ibmmq-operator-catalogsource"
  lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  lf_strategy="Automatic"
  lf_wait_for_state=1
  lf_csv_name=$MY_MQ_CSV_NAME
  create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"


  # Creating DP Gateway operator subscription
  if $MY_DPGW; then
    check_add_cs_ibm_pak ibm-datapower-operator MY_DPGW_CASE amd64

    lf_operator_name="datapower-operator"
    lf_catalog_source_name="ibm-datapower-operator-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_DPGW_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

  decho "F:OUT:install_dpgw"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install EEM
function install_eem() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_eem"

  local lf_in_ns=$1
  local varb64

  if $MY_EEM; then
    mylog info "==== Installing Event Endpoint Management." 1>&2
    ## event endpoint management
    ## to get the name of the pak to use : oc ibm-pak list
    ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
    check_add_cs_ibm_pak ibm-eventendpointmanagement MY_EEM_CASE amd64
    #oc -n $lf_in_ns ibm-pak launch ibm-eventendpointmanagement --version $MY_EEM_CASE --inventory eemOperatorSetup --action installCatalog

    # Creating Event Endpoint Management operator subscription
    lf_operator_name="ibm-eventendpointmanagement"
    lf_catalog_source_name="ibm-eventendpointmanagement-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_EEM_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating EventEndpointManager instance (Event Processing)
    lf_file="${OPERANDSDIR}EEM-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EEM_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventEndpointManagement"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    ## Creating EEM users and roles
    # generate properties files
    adapt_file ${EEM_SCRIPTDIR}config/ ${EEM_GEN_CUSTOMDIR}config/ user-credentials.yaml
    adapt_file ${EEM_SCRIPTDIR}config/ ${EEM_GEN_CUSTOMDIR}config/ user-roles.yaml

    # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
    # user credentials
    varb64=$(cat "${EEM_GEN_CUSTOMDIR}config/user-credentials.yaml" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]"
    # user roles
    varb64=$(cat "${EEM_GEN_CUSTOMDIR}config/user-roles.yaml" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]"
  fi
  
  decho "F:OUT:install_eem"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise EEM
function customise_eem() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_eem"

  if $MY_EEM_CUSTOM; then
    mylog info "==== Customise Event Endpoint Management." 1>&2

    # launch custom script
    mylog info "Customise EEM"
  fi

  decho "F:OUT:customise_eem"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}
################################################
# Install EGW
function install_egw() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_egw"

  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW; then
    mylog info "==== Installing Event Endpoint Gateway." 1>&2
    export MY_EEM_MANAGER_GATEWAY_ROUTE=$(oc -n $MY_OC_PROJECT get eem $MY_EEM_INSTANCE_NAME -o jsonpath='{.status.endpoints[1].uri}')

    lf_file="${OPERANDSDIR}EG-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EGW_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventGateway"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_egw"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise EGW
function customise_egw() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_egw"

  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW_CUSTOM; then
    mylog info "==== Customise Event Endpoint Gateway." 1>&2

  fi

  decho "F:OUT:customise_egw"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install EP
function install_ep() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_ep"

  local lf_in_ns=$1
  local varb64

  if $MY_EP; then
    mylog info "==== Installing Event Processing." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-eventprocessing MY_EP_CASE amd64
    #oc -n  $lf_in_ns ibm-pak launch ibm-eventprocessing --version $MY_EP_CASE --inventory epOperatorSetup --action installCatalog

    ## Creating Event processing operator subscription
    lf_operator_name="ibm-eventprocessing"
    lf_catalog_source_name="ibm-eventprocessing-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_EP_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    ## SB]20231023 to check the status of Event processing : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The Status column displays the current state of the EventProcessing custom resource.
    ## When the Event Processing instance is ready, the phase displays Phase: Running.
    ## Creating EventProcessing instance (Event Processing)
    ## oc -n <namespace> get eventprocessing <instance-name> -o jsonpath='{.status.phase}'
    ## Creating Event processing instance
    lf_file="${OPERANDSDIR}EP-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_EP_INSTANCE_NAME"
    lf_state="Running"
    lf_type="EventProcessing"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # generate properties files
    adapt_file ${EP_SCRIPTDIR}config/ ${EP_GEN_CUSTOMDIR}config/ user-credentials.yaml
    adapt_file ${EP_SCRIPTDIR}config/ ${EP_GEN_CUSTOMDIR}config/ user-roles.yaml

    # user credentials
    varb64=$(cat "${EP_GEN_CUSTOMDIR}config/user-credentials.yaml" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]"

    # user roles
    varb64=$(cat "${EP_GEN_CUSTOMDIR}config/user-roles.yaml" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]"
  fi

  decho "F:OUT:install_ep"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise EP
function customise_ep() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_ep"

  local lf_in_ns=$1
  local varb64

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  ## Creating Event Processing users and roles
  if $MY_EP_CUSTOM; then
    mylog info "==== Customise Event Endpoint Processing." 1>&2
    # launch custom script
    mylog info "Customise Event Processing"
  fi

  decho "F:OUT:customise_ep"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install IBM Event streams
function install_es() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_es"

  # ibm-eventstreams
  if $MY_ES; then
    mylog info "==== Installing Event Streams." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-eventstreams MY_ES_CASE amd64

    # Creating EventStreams operator subscription
    lf_operator_name="ibm-eventstreams"
    lf_catalog_source_name="ibm-eventstreams"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_ES_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating Event Streams instance
    lf_file="${OPERANDSDIR}ES-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_ES_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventStreams"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_es"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise IBM Event streams
function customise_es() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_es"

  # start customization
  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config

  # Creating Eventstream topic,
  # SB]20231019
  # 2 options :
  #   Option1 : using the es plugin : cloudctl es topic-create.
  #   You have to install the ES plugin for ibmcloud command : cloudct.
  #   https://ibm.github.io/event-automation/es/installing/post-installation/#installing-the-event-streams-command-line-interface, part : IBM Cloud Pak CLI plugin (cloudctl es)
  #
  #   Option2 : using a yaml configuration file

  # SB]20231026 Creating :
  # - operands properties file,
  # - topics, ...
  if $MY_ES_CUSTOM; then
      mylog info "==== Customise Event Streams" 1>&2

    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    if [ ! -d ${ES_GEN_CUSTOMDIR}scripts ]; then
      mkdir -p ${ES_GEN_CUSTOMDIR}scripts
    fi
    if [ ! -d ${ES_GEN_CUSTOMDIR}config ]; then
      mkdir -p ${ES_GEN_CUSTOMDIR}config
    fi
    generate_files $ES_SCRIPTDIR $ES_GEN_CUSTOMDIR false

    # SB]20231211 https://ibm.github.io/event-automation/es/installing/installing/
    # Question : Do we have to create this configmap before installing ES or even after ? Used for monitoring
    lf_type="configmap"
    lf_cr_name="cluster-monitoring-config"
    lf_yaml_file="${RESOURCSEDIR}openshift-monitoring-cm.yaml"
    lf_namespace="openshift-monitoring"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
      . ${ES_SCRIPTDIR}scripts/es.config.sh
  fi

  decho "F:OUT:customise_es"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Flink
function install_flink() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_flink"

  local lf_in_ns=$1
  if $MY_FLINK; then
    mylog info "==== Installing Flink." 1>&2
    # add catalog sources using ibm_pak plugin
    ## SB]20231020 For Flink and Event processing first you have to apply the catalog source to your cluster :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter Applying catalog sources to your cluster
    # event flink
    check_add_cs_ibm_pak ibm-eventautomation-flink MY_FLINK_CASE amd64
    #oc -n $lf_in_ns ibm-pak launch ibm-eventautomation-flink --version $MY_FLINK_CASE --inventory flinkKubernetesOperatorSetup --action installCatalog

    ## SB]20231020 For Flink and Event processing install the operator with the following command :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter : Install the operator by using the CLI (oc ibm-pak)
    ## event flink
    ## Creating Eventautomation Flink operator subscription
    ## Creating Event processing operator subscription
    lf_operator_name="ibm-eventautomation-flink"
    lf_catalog_source_name="ibm-eventautomation-flink-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_FLINK_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    ## Creation of Event automation Flink PVC and instance
    # Even if it's a pvc we use the same generic function
    lf_file="${OPERANDSDIR}EA-Flink-PVC.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="ibm-flink-pvc"
    lf_state="Bound"
    lf_type="PersistentVolumeClaim"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    ## SB]20231023 to check the status of created Flink instance : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The status field displays the current state of the FlinkDeployment custom resource.
    ## When the Flink instance is ready, the custom resource displays status.lifecycleState: STABLE and status.jobManagerDeploymentStatus: READY.
    ## STANLE and READY (uppercase!!!)
    lf_file="${OPERANDSDIR}EA-Flink-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.lifecycleState}-{.status.jobManagerDeploymentStatus}"
    lf_resource="$MY_FLINK_INSTANCE_NAME"
    lf_state="STABLE-READY"
    lf_type="FlinkDeployment"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_flink"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Flink
function customise_flink() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_flink"

  local lf_in_ns=$1
  if $MY_FLINK_CUSTOM; then
    mylog info "==== Customise Flink." 1>&2
  fi

  decho "F:OUT:customise_flink"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}
################################################
# Install Aspera HSTS
function install_hsts() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_hsts"

  # ibm aspera hsts
  if $MY_HSTS; then
    mylog info "==== Installing HSTS." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-aspera-hsts-operator MY_HSTS_CASE amd64

    # Creating Aspera HSTS operator subscription
    lf_operator_name="aspera-hsts-operator"
    lf_catalog_source_name="aspera-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_HSTS_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    lf_file="${OPERANDSDIR}AsperaHSTS-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_HSTS_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IbmAsperaHsts"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_hsts"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Aspera HSTS
function customise_hsts() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_hsts"

  # ibm aspera hsts
  if $MY_HSTS_CUSTOM; then
    mylog info "==== Customise HSTS." 1>&2
  fi

  decho "F:OUT:customise_hsts"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install MQ
function install_mq() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_mq"

  # ibm-mq
  if $MY_MQ; then
    mylog info "==== Installing MQ." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-mq MY_MQ_CASE amd64

    # Creating MQ operator subscription
    lf_operator_name="ibm-mq"
    lf_catalog_source_name="ibmmq-operator-catalogsource"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_csv_name=$MY_MQ_CSV_NAME
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating MQ instance
    #lf_file="${OPERANDSDIR}MQ-Capability.yaml"
    #lf_ns="${MY_OC_PROJECT}"
    #lf_path="{.status.phase}"
    #lf_resource="$MY_MQ_INSTANCE_NAME"
    #lf_state="Running"
    #lf_type="QueueManager"
    #lf_wait_for_state=0
    #create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_mq"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise MQ
function customise_mq() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_mq"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_MQ_CUSTOM; then
    # launch custom script
    mylog info "==== Customise MQ." 1>&2
    . ${MQ_SCRIPTDIR}scripts/mq.config.sh -i ${sc_properties_file} ${sc_versions_file} ${MY_MQ_INSTANCE_NAME}
    #${MQ_SCRIPTDIR}scripts/mq.config.sh -i ${sc_properties_file} ${sc_versions_file} ${MY_MQ_INSTANCE_NAME}
  fi

  decho "F:OUT:customise_mq"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Instana
function install_instana() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:install_instana"

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA; then
    mylog info "==== Adding Instana." 1>&2
    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    lf_operator_name="instana-agent-operator"
    lf_catalog_source_name="certified-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_csv_name=$MY_INSTANA_CSV_NAME
    lf_wait_for_state=1
    create_namespace $MY_INSTANA_AGENT_NAMESPACE
    oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy add-scc-to-user privileged -z instana-agent
    create_operator_subscription "${lf_operator_name}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating Instana agent
    lf_file="${OPERANDSDIR}Instana-Agent-CloudIBM-Capability.yaml"
    lf_ns="${MY_INSTANA_AGENT_NAMESPACE}"
    lf_path="{.status.numberReady}"
    lf_resource="$MY_INSTANA_INSTANCE_NAME"
    lf_state="$MY_CLUSTER_WORKERS"
    lf_type="InstanaAgent"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho "F:OUT:install_instana"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Instana
function customise_instana() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho "F:IN:customise_instana"

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA_CUSTOM; then
    mylog info "==== Customise Instana." 1>&2
  fi

  decho "F:OUT:customise_instana"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################################################################
# Start of the script main entry
################################################################################################
# @param sc_properties_file: file path and name of the properties file
# @param MY_OC_PROJECT: namespace where to create the operators and capabilities
# @param sc_cluster_name: name of the cluster
# example of invocation: ./provision_cluster-v2.sh private/my-cp4i.properties sbtest cp4i-sb-cluster
# other example: ./provision_cluster-v2.sh cp4i.properties ./versions/cp4i-2023.4.properties cp4i sb20240102
# other example: ./provision_cluster-v2.sh cp4i.properties ./versions/cp4i-2023.4.properties cp4i ad202341
sc_properties_file=$1
sc_versions_file=$2
export MY_OC_PROJECT=$3
sc_cluster_name=$4

#
export ADEBUG=1
export TECHZONE=true

# SB]20240404 Global Index sequence for incremental output for each function call
export SC_SPACES_COUNTER=0
export SC_SPACES_INCR=3

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
# MAINSCRIPTDIR=$(dirname "$0")/
MAINSCRIPTDIR=${PWD}/

if [ $# -ne 4 ]; then
  echo "the number of arguments should be 4 : properties_file versions_file namespace cluster"
  exit 1
else
  echo "The provided arguments are: $@"
fi

#trap 'display_access_info' EXIT
# load helper functions
. "${MAINSCRIPTDIR}"lib.sh

# Read all the properties
read_config_file "$sc_properties_file"

# Read versions properties
read_config_file "$sc_versions_file"

# Read user file properties
my_user_file="${PRIVATEDIR}user.properties"
read_config_file "$my_user_file"

# check the differents pre requisites
check_exec_prereqs

: <<'END_COMMENT'

# Log to IBM Cloud
#login_2_ibm_cloud

# Create Openshift cluster
#create_openshift_cluster_wait_4_availability

# Log to openshift cluster
#login_2_openshift_cluster


# Create project namespace.
# SB]20231213 erreur obtenue juste après la création du cluster openshift : Error from server (Forbidden): You may not request a new project via this API.
# Solution : https://stackoverflow.com/questions/51657711/openshift-allow-serviceaccount-to-create-project
#          : https://stackoverflow.com/questions/44349987/error-from-server-forbidden-error-when-creating-clusterroles-rbac-author
#          : https://bugzilla.redhat.com/show_bug.cgi?id=1639197
# extrait du lien ci-dessus:
# You'll need to add the "self-provisioner" role to your service account as well. Although you've made it project admin, that only means its admin rights are scoped to that one project, which is not enough to allow it to request new projects.
# oc adm policy add-cluster-role-to-user self-provisioner system:serviceaccount:<project>:<cx-jenkins
# oc create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=IAM#saad.benachi@fr.ibm.com
if ! ${TECHZONE};then
  oc create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=$MY_USER_ID > /dev/null 2>&1
  oc create clusterrolebinding myname-cluster-binding --clusterrole=admin --user=$MY_USER_ID > /dev/null 2>&1
  oc adm policy add-cluster-role-to-user self-provisioner $MY_USER_ID -n $MY_OC_PROJECT
fi


# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=operators-installing-by-using-cli
# (Only if your preferred installation mode is a specific namespace on the cluster) Create an OperatorGroup
# We decided to install in openshift-operators so no need to OperatorGroup !
# TODO # nommer correctement les operatorgroup
create_namespace $MY_OC_PROJECT
create_namespace $MY_COMMON_SERVICES_NAMESPACE

create_namespace $MY_CERT_MANAGER_NAMESPACE
ls_type="OperatorGroup"
ls_cr_name="${MY_CERT_MANAGER_OPERATORGROUP}"
ls_yaml_file="${RESOURCSEDIR}operator-group-single.yaml"
ls_namespace=$MY_CERT_MANAGER_NAMESPACE
check_create_oc_yaml "${ls_type}" "${ls_cr_name}" "${ls_yaml_file}" "${ls_namespace}"

create_namespace $MY_LICENSE_SERVER_NAMESPACE
ls_type="OperatorGroup"
ls_cr_name="${MY_LICENSE_SERVER_OPERATORGROUP}"
ls_yaml_file="${RESOURCSEDIR}operator-group-single.yaml"
ls_namespace=$MY_LICENSE_SERVER_NAMESPACE
check_create_oc_yaml "${ls_type}" "${ls_cr_name}" "${ls_yaml_file}" "${ls_namespace}"

# Add ibm entitlement key to namespace
# SB]20230209 Aspera hsts service cannot be created because a problem with the entitlement, it must be added in the openshift-operators namespace.
mylog info "Creating entitlement, need to check if it is needed or works"
add_ibm_entitlement $MY_OC_PROJECT $MY_CONTAINER_ENGINE
add_ibm_entitlement $MY_OPERATORS_NAMESPACE $MY_CONTAINER_ENGINE
#add_ibm_entitlement $MY_GITOPS_NAMESPACE $MY_CONTAINER_ENGINE

#SB]20240429 Installing Red Hat OpenShift GitOps Operator
mylog info "==== Installing Red Hat OpenShift GitOps Operator." 1>&2
install_gitops

######################################################
# Start installation capabilities
######################################################

#SB]20231214 Installing Foundation services
mylog info "==== Installing foundational services (Cert Manager, Licensing Server and Common Services)." 1>&2
install_cert_manager
install_lic_srv
install_fs
install_mailhog

# Add OpenLdap app to openshift
install_openldap

END_COMMENT
# install_xxx: For each capability install : case, operator, operand

# install_openliberty
install_wasliberty

install_navigator

install_intassembly

install_assetrepo

install_ace

install_apic

install_eem $MY_CATALOGSOURCES_NAMESPACE

install_egw

install_ep $MY_CATALOGSOURCES_NAMESPACE

install_es

install_flink $MY_CATALOGSOURCES_NAMESPACE

install_hsts

install_mq

install_instana

######################################################
# Start customisation
######################################################

customise_openldap

customise_openliberty

customise_wasliberty

# Not needed, does not exist
# customise_navigator 
# customise_intassembly
# customise_assetrepo

customise_ace

customise_apic

customise_eem

customise_egw

customise_ep

customise_es

customise_flink

customise_hsts

customise_mq

customise_instana

######################################################
## Display information to access CP4I
######################################################
display_access_info

#work in progress
#SB]20230214 Ajout Configuration ACE
# export my_global_index="04"
# configure_ace_is $MY_OC_PROJECT
#configure_ace_is cp4i cp4i-ace-is-02 ./tmpl/configuration/ACE/ACE-IS-02.yaml cp4i-ace-barauth-02 ./tmpl/configuration/ACE/ACE-barauth-02.yaml

exit 0