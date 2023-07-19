#!/bin/bash
# Laurent 2021 
# Updated July 2023 Saad / Arnauld

################################################
# Create openshift cluster using classic infrastructure
CreateOpenshiftClusterClassic () {
  var_fail my_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $my_cluster_name"
  if ibmcloud ks cluster get --cluster $my_cluster_name > /dev/null 2>&1; then mylog ok ", cluster exists"; else
    mylog warn ", cluster does not exist"
    var_fail my_oc_version 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
    var_fail my_cluster_zone 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider classic'
    var_fail my_cluster_flavor_classic 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $my_cluster_zone'
    var_fail my_cluster_workers 'Speficy number of worker nodes in cluster'
    mylog info "Getting current version for OC: $my_oc_version"
    oc_version_full=$(ibmcloud ks versions -q --show-version OpenShift|grep $my_oc_version)
    if test -z "${oc_version_full}";then
      mylog error "Failed to find full version for ${my_oc_version}" 1>&2
      fix_oc_version
      exit 1
    fi
    mylog info "Found: ${oc_version_full}"
    # create
    mylog info "Creating cluster: $my_cluster_name"
    vlans=$(ibmcloud ks vlan ls --zone $my_cluster_zone --output json|jq -j '.[]|" --" + .type + "-vlan " + .id')
    if ! ibmcloud oc cluster create classic \
      --name    $my_cluster_name \
      --version $oc_version_full \
      --zone    $my_cluster_zone \
      --flavor  $my_cluster_flavor_classic \
      --workers $my_cluster_workers \
      --entitlement cloud_pak \
      --disable-disk-encrypt \
      $vlans
    then
      mylog error "Failed to create cluster" 1>&2
      exit 1
    fi
  fi
}

################################################
# Create openshift cluster using VPC infra function
# use terraform because creation is more complex than classic
CreateOpenshiftClusterVPC () {
  # check vars from config file
  var_fail my_oc_version 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
  var_fail my_cluster_zone 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider vpc-gen2'
  var_fail my_cluster_flavor_vpc 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $my_cluster_zone'
  var_fail my_cluster_workers 'Speficy number of worker nodes in cluster'
  # set variables for terraform
  export TF_VAR_ibmcloud_api_key="$my_ic_apikey"
  export TF_VAR_openshift_worker_pool_flavor="$my_cluster_flavor_vpc"
  export TF_VAR_prefix="$my_oc_project"
  export TF_VAR_region="$my_cluster_region"
  export TF_VAR_openshift_version=$(ibmcloud ks versions -q --show-version OpenShift|sed -Ene "s/^(${my_oc_version//./\\.}\.[^ ]*) .*$/\1/p")
  export TF_VAR_resource_group="rg-$my_oc_project"
  export TF_VAR_openshift_cluster_name="$my_cluster_name"
  pushd terraform
  terraform init
  terraform apply -var-file=var_override.tfvars
  popd
}

# function
CreateOpenshiftCluster () {
  var_fail my_cluster_infra 'mylog warn "Choose one of: classic or vpc" 1>&2'
  case "${my_cluster_infra}" in
  classic)
    CreateOpenshiftClusterClassic
    gbl_ingress_hostname_filter=.ingressHostname
    gbl_cluster_url_filter=.serverURL
    ;;
  vpc)
    CreateOpenshiftClusterVPC
    gbl_ingress_hostname_filter=.ingress.hostname
    gbl_cluster_url_filter=.masterURL
    ;;
  *)
    mylog error "only classic and vpc for my_cluster_infra"
    ;;
  esac
}

# wait for ingress address availability function
Wait4IngressAddressAvailability () {
  mylog check "Checking Ingress address"
  firsttime=true
  case $my_cluster_infra in

  esac
  while true;do
  ingress_address=$(ibmcloud ks cluster get --cluster $my_cluster_name --output json|jq -r "$gbl_ingress_hostname_filter")
	if test -n "$ingress_address";then
		mylog ok ", $ingress_address"
		break
	fi
	if $firsttime;then
		mylog warn "not ready"
		firsttime=false
	fi
	mylog wait "waiting for ingress address"
	sleep 10
  done
}

################################################
# Create namespace function
# @param ns namespace to be created
CreateNameSpace () {
  local ns=$1
  var_fail my_oc_project "Please define project name in config"
  mylog check "Checking project $ns"
  if oc get project $ns > /dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $ns"
    if ! oc new-project $ns; then
      exit 1
    fi
  fi
}

################################################
# add ibm entitlement key to namespace function
# @param ns namespace where secret is created
AddIBMEntitlement () {
  local ns=$1
  mylog check "Checking ibm-entitlement-key in $ns"
  if oc get secret ibm-entitlement-key --namespace=$ns > /dev/null 2>&1; then mylog ok; else
    var_fail my_entitlement_key "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    docker -h > /dev/null 2>&1
    if test $? -eq 0 && ! echo $my_entitlement_key | docker login cp.icr.io --username cp --password-stdin;then
      mylog error "Invalid entitlement key" 1>&2
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $ns"
    if ! oc create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$my_entitlement_key --docker-server=cp.icr.io --namespace=$ns;then
      exit 1
    fi
  fi
}

################################################
# add catalog sources using ibm_pak plugin
Add_Catalog_Sources_ibm_pak () {

  ## ibm-integration-platform-navigator
  check_add_cs_ibm_pak ibm-integration-platform-navigator $my_ibm_integration_platform_navigator_case amd64

  ## ibm-integration-asset-repository
  check_add_cs_ibm_pak ibm-integration-asset-repository $my_ibm_integration_asset_repository_case amd64

  # ibm-apiconnect
  check_add_cs_ibm_pak ibm-apiconnect $my_ibm_apiconnect_case amd64

  ## ibm-appconnect
  check_add_cs_ibm_pak ibm-appconnect $my_ibm_appconnect_case amd64

  ## ibm-mq
  check_add_cs_ibm_pak ibm-mq $my_ibm_mq_case amd64

  ## ibm-eventstreams
  check_add_cs_ibm_pak ibm-eventstreams $my_ibm_eventstreams_case amd64

  ## ibm-datapower-operator
  check_add_cs_ibm_pak ibm-datapower-operator $my_ibm_datapower_operator_case amd64

  ## ibm-aspera-hsts-operator
  check_add_cs_ibm_pak ibm-aspera-hsts-operator $my_ibm_aspera_hsts_operator_case amd64

  ## ibm-cp-common-services
  check_add_cs_ibm_pak ibm-cp-common-services $my_ibm_cp_common_services_case amd64
}

################################################
# Install Operators
## operator_name = "Literal name", https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=operators-installing-using-cli#operators-available
## current_channel = "Operator channel", : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=reference-operator-channel-versions-this-release
## catalog_source_name = catalog source created for this operator : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
# @param ns: namespace to install the operators
Install_Operators () {
  local ns=$1

  ##-- Creating Navigator operator subscription
  if $my_ibm_integration_platform_navigator;then
    export operator_name=ibm-integration-platform-navigator
    export current_channel=$my_ibm_navigator_operator_channel
    export catalog_source_name=ibm-integration-platform-navigator-catalog

    check_create_oc_yaml "subscription" ibm-integration-platform-navigator "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion ibm-integration-platform-navigator $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns 
  fi

  ##-- Creating Asset Repository operator subscription
  if $my_ibm_integration_asset_repository;then
    export operator_name=ibm-integration-asset-repository
    export current_channel=$my_ibm_ar_operator_channel
    export catalog_source_name=ibm-integration-asset-repository-catalog

    check_create_oc_yaml "subscription" ibm-integration-asset-repository "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion ibm-integration-asset-repository $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  ##-- Creating ACE operator subscription
  if $my_ibm_appconnect;then
    export operator_name=ibm-appconnect
    export current_channel=$my_ibm_ace_operator_channel
    export catalog_source_name=appconnect-operator-catalogsource

    check_create_oc_yaml "subscription" ibm-appconnect "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion ibm-appconnect $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  ##-- Creating APIC operator subscription
  if $my_ibm_apiconnect;then
    export operator_name=ibm-apiconnect
    export current_channel=$my_ibm_apic_operator_channel
    export catalog_source_name=ibm-apiconnect-catalog

    check_create_oc_yaml "subscription" ibm-apiconnect "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion ibm-apiconnect $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  ##-- Creating MQ operator subscription
  if $my_ibm_mq;then
    export operator_name=ibm-mq
    export current_channel=$my_ibm_mq_operator_channel
    export catalog_source_name=ibmmq-operator-catalogsource

    check_create_oc_yaml "subscription" ibm-mq "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion ibm-mq $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  ##-- Creating EventStreams operator subscription
  if $my_ibm_eventstreams;then
    export operator_name=ibm-eventstreams
    export current_channel=$my_ibm_es_channel
    export catalog_source_name=ibm-eventstreams

    check_create_oc_yaml "subscription" ibm-eventstreams "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion ibm-eventstreams $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  ##-- Creating DP Gateway operator subscription
  ## SB]202302001 attention au dp la souscription porte un nom particulier voir la variable dp ci-dessous.
  if $my_datapower_operator;then
    export operator_name=datapower-operator
    export current_channel=$my_ibm_dpgw_operator_channel
    export catalog_source_name=ibm-datapower-operator-catalog
    dp=${operator_name}-${current_channel}-${catalog_source_name}-openshift-marketplace

    check_create_oc_yaml "subscription" $dp "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion datapower-operator $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  ##-- Creating Aspera HSTS operator subscription
  if $my_aspera_hsts_operator;then
    export operator_name=aspera-hsts-operator
    export current_channel=$my_ibm_hsts_operator_channel
    export catalog_source_name=aspera-operators
  
    check_create_oc_yaml "subscription" aspera-hsts-operator "${subscriptionsdir}subscription.yaml" $ns
    check_resource_availability clusterserviceversion aspera-hsts-operator $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  #SB]20230130 Ajout du repository Nexus
  ##-- Creating Nexus perator subscription
  if $my_install_nexus;then
    check_create_oc_yaml "subscription" nxrm-operator-certified "${subscriptionsdir}Nexus-Sub.yaml" $ns
    check_resource_availability clusterserviceversion nxrm-operator-certified $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi

  #SB]20230201 Ajout d'Instana
  ##-- Creating Instana operator subscription
  if $my_instana_agent_operator;then
    ##-- Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    CreateNameSpace $my_instana_agent_project
    oc adm policy add-scc-to-user privileged -z instana-agent -n $my_instana_agent_project

    check_create_oc_yaml "subscription" instana-agent-operator "${subscriptionsdir}Instana-Sub.yaml" $ns
    check_resource_availability clusterserviceversion instana-agent-operator $ns
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase' $ns
  fi
}

################################################
# create capabilities function
# @param ns namespace where capabilities are created
Create_Capabilities () {
  local ns=$1

  ##-- Creating Navigator instance
  if $my_ibm_integration_platform_navigator;then
    check_create_oc_yaml PlatformNavigator $my_cp_navigator_instance_name "${capabilitiesdir}Navigator-Capability.yaml" $ns
    wait_for_oc_state PlatformNavigator "$my_cp_navigator_instance_name" Ready '.status.conditions[0].type' $ns
  fi

  #SB]20230201 Utilisation de l'integration Assembly
  ##-- Creating Integration Assembly instance
  if $my_ibm_intassembly;then
    check_create_oc_yaml IntegrationAssembly $my_cp_intassembly_instance_name "${capabilitiesdir}IntegrationAssembly-Capability.yaml" $ns
    wait_for_oc_state IntegrationAssembly "$my_cp_intassembly_instance_name" Ready '.status.conditions[0].type' $ns
  fi
  
  ##-- Creating ACE Dashboard instance
  if $my_ibm_appconnect;then
    check_create_oc_yaml Dashboard $my_cp_ace_dashboard_instance_name "${capabilitiesdir}ACE-Dashboard-Capability.yaml" $ns
    wait_for_oc_state Dashboard "$my_cp_ace_dashboard_instance_name" Ready '.status.conditions[0].type' $ns
  fi
  
  ##-- Creating ACE Designer instance
  if $my_ibm_appconnect;then
    check_create_oc_yaml DesignerAuthoring $my_cp_ace_designer_instance_name "${capabilitiesdir}ACE-Designer-Capability.yaml" $ns
    wait_for_oc_state DesignerAuthoring "$my_cp_ace_designer_instance_name" Ready '.status.conditions[0].type' $ns
  fi

  ##-- Creating ASpera HSTS instance
  if $my_aspera_hsts_operator;then
    oc apply -f "${capabilitiesdir}AsperaCM-cp4i-hsts-prometheus-lock.yaml"
    oc apply -f "${capabilitiesdir}AsperaCM-cp4i-hsts-engine-lock.yaml"

    check_create_oc_yaml IbmAsperaHsts $my_cp_hsts_instance_name "${capabilitiesdir}AsperaHSTS-Capability.yaml" $ns
    wait_for_oc_state IbmAsperaHsts "$my_cp_hsts_instance_name" Ready '.status.conditions[0].type' $ns
  fi

  ##-- Creating APIC instance
  if $my_ibm_apiconnect;then
    check_create_oc_yaml APIConnectCluster $my_cp_apic_instance_name "${capabilitiesdir}APIC-Capability.yaml" $ns
    wait_for_oc_state APIConnectCluster "$my_cp_apic_instance_name" Ready '.status.phase' $ns
  fi

  ##-- Creating Asset Repository instance
  if $my_ibm_integration_asset_repository;then
    check_create_oc_yaml AssetRepository $my_cp_ar_instance_name ${capabilitiesdir}AR-Capability.yaml $ns
    wait_for_oc_state AssetRepository "$my_cp_ar_instance_name" Ready '.status.phase' $ns
  fi

  ##-- Creating Eventstream instance
  if $my_ibm_eventstreams;then
    check_create_oc_yaml EventStreams $my_cp_es_instance_name ${capabilitiesdir}ES-Capability.yaml $ns
    wait_for_oc_state EventStreams "$my_cp_es_instance_name" Ready '.status.phase' $ns
  fi

  #SB]20230130 Ajout de Nexus Repository (An open source repository for build artifacts)
  ##-- Creating Nexus Repository instance
    if $my_install_nexus;then
    check_create_oc_yaml NexusRepo $my_nexus_instance_name ${capabilitiesdir}Nexus-Capability.yaml $ns
    wait_for_oc_state NexusRepo "$my_nexus_instance_name" Deployed '[.status.conditions[].type][1]' $ns
    # add route to access Nexus from outside cluster
    check_create_oc_yaml Route $my_nexus_route_name ${capabilitiesdir}Nexus-Route.yaml $ns
  fi

  #SB]20230201 Ajout Instana
  ##-- Creating Instana agent
  if $my_instana_agent_operator;then
    check_create_oc_yaml InstanaAgent $my_instana_agent_instance_name ${capabilitiesdir}Instana-Agent-Capability-CloudIBM.yaml $my_instana_agent_project
    wait_for_oc_state DaemonSet $my_instana_agent_instance_name $my_cluster_workers '.status.numberReady' $my_instana_agent_project
  fi
}

##SB]20230215 load bar files in nexus repository
################################################
# Load bar files into nexus repository
Load_ACE_Bars () {
  # the input parameters :
  # - the directory containing the bar files to be loaded

  local ns=$1
  local directory=$2

  export my_nexus_url=`oc get route $my_nexus_route_name -n $ns -o jsonpath='{.spec.host}'`

  i=1
  for barfile in ${directory}*.bar
  do 
    artifactid=`basename $barfile .bar` 
    curl --user "admin:bvn4KHQ*nep*zeb!qrp" -F "maven2.generate-pom=true" \
                                            -F "maven2.groupId=$my_maven2_groupid" \
                                            -F "maven2.artifactId=$artifactid" \
                                            -F "maven2.packaging=bar" \
                                            -F "version=$my_maven2_asset_version" \
                                            -F "maven2.asset${i}=@${barfile};type=$my_maven2_type" \
                                            -F "maven2.asset${i}.extension=bar" "http://${my_nexus_url}/service/rest/v1/components?repository=$my_nexus_repository"
    i=i+1
  done
}

################################################
# Configure ACE IS
Configure_ACE_IS () {
  local ns=$1
  ace_bar_secret=${my_ace_barauth_secret}-${my_global_index}
  ace_bar_auth=${my_ace_barauth}-${my_global_index}
  ace_is=${my_ace_is}-${my_global_index}

  # Create secret for barauth
  # Reference : https://www.ibm.com/docs/en/app-connect/containers_cd?topic=resources-configuration-reference#install__install_cli

  #export my_ace_barauth_secret_b64=`base64 -w 0 ${aceconfigdir}ACE-basic-auth.json`
  if oc get secret $ace_bar_secret -n=$ns > /dev/null 2>&1; then mylog ok;else
    oc create secret generic $ace_bar_secret --from-file=configuration="${aceconfigdir}ACE-basic-auth.json" -n=$ns
  fi
  
  # Create a barauth 
  check_create_oc_yaml Configuration $ace_bar_auth ${aceconfigdir}ACE-barauth-${my_global_index}.yaml $ns

 # Create an IS
  check_create_oc_yaml IntegrationServer $ace_is ${aceconfigdir}ACE-IS-${my_global_index}.yaml $ns
  wait_for_oc_state IntegrationServer "$ace_is" Ready '.status.phase' $ns
}

################################################
# Login to both of IBM Cloud and OCS function
# It also create the cluster if it does not exist
# Since the creation steps used here are all idempotent, we have decided to do everything here.
function Login2IBMCloud_and_OpenshiftCluster ()  {
  ##--Log in IBM Cloud
  Login2IBMCloud

  ##--Create openshift cluster
  CreateOpenshiftCluster

  ##-- wait for Cluster availability
  Wait4ClusterAvailability

  ##-- wait for ingress address availability
  Wait4IngressAddressAvailability

  ##-- Login to openshift cluster
  Login2OpenshiftCluster
}

################################################################################################
# Start of the script main entry
################################################################################################

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
ldapdir="${scriptdir}ldap/"
yamldir="${scriptdir}templates/"
subscriptionsdir="${scriptdir}templates/subscriptions/"
capabilitiesdir="${scriptdir}templates/capabilities/"
privatedir="${scriptdir}private/"

#SB]20230214 Ajout des variables de configuration ACE ...
resourcedir="${scriptdir}templates/resources/"
aceconfigdir="${scriptdir}templates/configuration/ACE/"
acebardir="${resourcedir}ACE/Bar/"

if (($# < 3)); then
  echo "the number of arguments should be be 3"
elif (($# > 3)); then
  echo "the number of arguments should be be 3"
else echo "The provided arguments are: $@"
fi

# load helper functions
. "${scriptdir}"lib.sh

#SB]20230201 sometimes we want just to create many ns in the same ic cluster (de, int, prod, ...)
#            so I'll use the namespace name and the cluster name as input parameters to the main script
# example of invocation : ./provision_cluster-v2.sh private/my-cp4i.properties sbtest cp4i-sb-cluster
my_properties_file=$1
my_oc_project=$2
my_cluster_name=$3

read_config_file "$my_properties_file"

##--Log
Login2IBMCloud_and_OpenshiftCluster

##-- Create project namespace.
CreateNameSpace $my_oc_project

##-- add ibm entitlement key to namespace
# SB]20230209 Aspera hsts service cannot be reated because a problem with the entitlement, it muste be added in the openshift-operators namespace.
AddIBMEntitlement $my_op_group_ns
AddIBMEntitlement $my_oc_project

#SB]202300201 https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
##-- instantiate catalog sources
if $my_ibm_pak; then
  Add_Catalog_Sources_ibm_pak
fi

##-- install operators
Install_Operators $my_op_group_ns
#Install_Operators $my_oc_project
#END_COMMENT

##-- instantiate capabilities
Create_Capabilities $my_oc_project

##-- Add OpenLdap app to openshift
oc project $my_oc_project
if $my_install_openldap;then
    check_create_oc_openldap "deployment" "openldap-2441-centos7"
fi

#work in progress
# exit
#SB]20230214 Ajout Configuration ACE
# export my_global_index="04"
# Configure_ACE_IS $my_oc_project
#Configure_ACE_IS cp4i cp4i-ace-is-02 ./tmpl/configuration/ACE/ACE-IS-02.yaml cp4i-ace-barauth-02 ./tmpl/configuration/ACE/ACE-barauth-02.yaml
