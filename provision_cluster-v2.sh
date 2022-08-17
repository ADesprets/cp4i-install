#!/bin/bash
# Laurent 2021

################################################
# Create openshift cluster using classic infra
CreateOpenshiftClusterClassic () {
  var_fail my_ic_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $my_ic_cluster_name"
  if ibmcloud ks cluster get --cluster $my_ic_cluster_name > /dev/null 2>&1; then mylog ok ", cluster exists"; else
    mylog warn ", cluster does not exist"
    var_fail my_oc_version 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
    var_fail my_cluster_zone 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider classic'
    var_fail my_cluster_flavor 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $my_cluster_zone'
    var_fail my_cluster_workers 'Speficy number of worker nodes in cluster'
    mylog info "Getting current version for OC: $my_oc_version"
    oc_version_full=$(ibmcloud ks versions -q --show-version OpenShift|sed -Ene "s/^(${my_oc_version//./\\.}\.[^ ]*) .*$/\1/p")
    if test -z "${oc_version_full}";then
      mylog error "Failed to find full version for ${my_oc_version}" 1>&2
      fix_oc_version
      exit 1
    fi
    mylog info "Found: ${oc_version_full}"
    # create
    mylog info "Creating cluster: $my_ic_cluster_name"
    vlans=$(ibmcloud ks vlan ls --zone $my_cluster_zone --output json|jq -j '.[]|" --" + .type + "-vlan " + .id')
    if ! ibmcloud oc cluster create classic \
      --name    $my_ic_cluster_name \
      --version $oc_version_full \
      --zone    $my_cluster_zone \
      --flavor  $my_cluster_flavor \
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
# Create openshift cluster using VPC infra
# use terraform because creation is more complex than classic
CreateOpenshiftClusterVPC () {
  var_fail my_oc_version 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
  var_fail my_cluster_zone 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider vpc-gen2'
  var_fail my_cluster_flavor 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $my_cluster_zone'
  var_fail my_cluster_workers 'Speficy number of worker nodes in cluster'
  export TF_VAR_ibmcloud_api_key="$my_ic_apikey"
  export TF_VAR_openshift_worker_pool_flavor="$my_cluster_flavor"
  export TF_VAR_prefix="$my_unique_name"
  export TF_VAR_region="$my_cluster_region"
  export TF_VAR_openshift_version=$(ibmcloud ks versions -q --show-version OpenShift|sed -Ene "s/^(${my_oc_version//./\\.}\.[^ ]*) .*$/\1/p")
  export TF_VAR_resource_group="rg-$my_unique_name"

  pushd terraform
  terraform init
  terraform apply -var-file="testing.auto.tfvars"
  popd
  #echo "CreateOpenshiftClusterVPC: not implemented"
  #exit 1
}

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

Wait4IngressAddressAvailability () {
# wait for ingress address availability
  mylog check "Checking Ingress address"
  firsttime=true
  case $my_cluster_infra in

  esac
  while true;do
  ingress_address=$(ibmcloud ks cluster get --cluster $my_ic_cluster_name --output json|jq -r "$gbl_ingress_hostname_filter")
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

CreateNameSpace () {
################################################
# Create namespace
  var_fail my_oc_project "Please define project name in config"
  mylog check "Checking project $my_oc_project"
  if oc get project $my_oc_project > /dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $my_oc_project"
    if ! oc new-project $my_oc_project; then
      exit 1
    fi
  fi
}

AddIBMEntitlement () {
################################################
# add ibm entitlement key to namespace
  mylog check "Checking ibm-entitlement-key in $my_oc_project"
  if oc get secret ibm-entitlement-key --namespace=$my_oc_project > /dev/null 2>&1; then mylog ok; else
    mylog no
    var_fail my_entitlement_key "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    if ! echo $my_entitlement_key | docker login cp.icr.io --username cp --password-stdin;then
      mylog error "Invalid entitlement key" 1>&2
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $my_oc_project"
    if ! oc create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$my_entitlement_key --docker-server=cp.icr.io --namespace=$my_oc_project;then
      exit 1
    fi
  fi
}

InstallAllWithCP4IOperator () {
################################################
# install cloud pak operator

  # wait for cloud pak main operator availability
  while ! oc get packagemanifest $my_cp4i_operator_name -n openshift-marketplace > /dev/null 2>&1;do
    mylog wait "Package $my_cp4i_operator_name not yet available, waiting..." 1>&2
    sleep 30
  done

  check_create_oc_yaml OperatorGroup "${my_op_group}" "${yamldir}operator-group.yaml"
  check_create_oc_yaml Subscription "${my_subscription}" "${subscriptionsdir}subscription.yaml"

  check_resource_availability clusterserviceversion $my_cp4i_operator_name
  wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
}

Create_Subscriptions () {
################################################
# create subscriptions
##-- Creating Navigator operator subscription
  if $my_install_navigator;then
    check_create_oc_yaml "subscription" ibm-integration-platform-navigator "${subscriptionsdir}Navigator-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion ibm-integration-platform-navigator
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  ##-- Creating Operational Dashboard operator subscription
  if $my_install_od;then
    check_create_oc_yaml "subscription" ibm-integration-operations-dashboard "${subscriptionsdir}Dashboard-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion ibm-integration-operations-dashboard
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  ##-- Creating ACE operator subscription
  if $my_install_ace_dd; then
    check_create_oc_yaml "subscription" ibm-appconnect "${subscriptionsdir}ACE-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion ibm-appconnect
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  ##-- Creating APIC operator subscription
  if $my_install_apic;then
    check_create_oc_yaml "subscription" ibm-apiconnect "${subscriptionsdir}APIC-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion ibm-apiconnect
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  ##-- Creating Asset Repository operator subscription
  if $my_install_ar;then
    check_create_oc_yaml "subscription" ibm-integration-asset-repository "${subscriptionsdir}AR-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion ibm-integration-asset-repository
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  
  ##-- Creating EventStreams operator subscription
  if $my_install_es;then
    check_create_oc_yaml "subscription" ibm-eventstreams "${subscriptionsdir}ES-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion ibm-eventstreams
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  ##-- Creating MQ operator subscription
  if $my_install_mq;then
    check_create_oc_yaml "subscription" ibm-mq "${subscriptionsdir}MQ-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion ibm-mq
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  ##-- Creating Aspera HSTS operator subscription
  # Special for HSTS : install IBM Redis version <1.5.0
  if $my_install_hsts;then
    check_create_oc_yaml "subscription" aspera-hsts-operator "${subscriptionsdir}HSTS-Sub.yaml" $my_oc_project
    check_resource_availability clusterserviceversion aspera-hsts-operator
    # ici pb avec operateur hsts qui installe une version redis avec le channel v1.2-eus
    # pour corriger patcher vers 1.4 puis supprimer l'ancienne
    check_resource_availability clusterserviceversion ibm-cloud-databases-redis-operator-v1.2-eus-ibm-operator-catalog-openshift-marketplace
    oc patch subscription ibm-cloud-databases-redis-operator-v1.2-eus-ibm-operator-catalog-openshift-marketplace --type merge -p '{"spec":{"channel":"v1.4"}}'
    oc delete csv ibm-cloud-databases-redis.v1.2.3
    wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
  fi
  
  # SB problème détecté au niveau de : IBM Automation Foundation Core
  # IBM Automation Foundation Core 1.3.6 provided by IBM qui passait en 'failed'
  # j'ai fini par trouver de fil en aiguille  et voici la solution .... qui n'a pas fonctionné en ligne de commande =>
  # il a fallu faire le update manuel (approuver sur la console Openshift).
  # saad@kubuntu2204:~/Mywork/Scripts$ oc patch subscription ibm-cert-manager-operator -n ibm-common-services --type merge -p '{"spec":{"installPlanApproval":"Automatic"}}'
  #subscription.operators.coreos.com/ibm-cert-manager-operator patched
  #saad@kubuntu2204:~/Mywork/Scripts$
  
}

################################################
# create capabilities
Create_Capabilities () {
  ##-- Creating Navigator instance
  if $my_install_navigator;then
    check_create_oc_yaml PlatformNavigator $my_cp_navigator_instance_name "${capabilitiesdir}Navigator-Capability.yaml" $my_oc_project
    wait_for_oc_state PlatformNavigator "$my_cp_navigator_instance_name" Ready '.status.conditions[0].type'
  fi
  
  
  ##-- Creating Operational Dashboard instance
  if $my_install_od;then
    check_create_oc_yaml OperationsDashboard $my_cp_od_instance_name "${capabilitiesdir}Dashboard-Capability.yaml" $my_oc_project
    wait_for_oc_state OperationsDashboard "$my_cp_od_instance_name" Ready '.status.conditions[0].type'
  fi
  
  ##-- Creating ACE Dashboard instance
  if $my_install_ace_dd;then
    check_create_oc_yaml Dashboard $my_cp_ace_dashboard_instance_name "${capabilitiesdir}ACE-Dashboard-Capability.yaml" $my_oc_project
    wait_for_oc_state Dashboard "$my_cp_ace_dashboard_instance_name" Ready '.status.conditions[0].type'
  fi
  
  ##-- Creating ACE Designer instance
  if $my_install_ace_dg;then
    check_create_oc_yaml DesignerAuthoring $my_cp_ace_designer_instance_name "${capabilitiesdir}ACE-Designer-Capability.yaml" $my_oc_project
    wait_for_oc_state DesignerAuthoring "$my_cp_ace_designer_instance_name" Ready '.status.conditions[0].type'
  fi
  
  ##-- Creating MQ instance
  if $my_install_mq;then
    check_create_oc_yaml QueueManager $my_cp_mq_instance_name "${capabilitiesdir}MQ-Capability.yaml" $my_oc_project
    wait_for_oc_state QueueManager "$my_cp_mq_instance_name" Running '.status.phase'
  fi
  
  
  ##-- Creating ASpera HSTS instance
  if $my_install_hsts;then
    check_create_oc_yaml IbmAsperaHsts $my_cp_hsts_instance_name "${capabilitiesdir}AsperaHSTS-Capability.yaml" $my_oc_project
    wait_for_oc_state IbmAsperaHsts "$my_cp_hsts_instance_name" Ready '.status.conditions[0].type'
  fi
  
  ##-- Creating EventStreams instance
  if $my_install_es;then
    check_create_oc_yaml ConfigMap $my_cp_es_kafka_metricsConfig_name "${capabilitiesdir}ES-kafka-metrics-ConfigMap.yaml" $my_oc_project
    check_create_oc_yaml ConfigMap $my_cp_es_zookeeper_metricsConfig_name "${capabilitiesdir}ES-zookeeper-metrics-ConfigMap.yaml" $my_oc_project
    check_create_oc_yaml EventStreams $my_cp_es_instance_name "${capabilitiesdir}ES-Capability.yaml" $my_oc_project
    wait_for_oc_state EventStreams "$my_cp_es_instance_name" Ready '.status.phase'
  fi
  
  ##-- Creating Asset Repository instance
  if $my_install_ar;then
    check_create_oc_yaml AssetRepository $my_cp_ar_instance_name ${capabilitiesdir}AR-Capability.yaml $my_oc_project
    wait_for_oc_state AssetRepository "$my_cp_ar_instance_name" Ready '.status.phase'
  fi
  
  ##-- Creating APIC instance
  if $my_install_apic;then
    check_create_oc_yaml APIConnectCluster $my_cp_apic_instance_name "${capabilitiesdir}APIC-Capability.yaml" $my_oc_project
    wait_for_oc_state APIConnectCluster "$my_cp_apic_instance_name" Ready '.status.phase'
  fi
}

################################################################################################
# Start of the script main entry
################################################################################################

# end with / on purpose (if var not defined, uses CWD)
scriptdir=$(dirname "$0")/
ldapdir="${scriptdir}ldap/"
yamldir="${scriptdir}tmpl/"
subscriptionsdir="${scriptdir}tmpl/subscriptions/"
capabilitiesdir="${scriptdir}tmpl/capabilities/"
privatedir="${scriptdir}private/"

# load helper functions
. "${scriptdir}"lib.sh

read_config_file "$1"

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


##-- Create namespace
CreateNameSpace

##-- add ibm entitlement key to namespace
AddIBMEntitlement


if $my_install_all_with_cp4i_operator;then
  check_create_oc_yaml_redis "subscription" ibm-cloud-databases-redis-operator "${subscriptionsdir}Redis-Sub.yaml" $my_oc_project
  InstallAllWithCP4IOperator
else
  ##-- add ibm catalog
  check_create_oc_yaml "catalogsource" "ibm-operator-catalog" "${yamldir}ibm-operator-catalog.yaml" $my_oc_cs_ns 
  
  ##-- Creating operator subscriptions
  check_create_oc_yaml "operatorgroup" $my_op_group "${yamldir}operator-group.yaml" $my_oc_project
  
  ##-- add CatalogSource resource common-services
  #check_create_oc_yaml "catalogsource" "opencloud-operators" "${yamldir}operator-source-cs.yaml"
  
  ##-- instantiate subscriptions
  Create_Subscriptions
fi


##-- instantiate capabilities
Create_Capabilities 

##-- Add OpenLdap app to openshift
if $my_install_openldap;then
    check_create_oc_openldap "deployment" "openldap-2441-centos7"
fi

