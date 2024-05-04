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
function create_openshift_cluster_classic () {

  SECONDS=0
  var_fail sc_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $sc_cluster_name"
  if ibmcloud ks cluster get --cluster $sc_cluster_name > /dev/null 2>&1; then 
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
      exit 1
    fi
    oc_version_full=$(echo "[$oc_version_full]" | jq -r '.[] | (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring) + "_openshift"')
    mylog info "Found: ${oc_version_full}"
    # create
    mylog info "Creating OpenShift cluster: $sc_cluster_name"

    SECONDS=0
    vlans=$(ibmcloud ks vlan ls --zone $MY_CLUSTER_ZONE --output json|jq -j '.[]|" --" + .type + "-vlan " + .id')
    if ! ibmcloud ks cluster create classic \
      --name    $sc_cluster_name \
      --version $oc_version_full \
      --zone    $MY_CLUSTER_ZONE \
      --flavor  $MY_CLUSTER_FLAVOR_CLASSIC \
      --workers $MY_CLUSTER_WORKERS \
      --entitlement cloud_pak \
      --disable-disk-encrypt \
      $vlans
    then
      mylog error "Failed to create cluster" 1>&2
      exit 1
    fi
    mylog info "Creation of the cluster took: $SECONDS seconds." 1>&2
  fi
}

################################################
# Create openshift cluster using VPC infra
# use terraform because creation is more complex than classic
function create_openshift_cluster_vpc () {
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
  export TF_VAR_openshift_version=$(ibmcloud ks versions -q --show-version OpenShift|sed -Ene "s/^(${MY_OC_VERSION//./\\.}\.[^ ]*) .*$/\1/p")
  export TF_VAR_resource_group="rg-$MY_OC_PROJECT"
  export TF_VAR_openshift_cluster_name="$sc_cluster_name"
  pushd terraform
  terraform init
  terraform apply -var-file=var_override.tfvars
  popd
}

################################################
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
function add_ibm_entitlement () {
  local lf_in_ns=$1

  mylog check "Checking ibm-entitlement-key in $lf_in_ns"
  if oc -n $lf_in_ns get secret ibm-entitlement-key > /dev/null 2>&1
  then mylog ok
  else
    var_fail MY_ENTITLEMENT_KEY "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    $MY_CONTAINER_ENGINE -h > /dev/null 2>&1
    if test $? -eq 0 && ! echo $MY_ENTITLEMENT_KEY | $MY_CONTAINER_ENGINE login cp.icr.io --username cp --password-stdin;then
      mylog error "Invalid entitlement key" 1>&2
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $lf_in_ns"
    if ! oc -n $lf_in_ns create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io;then
      exit 1
    fi
  fi
}

################################################
# start customization
# Takes all the templates associated with the capabilities and generate the files from the context variables
# The files are generated into ./customisation/working/<capability>/config
# @param ns namespace where operands were instantiated
function start_customization () {
  local ns=$1
  local varb64

  mylog info "Copy template files to the working directory"
  
}

################################################
# launch customization
# Takes all the templates associated with the capabilities and generate the files from the context variables
# The files are generated into ./customisation/working/<capability>/config
# @param ns namespace where operands were instantiated
function launch_customization () {
  local ns=$1

  mylog info "Customisation of the capabilities"
}

##SB]20230215 load bar files in nexus repository
################################################
# Load bar files into nexus repository
function load_ace_bars () {
  # the input parameters :
  # - the directory containing the bar files to be loaded

  local ns=$1
  local directory=$2

  export my_nexus_url=`oc -n $ns get route $MY_NEXUS_ROUTE_NAME -o jsonpath='{.spec.host}'`

  i=1
  for barfile in ${directory}*.bar
  do 
    artifactid=`basename $barfile .bar` 
    curl --user "admin:bvn4KHQ*nep*zeb!qrp" \
      -F "maven2.generate-pom=true" \
      -F "maven2.groupId=$MY_MAVEN2_GROUPID" \
      -F "maven2.artifactId=$artifactid" \
      -F "maven2.packaging=bar" \
      -F "version=$MY_MAVEN2_ASSET_VERSION" \
      -F "maven2.asset${i}=@${barfile};type=$MY_MAVEN2_TYPE" \
      -F "maven2.asset${i}.extension=bar" "http://${my_nexus_url}/service/rest/v1/components?repository=$MY_NEXUS_REPO"
    i=i+1
  done
}

################################################
# Configure ACE IS
function configure_ace_is () {
  local ns=$1
  ace_bar_secret=${MY_ACE_BARAUTH_secret}-${my_global_index}
  ace_bar_auth=${MY_ACE_BARAUTH}-${my_global_index}
  ace_is=${MY_ACE_IS}-${my_global_index}

  # Create secret for barauth
  # Reference : https://www.ibm.com/docs/en/app-connect/containers_cd?topic=resources-configuration-reference#install__install_cli

  #export MY_ACE_BARAUTH_secret_b64=`base64 -w 0 ${ACE_CONFIGDIR}ACE-basic-auth.json`
  if oc -n=$ns get secret $ace_bar_secret > /dev/null 2>&1; then mylog ok;else
    oc -n=$ns create secret generic $ace_bar_secret --from-file=configuration="${ACE_CONFIGDIR}ACE-basic-auth.json"
  fi
  
  # Create a barauth 
  lf_type="Configuration"
  lf_cr_name=$ace_bar_auth
  lf_yaml_file="${ACE_CONFIGDIR}ACE-barauth-${my_global_index}.yaml"
  lf_namespace=$ns
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

 # Create an IS
  lf_type="IntegrationServer"
  lf_cr_name=$ace_is
  lf_yaml_file="${ACE_CONFIGDIR}ACE-IS-${my_global_index}.yaml"
  lf_namespace=$ns
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  wait_for_state IntegrationServer "$ace_is" Ready '{.status.phase}' $ns
}

################################################
# TBC
function create_openshift_cluster () {
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
}

################################################
# wait for Cluster availability
# set variable my_cluster_url
function wait_for_cluster_availability () {
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
	exit 1
	;;
  esac
}

################################################
# wait for ingress address availability
function wait_4_ingress_address_availability () {
  SECONDS=0
  local lf_ingress_address

  mylog check "Checking Ingress address"
  firsttime=true
  case $MY_CLUSTER_INFRA in
  classic) 
    sc_ingress_hostname_filter=.ingressHostname;;
  vpc) 
    sc_ingress_hostname_filter=.ingress.hostname;;
  *)
    mylog error "Only classic and vpc for MY_CLUSTER_INFRA"
    ;;
  esac

  while true;do
    lf_ingress_address=$(ibmcloud ks cluster get --cluster $sc_cluster_name --output json|jq -r "$sc_ingress_hostname_filter")
	  if test -n "$lf_ingress_address";then
		  mylog ok ", $lf_ingress_address"
		  break
	  fi
	  if $firsttime;then
		  mylog warn "not ready"
		  firsttime=false
	  fi
	  mylog wait "waiting for ingress address"
    # It takes about 15 minutes (21 Aug 2023)
	  sleep 90
  done
  mylog info "Checking Ingress availability took $SECONDS seconds to execute." 1>&2
}

######################################################################
# Create openshift cluster if it does not exist
# and wait for both availability of the cluster and the ingress address
function create_openshift_cluster_wait_4_availability () {
  if ! ${TECHZONE}; then
    # Create openshift cluster
    create_openshift_cluster

    # Wait for Cluster availability
    wait_for_cluster_availability

    # Wait for ingress address availability
    wait_4_ingress_address_availability
  fi
}

################################################
# Add OpenLdap app to openshift
function install_openldap () {
  if $MY_LDAP;then
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
}

################################################
# Add mailhog app to openshift
# Port is hard coded to 8025 and is defined by mailhog (default port)
function install_mailhog () {
  if $MY_MAILHOG;then
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
}

################################################
# Display information to access CP4I
function display_access_info () {
  mylog info "==== Displaying Access Info to CP4I." 1>&2
  # Temporary access with Keycloack
  temp_integration_admin_pwd=$(oc -n $MY_COMMON_SERVICES_NAMESPACE get secret integration-admin-initial-temporary-credentials -o jsonpath={.data.password} | base64 -d)
  mylog info "Integration admin password: ${temp_integration_admin_pwd}"

  mailhog_hostname=$(oc -n ${MY_MAIL_SERVER_NAMESPACE} get route maillhog -o jsonpath='{.spec.host}')
  decho "MailHog accessible at https://${mailhog_hostname}"

  if $MY_NAVIGATOR_INSTANCE;then
    get_navigator_access
  fi

  if $MY_ACE;then
    ace_ui_db_url=$(oc -n $MY_OC_PROJECT get Dashboard -o=jsonpath='{.items[?(@.kind=="Dashboard")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "ACE Dahsboard UI endpoint: " $ace_ui_db_url
    ace_ui_dg_url=$(oc -n $MY_OC_PROJECT get DesignerAuthoring -o=jsonpath='{.items[?(@.kind=="DesignerAuthoring")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "ACE Designer UI endpoint: " $ace_ui_dg_url
  fi

  if $MY_APIC;then
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

  if $MY_EEM;then
    eem_ui_url=$(oc -n $MY_OC_PROJECT get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "Event Endpoint Management UI endpoint: ${eem_ui_url}"
    eem_gtw_url=$(oc -n $MY_OC_PROJECT get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="gateway")].uri}')
	  mylog info "Event Endpoint Management Gateway endpoint: ${eem_gtw_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi

  if $MY_ES;then
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

  if $MY_LDAP;then
   mylog info "LDAP info"
  fi
  
  if $MY_ASSETREPO;then
   mylog info "AR info"
  fi

  if $MY_DPGW;then
   mylog info "DataPower info"
  fi

  if $MY_MQ;then
   mylog info "MQ info"
  fi

  if $MY_LIC_SRV;then
    licensing_service_url=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-licensing-service-instance")].spec.host}')
    mylog info "Licensing service endpoint: ${licensing_service_url}"
  fi
  
}

################################################
# SB]20231215 
# SB]20231130 patcher les foundational services en acceptant la license
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm
# 3.Setting the hardware profile and accepting the license
# License: Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
function accept_license_fs () {
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
}

################################################
# Log in IBM Cloud
function login_2_ibm_cloud () {
  if ! ${TECHZONE}; then
    SECONDS=0
    
    if ibmcloud resource groups -q > /dev/null 2>&1;then
      mylog info "user already logged to IBM Cloud." 
    else
      mylog info "user not logged to IBM Cloud." 1>&2
      var_fail MY_IC_APIKEY "Create and save API key JSON file from: https://cloud.ibm.com/iam/apikeys"
      mylog check "Login to IBM Cloud"
      if ! ibmcloud login -q --no-region --apikey $MY_IC_APIKEY > /dev/null;then
        mylog error "Fail to login to IBM Cloud, check API key: $MY_IC_APIKEY" 1>&2
        exit 1
      else mylog ok
      mylog info "Connecting to IBM Cloud took: $SECONDS seconds." 1>&2
      fi
    fi
  fi
}

################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
# requires var my_cluster_url
function login_2_openshift_cluster () {
  SECONDS=0

  if oc whoami > /dev/null 2>&1;then
    mylog info "user already logged to openshift cluster." 
  else
    if $TECHZONE; then
      oc login -u ${MY_TECHZONE_USERNAME} -p ${MY_TECHZONE_PASSWORD} ${MY_TECHZONE_OPENSHIFT_API_URL}
    else
      mylog check "Login to cluster"
      # SB 20231208 The following command sets your command line context for the cluster and download the TLS certificates and permission files for the administrator.
      # more details here : https://cloud.ibm.com/docs/openshift?topic=openshift-access_cluster#access_public_se
      ibmcloud ks cluster config --cluster ${sc_cluster_name} --admin
      while ! oc login -u apikey -p $MY_IC_APIKEY --server=$my_cluster_url > /dev/null;do
        mylog error "$(date) Fail to login to Cluster, retry in a while (login using web to unblock)" 1>&2
        sleep 30
      done
      mylog ok
      mylog info "Logging to Cluster took: $SECONDS seconds." 1>&2
    fi
  fi
}

################################################
# Install Cert Manager 
function install_cert_manager () {
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
  lf_current_chl=$MY_CERT_MANAGER_CHL
  lf_catalog_source_name="redhat-operators"
  lf_operator_namespace=$MY_CERT_MANAGER_NAMESPACE
  lf_strategy="Automatic"
  lf_wait_for_state=1
  lf_startingcsv=$MY_CERT_MANAGER_STARTINGCSV
  decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_current_chl}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_startingcsv}\""
  create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"
}

################################################
# Install Licensing Server 
function install_lic_srv () {
  # ibm-license-server
  if $MY_LIC_SRV;then
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
    lf_current_chl=$MY_LIC_SRV_CHL
    lf_catalog_source_name="ibm-licensing-catalog"
    lf_operator_namespace=$MY_LICENSE_SERVER_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_LIC_SRV_OPERATOR_STARTINGCSV
    decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_current_chl}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_startingcsv}\""
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"
  fi 
}

############################################################################################################################################
#SB]20231214 Installing Foundational services v4.3
# Referring to https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=whats-new-in-cloud-pak-integration-202341
# "The IBM Cloud Pak foundational services operator is no longer installed automatically. 
#  Install this operator manually if you need to create an instance that uses identity and access management. 
#  Also, make sure you have a certificate manager; otherwise, the IBM Cloud Pak foundational services operator installation will not complete."
# This function implements the following steps described here : 
############################################################################################################################################
function install_fs () {
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
  lf_current_chl=$MY_COMMONSERVICES_CHL
  lf_catalog_source_name="opencloud-operators"
  lf_strategy="Automatic"
  lf_wait_for_state=1
  lf_startingcsv=$MY_COMMONSERVICES_OPERATOR_STARTINGCSV
  decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_current_chl}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_startingcsv}\""
  create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"
 
  ## Setting hardware  Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
  #accept_license_fs $MY_OPERATORS_NAMESPACE
  accept_license_fs $lf_operator_namespace

  # Configuring foundational services by using the CommonService custom resource.
  lf_type="CommonService"
  lf_cr_name=$MY_COMMONSERVICES_INSTANCE_NAME
  lf_yaml_file="${RESOURCSEDIR}foundational-services-cr.yaml"
  decho "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"
}

################################################
# Install Navigator (depending on two boolean)
function install_navigator () {
  ## ibm-integration-platform-navigator
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  # Creating Navigator operator subscription
  if $MY_NAVIGATOR;then
    mylog info "==== Installing Navigator." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-integration-platform-navigator MY_NAVIGATOR_CASE amd64

    # Creating Navigator operator subscription
    lf_operator_name="ibm-integration-platform-navigator"
    lf_current_chl=$MY_NAVIGATOR_CHL
    lf_catalog_source_name="ibm-integration-platform-navigator-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_NAVIGATOR_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"
  fi

  if $MY_NAVIGATOR_INSTANCE;then
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
}

################################################
# Install Integration Assembly
function install_intassembly () {
  # Creating Integration Assembly instance
  if $MY_INTASSEMBLY;then
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
}

################################################
# Install Asset Repository 
function install_assetrepo () {
  if $MY_ASSETREPO;then
    mylog info "==== Installing Asset Repository." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-integration-asset-repository MY_ASSETREPO_CASE amd64

    # Creating Asset Repository operator subscription
    lf_operator_name="ibm-integration-asset-repository"
    lf_current_chl=$MY_ASSETREPO_CHL
    lf_catalog_source_name="ibm-integration-asset-repository-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_ASSETREPO_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

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
}

################################################
# Install ACE
function install_ace () {
  # ibm-appconnect
  if $MY_ACE;then
    mylog info "==== Installing ACE." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-appconnect MY_ACE_CASE amd64
 
    # Creating ACE operator subscription
    lf_operator_name="ibm-appconnect"
    lf_current_chl=$MY_ACE_CHL
    lf_catalog_source_name="appconnect-operator-catalogsource"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_ACE_OPERATOR_STARTINGCSV
    lf_wait_for_state=1
    decho "create_operator_subscription \"${lf_operator_name}\" \"${lf_current_chl}\" \"${lf_catalog_source_name}\" \"${lf_operator_namespace}\" \"${lf_strategy}\" \"${lf_wait_for_state}\" \"${lf_startingcsv}\""
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

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

  # start customization
  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_ACE_CUSTOM;then
    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    if [ ! -d ${ACE_GEN_CUSTOMDIR}scripts ]; then
      mkdir -p ${ACE_GEN_CUSTOMDIR}scripts
    fi
    if [ ! -d ${ACE_GEN_CUSTOMDIR}config ]; then
      mkdir -p ${ACE_GEN_CUSTOMDIR}config
    fi
    generate_files $ACE_TMPL_CUSTOMDIR $ACE_GEN_CUSTOMDIR true

    # launch custo scripts
    mylog info "Customise ACE"
  fi
}

################################################
# Install APIC
function install_apic () {
  # ibm-apiconnect
  if $MY_APIC;then
    mylog info "==== Installing APIC." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-apiconnect MY_APIC_CASE amd64

    # Creating APIC operator subscription 
    lf_operator_name="ibm-apiconnect"
    lf_current_chl=$MY_APIC_CHL
    lf_catalog_source_name="ibm-apiconnect-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_APIC_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

    # Creating APIC instance
    lf_file="${OPERANDSDIR}APIC-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_APIC_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="APIConnectCluster"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  # start customization
  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_APIC_CUSTOM;then
    save_certificate ${MY_OC_PROJECT} cp4i-apic-ingress-ca ${WORKINGDIR}
    save_certificate ${MY_OC_PROJECT} cp4i-apic-gw-gateway ${WORKINGDIR}

    # launch custom script
    mylog info "Customise APIC"
    . ${APIC_SCRIPTDIR}scripts/apic.config.sh
  fi
  exit
}

################################################
# Install APIC
function install_openliberty () {
  # backend J2EE applications
  if $MY_OPENLIBERTY;then
    mylog info "==== Installing OPEN Liberty." 1>&2

    create_namespace $MY_BACKEND_NAMESPACE

    # TODO other approach is to use the catalog which already inludes the Open Liberty operator and use a subscription
    # Case exists 1.3.1, and IBM/RedHat Catalog

    export OPEN_LIBERTY_OPERATOR_NAMESPACE=$MY_BACKEND_NAMESPACE
    export OPEN_LIBERTY_OPERATOR_WATCH_NAMESPACE=$MY_BACKEND_NAMESPACE
    # TODO Check that is this value
    export WATCH_NAMESPACE='""'
    adapt_file ${OPENLIBERTY_TMPL_CUSTOMDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-rbac-watch-all.yaml
    adapt_file ${OPENLIBERTY_TMPL_CUSTOMDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-crd.yaml
    adapt_file ${OPENLIBERTY_TMPL_CUSTOMDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-operator.yaml

    # Creating APIC operator subscription (Check arbitrarely one resource, the deployment of the operator)
    local lf_octype='deployment'
    local lf_name='olo-controller-manager'
    
    # check if deployment of the operator already performed
    mylog check "Checking ${lf_octype} ${lf_name} in ${MY_BACKEND_NAMESPACE}"
    if oc -n ${MY_BACKEND_NAMESPACE} get ${lf_octype} ${lf_name} > /dev/null 2>&1; then mylog ok
    else
      oc apply --server-side -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml
      oc apply -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml
      oc apply -n ${MY_BACKEND_NAMESPACE} -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml
    fi

    # Handle private image registry
    # I'm using a service id associated to my email, information are configured in private/users.properties (See README.dm)
    # Creating the secret to access the images in the private registry
    local lf_octype='secret'
    local lf_name='my-image-registry-secret'
      
    # check if secret already created
    mylog check "Checking ${lf_octype} ${lf_name} in ${MY_BACKEND_NAMESPACE}"
    if oc -n ${MY_BACKEND_NAMESPACE} get ${lf_octype} ${lf_name} > /dev/null 2>&1; then mylog ok
    else
      kubectl -n ${MY_BACKEND_NAMESPACE} create secret docker-registry my-image-registry-secret \
        --docker-server=${MY_IMAGE_REGISTRY} \
        --docker-username=${MY_IMAGE_REGISTRY_USERNAME} \
        --docker-password=${MY_IMAGE_REGISTRY_PASSWORD}  \
        --docker-email=${MY_USER_EMAIL}
    fi

    # Build and create image, then load it into registry, this is optional because images won't change very often
    if $MY_OPENLIBERTY_CUSTOM;then
    pushd ${OPENLIBERTY_TMPL_CUSTOMDIR}system
      mylog info "Compile code"
      mvn clean install

      mylog info "Login to docker registry"
      docker login -u $MY_IMAGE_REGISTRY_USERNAME -p $MY_IMAGE_REGISTRY_PASSWORD $MY_IMAGE_REGISTRY
      ibmcloud cr login --client docker -u myappscreds -p $MY_IMAGE_REGISTRY_PASSWORD $MY_IMAGE_REGISTRY

      mylog info "Build docker image oljaxrs:1.0"
      docker build -t oljaxrs:1.0 .

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
    adapt_file ${OPENLIBERTY_TMPL_CUSTOMDIR}config/ ${OPENLIBERTY_GEN_CUSTOMDIR}config/ system-appdeploy.yaml
    kubectl -n ${MY_BACKEND_NAMESPACE} apply -f ${OPENLIBERTY_GEN_CUSTOMDIR}config/system-appdeploy.yaml
    # kubectl run <service_name> --image=de.icr.io/olo1/oljaxrs
    # kubectl -n ${MY_BACKEND_NAMESPACE} get OpenLibertyApplications
    # kubectl -n ${MY_BACKEND_NAMESPACE} describe olapps/mysystem

    # lf_operator_name="ibm-apiconnect"
    # lf_current_chl=$MY_APIC_CHL
    # lf_catalog_source_name="ibm-apiconnect-catalog"
    # lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    # lf_strategy="Automatic"
    # lf_wait_for_state=1
    # lf_startingcsv=$MY_APIC_OPERATOR_STARTINGCSV
    # create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"
 
    # # Creating APIC instance
    # lf_file="${OPERANDSDIR}APIC-Capability.yaml"
    # lf_ns="${MY_OC_PROJECT}"
    # lf_path="{.status.phase}"
    # lf_resource="$MY_APIC_INSTANCE_NAME"
    # lf_state="Ready"
    # lf_type="APIConnectCluster"
    # lf_wait_for_state=0
    # create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  # start customization
  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_OPENLIBERTY_CUSTOM;then
    save_certificate ${MY_OC_PROJECT} cp4i-apic-ingress-ca ${WORKINGDIR}
    save_certificate ${MY_OC_PROJECT} cp4i-apic-gw-gateway ${WORKINGDIR}

    # launch custom script
    mylog info "Customise OPENLIBERTY"
    # . ${OPENLIBERTY_SCRIPTDIR}scripts/openliberty.config.sh
  fi
}

################################################
# Install DataPower Gateway
function install_dpgw () {
  # Creating DP Gateway operator subscription
  if $MY_DPGW;then
    check_add_cs_ibm_pak ibm-datapower-operator MY_DPGW_CASE amd64

    lf_operator_name="datapower-operator"
    lf_current_chl=$MY_DPGW_CHL
    lf_catalog_source_name="ibm-datapower-operator-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_DPGW_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"
  fi
}

################################################
# Install EEM
function install_eem () {
  local lf_in_ns=$1
  local varb64

  if $MY_EEM;then
    mylog info "==== Installing Event Endpoint Management." 1>&2
    ## event endpoint management
    ## to get the name of the pak to use : oc ibm-pak list
    ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
    check_add_cs_ibm_pak ibm-eventendpointmanagement MY_EEM_CASE amd64
    #oc -n $lf_in_ns ibm-pak launch ibm-eventendpointmanagement --version $MY_EEM_CASE --inventory eemOperatorSetup --action installCatalog

    # Creating Event Endpoint Management operator subscription
    lf_operator_name="ibm-eventendpointmanagement"
    lf_current_chl=$MY_EEM_CHL
    lf_catalog_source_name="ibm-eventendpointmanagement-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_EEM_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

    # Creating EventEndpointManager instance (Event Processing)
    lf_file="${OPERANDSDIR}EEM-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EEM_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventEndpointManagement"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  # start customization
  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  ## Creating EEM users and roles
  if $MY_EEM_CUSTOM;then
    # generate properties files
    cat  $EEM_TMPL_USER_CREDENTIALS_CUSTOMFILE | envsubst >  $EEM_GEN_USER_CREDENTIALS_CUSTOMFILE
    cat  $EEM_TMPL_USER_ROLES_CUSTOMFILE | envsubst >  $EEM_GEN_USER_ROLES_CUSTOMFILE

    # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
    # user credentials
    varb64=$(cat "$EEM_GEN_USER_CREDENTIALS_CUSTOMFILE" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]"

    # user roles
    varb64=$(cat "$EEM_GEN_USER_ROLES_CUSTOMFILE" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]"

    # launch custom script
    mylog info "Customise EEM"
  fi
}

################################################
# Install EGW
function install_egw () {
  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW;then
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
}

################################################
# Install EP
function install_ep () {
  local lf_in_ns=$1
  local varb64

  if $MY_EP;then
    mylog info "==== Installing Event Processing." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-eventprocessing MY_EP_CASE amd64
    #oc -n  $lf_in_ns ibm-pak launch ibm-eventprocessing --version $MY_EP_CASE --inventory epOperatorSetup --action installCatalog

    ## Creating Event processing operator subscription
    lf_operator_name="ibm-eventprocessing"
    lf_current_chl=$MY_EP_CHL
    lf_catalog_source_name="ibm-eventprocessing-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_EP_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

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
  fi

  # start customization
  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  ## Creating Event Processing users and roles
  if $MY_EP_CUSTOM;then
    # generate properties files
    cat  $EP_TMPL_USER_CREDENTIALS_CUSTOMFILE | envsubst >  $EP_GEN_USER_CREDENTIALS_CUSTOMFILE
    cat  $EP_TMPL_USER_ROLE_CUSTOMFILE | envsubst >  $EP_GEN_USER_ROLES_CUSTOMFILE

    # user credentials
    varb64=$(cat "$EP_GEN_USER_CREDENTIALS_CUSTOMFILE" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]"

    # user roles
    varb64=$(cat "$EP_GEN_USER_ROLES_CUSTOMFILE" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]"

    # launch custom script
    mylog info "Customise Event Processing"
  fi
}

################################################
# Install IBM Event streams
function install_es () {
  # ibm-eventstreams 
  if $MY_ES;then
    mylog info "==== Installing Event Streams." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-eventstreams MY_ES_CASE amd64

    # Creating EventStreams operator subscription 
    lf_operator_name="ibm-eventstreams"
    lf_current_chl=$MY_ES_CHL
    lf_catalog_source_name="ibm-eventstreams"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_ES_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

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
  if $MY_ES_CUSTOM;then
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
    generate_files $ES_TMPL_CUSTOMDIR $ES_GEN_CUSTOMDIR false

    # SB]20231211 https://ibm.github.io/event-automation/es/installing/installing/
    # Question : Do we have to create this configmap before installing ES or even after ? Used for monitoring
    lf_type="configmap"
    lf_cr_name="cluster-monitoring-config"
    lf_yaml_file="${RESOURCSEDIR}openshift-monitoring-cm.yaml"
    lf_namespace="openshift-monitoring"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
 
    # launch custom script
      mylog info "Customise Event Streams"
    . ${ES_SCRIPTDIR}scripts/es.config.sh
  fi
}

################################################
# Install Flink
function install_flink () {
  local lf_in_ns=$1
  if $MY_FLINK;then
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
    lf_current_chl=$MY_FLINK_CHL
    lf_catalog_source_name="ibm-eventautomation-flink-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_FLINK_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

  
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
}

################################################
# Install Aspera HSTS
function install_hsts () {
  # ibm aspera hsts
  if $MY_HSTS;then
    mylog info "==== Installing HSTS." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-aspera-hsts-operator MY_HSTS_CASE amd64

    # Creating Aspera HSTS operator subscription
    lf_operator_name="aspera-hsts-operator"
    lf_current_chl=$MY_HSTS_CHL
    lf_catalog_source_name="aspera-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_HSTS_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

    # Creating Aspera HSTS instance
    #oc apply -f "${OPERANDSDIR}AsperaCM-cp4i-hsts-prometheus-lock.yaml"
    #oc apply -f "${OPERANDSDIR}AsperaCM-cp4i-hsts-engine-lock.yaml"

    lf_file="${OPERANDSDIR}AsperaHSTS-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_HSTS_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IbmAsperaHsts"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi
}

################################################
# Install MQ
function install_mq () {
  # ibm-mq
  if $MY_MQ;then
    mylog info "==== Installing MQ." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-mq MY_MQ_CASE amd64

    # Creating MQ operator subscription
    lf_operator_name="ibm-mq"
    lf_current_chl=$MY_MQ_CHL
    lf_catalog_source_name="ibmmq-operator-catalogsource"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_MQ_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

    # Creating MQ instance
    lf_file="${OPERANDSDIR}MQ-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_MQ_INSTANCE_NAME"
    lf_state="Running"
    lf_type="QueueManager"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi
}

################################################
# Install Instana
function install_instana () {
  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA;then
    mylog info "==== Adding Instana." 1>&2
    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    lf_operator_name="instana-agent-operator"
    lf_current_chl=$MY_INSTANA_CHL
    lf_catalog_source_name="certified-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_INSTANA_OPERATOR_STARTINGCSV
    lf_wait_for_state=1
    create_namespace $MY_INSTANA_AGENT_NAMESPACE 
    oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy add-scc-to-user privileged -z instana-agent
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

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
}

################################################
# Install Nexus 
function install_nexus () {
  # Nexus
  #SB]20230130 Ajout du repository Nexus
  # Creating Nexus operator subscription
  if $MY_NEXUS;then
    mylog info "==== Adding Nexus." 1>&2
    lf_operator_name="nxrm-operator-certified"
    lf_current_chl=$MY_NEXUS_CHL
    lf_catalog_source_name="certified-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_wait_for_state=1
    lf_startingcsv=$MY_NEXUS_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_wait_for_state}" "${lf_startingcsv}"

    ## Creating Nexus Repository instance (An open source repository for build artifacts)
    lf_file="${OPERANDSDIR}Nexus-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="[.status.conditions[].type][1]"
    lf_resource="$MY_NEXUS_INSTANCE_NAME"
    lf_state="Deployed"
    lf_type="NexusRepo"
    lf_wait_for_state=0
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # add route to access Nexus from outside cluster
    lf_type="Route"
    lf_cr_name=$MY_NEXUS_ROUTE_NAME
    lf_yaml_file="${OPERANDSDIR}Nexus-Route.yaml"
    lf_namespace=$MY_OC_PROJECT
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    mylog info "Creation of Route (Nexus) took $SECONDS seconds to execute." 1>&2
  fi
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

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
# MAINSCRIPTDIR=$(dirname "$0")/
MAINSCRIPTDIR=${PWD}/

if [ $# -ne 4 ]; then
  echo "the number of arguments should be 4 : properties_file versions_file namespace cluster"
  exit
else echo "The provided arguments are: $@"
fi

trap 'display_access_info' EXIT
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

# Log to IBM Cloud
login_2_ibm_cloud

: <<'END_COMMENT'


# Create Openshift cluster
create_openshift_cluster_wait_4_availability

# Log to openshift cluster
login_2_openshift_cluster

END_COMMENT
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

#SB]20231214 Installing Foundation services
mylog info "==== Installing foundational services (Cert Manager, Licensing Server and Common Services)." 1>&2
install_cert_manager
install_lic_srv
install_fs
install_mailhog

# Add OpenLdap app to openshift
install_openldap

# Add Nexus Repository to openshift
install_nexus

# For each capability install : case, operator, operand 
install_navigator

# For each capability install : case, operator, operand 
install_intassembly

# For each capability install : case, operator, operand 
install_assetrepo

# For each capability install : case, operator, operand 
install_ace

# For each capability install : case, operator, operand
# install_openliberty
install_apic

# For each capability install : case, operator, operand 
install_eem $MY_CATALOGSOURCES_NAMESPACE

# For each capability install : case, operator, operand 
install_egw

# For each capability install : case, operator, operand 
install_ep $MY_CATALOGSOURCES_NAMESPACE

# For each capability install : case, operator, operand 
install_es

# For each capability install : case, operator, operand 
install_flink $MY_CATALOGSOURCES_NAMESPACE

# For each capability install : case, operator, operand 
install_hsts

# For each capability install : case, operator, operand 
install_mq

# Add Instana
install_instana

## Display information to access CP4I
display_access_info

#work in progress
#SB]20230214 Ajout Configuration ACE
# export my_global_index="04"
# configure_ace_is $MY_OC_PROJECT
#configure_ace_is cp4i cp4i-ace-is-02 ./tmpl/configuration/ACE/ACE-IS-02.yaml cp4i-ace-barauth-02 ./tmpl/configuration/ACE/ACE-barauth-02.yaml
