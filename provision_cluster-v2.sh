#!/bin/bash
# Laurent 2021

################################################
# Create openshift cluster using classic infra function
CreateOpenshiftClusterClassic () {
  var_fail my_ic_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $my_ic_cluster_name"
  if ibmcloud ks cluster get --cluster $my_ic_cluster_name > /dev/null 2>&1; then mylog ok ", cluster exists"; else
    mylog warn ", cluster does not exist"
    var_fail my_oc_version 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
    var_fail my_cluster_zone 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider classic'
    var_fail my_cluster_flavor_classic 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $my_cluster_zone'
    var_fail my_cluster_workers 'Speficy number of worker nodes in cluster'
    mylog info "Getting current version for OC: $my_oc_version"
    local oc_version_full=$(ibmcloud ks versions -q --show-version OpenShift|sed -Ene "s/^(${my_oc_version//./\\.}\.[^ ]*) .*$/\1/p")
    if test -z "${oc_version_full}";then
      mylog error "Failed to find full version for ${my_oc_version}" 1>&2
      fix_oc_version
      exit 1
    fi
    mylog info "Found: ${oc_version_full}"
    # create
    mylog info "Creating cluster: $my_ic_cluster_name"
    local vlans=$(ibmcloud ks vlan ls --zone $my_cluster_zone --output json|jq -j '.[]|" --" + .type + "-vlan " + .id')
    if ! ibmcloud oc cluster create classic \
      --name    $my_ic_cluster_name \
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
  # set variables for terraform (defined in variables.tf)
  export TF_VAR_ibmcloud_api_key="$my_ic_apikey"
  export TF_VAR_openshift_worker_pool_flavor="$my_cluster_flavor_vpc"
  export TF_VAR_prefix="$my_unique_name"
  export TF_VAR_region="$my_cluster_region"
  export TF_VAR_openshift_version=$(ibmcloud ks versions -q --show-version OpenShift|sed -Ene "s/^(${my_oc_version//./\\.}\.[^ ]*) .*$/\1/p")
  export TF_VAR_resource_group="rg-$my_unique_name"
  export TF_VAR_openshift_cluster_name="$my_ic_cluster_name"
  pushd terraform
  terraform init
  terraform apply -var-file=var_override.tfvars
  popd
}

# Create cluster: classic or VPC
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

################################################
# Create namespace function
CreateNameSpace () {
  var_fail my_oc_project "Please define project name in config"
  mylog check "Checking project $my_oc_project"
  if oc get project $my_oc_project > /dev/null 2>&1; then mylog ok; else
    mylog info "Creating project $my_oc_project"
    if ! oc new-project $my_oc_project; then
      exit 1
    fi
  fi
}

################################################
# add ibm entitlement key to namespace function
AddIBMEntitlement () {
  mylog check "Checking ibm-entitlement-key in $my_oc_project"
  if oc get secret ibm-entitlement-key --namespace=$my_oc_project > /dev/null 2>&1; then mylog ok; else
    mylog no
    var_fail my_entitlement_key "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    docker -h > /dev/null 2>&1
    if test $? -eq 0 && ! echo $my_entitlement_key | docker login cp.icr.io --username cp --password-stdin;then
      mylog error "Invalid entitlement key" 1>&2
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $my_oc_project"
    if ! oc create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$my_entitlement_key --docker-server=cp.icr.io --namespace=$my_oc_project;then
      exit 1
    fi
  fi
}

################################################
# install cloud pak operator function
InstallAllWithCP4IOperator () {
  # TODO: comment: for aspera ?
  check_create_oc_yaml "${subscriptionsdir}Redis-Sub.yaml"

  check_create_oc_yaml "${subscriptionsdir}subscription.yaml"

  # wait for cloud pak main operator availability
  while ! oc get packagemanifest $my_cp4i_operator_name -n openshift-marketplace > /dev/null 2>&1;do
    mylog wait "Package $my_cp4i_operator_name not yet available, waiting..." 1>&2
    sleep 30
  done

  check_resource_availability $my_cp4i_operator_name
  wait_for_oc_state clusterserviceversion $var Succeeded '.status.phase'
}

################################################
# create subscriptions function
Create_Subscriptions () {
  ##-- add CatalogSource resource common-services
  check_create_oc_yaml "${yamldir}operator-source-cs.yaml"
  
  ##-- Create Navigator operator subscription
  $my_install_navigator && check_create_wait_sub_oc_yaml "${subscriptionsdir}Navigator-Sub.yaml"
  
  ##-- Create Operational Dashboard operator subscription
  $my_install_od && check_create_wait_sub_oc_yaml "${subscriptionsdir}Dashboard-Sub.yaml"
  
  ##-- Create ACE operator subscription
  $my_install_ace_dd && check_create_wait_sub_oc_yaml "${subscriptionsdir}ACE-Sub.yaml"
  
  ##-- Create APIC operator subscription
  $my_install_apic && check_create_wait_sub_oc_yaml "${subscriptionsdir}APIC-Sub.yaml"
  
  ##-- Create Asset Repository operator subscription
  $my_install_ar && check_create_wait_sub_oc_yaml "${subscriptionsdir}AR-Sub.yaml"
  
  ##-- Create EventStreams operator subscription
  $my_install_es check_create_wait_sub_oc_yaml "${subscriptionsdir}ES-Sub.yaml"
  
  ##-- Create MQ operator subscription
  $my_install_mq && check_create_wait_sub_oc_yaml "${subscriptionsdir}MQ-Sub.yaml"
  
  ##-- Create Aspera HSTS operator subscription
  # Special for HSTS : install IBM Redis version <1.5.0
  $my_install_hsts && check_create_wait_sub_oc_yaml "${subscriptionsdir}HSTS-Sub.yaml"
  if false && $my_install_hsts;then
    check_create_oc_yaml "${subscriptionsdir}HSTS-Sub.yaml"
    # ici pb avec operateur hsts qui installe une version redis avec le channel v1.2-eus
    # pour corriger patcher vers 1.4 puis supprimer l'ancienne
    check_resource_availability ibm-cloud-databases-redis-operator-v1.2-eus-ibm-operator-catalog-openshift-marketplace
    oc patch subscription ibm-cloud-databases-redis-operator-v1.2-eus-ibm-operator-catalog-openshift-marketplace --type merge -p '{"spec":{"channel":"v1.4"}}'
    oc delete csv ibm-cloud-databases-redis.v1.2.3
    check_resource_availability aspera-hsts-operator
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
# create capabilities function
Create_Capabilities () {
  ##-- Create Navigator instance
  $my_install_navigator && check_create_wait_oc_yaml "${capabilitiesdir}Navigator-Capability.yaml" '.status.conditions[0].type' Ready
  
  ##-- Create Operational Dashboard instance
  $my_install_od && check_create_wait_oc_yaml "${capabilitiesdir}Dashboard-Capability.yaml" '.status.conditions[0].type' Ready
  
  ##-- Create ACE Dashboard instance
  $my_install_ace_dd && check_create_wait_oc_yaml "${capabilitiesdir}ACE-Dashboard-Capability.yaml" '.status.conditions[0].type' Ready
  
  ##-- Create ACE Designer instance
  $my_install_ace_dg && check_create_wait_oc_yaml "${capabilitiesdir}ACE-Designer-Capability.yaml" '.status.conditions[0].type' Ready
  
  ##-- Create MQ instance
  $my_install_mq && check_create_wait_oc_yaml "${capabilitiesdir}MQ-Capability.yaml" '.status.phase' Running
  
  ##-- Create ASpera HSTS instance
  $my_install_hsts && check_create_wait_oc_yaml "${capabilitiesdir}AsperaHSTS-Capability.yaml" '.status.conditions[0].type' Ready
  
  ##-- Create EventStreams instance
  if $my_install_es;then
    check_create_oc_yaml "${capabilitiesdir}ES-kafka-metrics-ConfigMap.yaml"
    check_create_oc_yaml "${capabilitiesdir}ES-zookeeper-metrics-ConfigMap.yaml"
    check_create_wait_oc_yaml "${capabilitiesdir}ES-Capability.yaml" '.status.phase' Ready
  fi
  
  ##-- Create Asset Repository instance
  $my_install_ar && check_create_wait_oc_yaml ${capabilitiesdir}AR-Capability.yaml '.status.phase' Ready
  
  ##-- Create APIC instance
  $my_install_apic && check_create_wait_oc_yaml "${capabilitiesdir}APIC-Capability.yaml" '.status.phase' Ready
}

Create_LDAP(){
  assert_args_fail 0 $#
  local octype=deployment
  local ocname=openldap-2441-centos7
  mylog check "Checking ${octype} ${ocname}"
  if oc get ${octype} ${ocname} > /dev/null 2>&1; then mylog ok;else
    oc new-app openshift/${ocname}
    oc expose service/${ocname}
    oc get service ${ocname} -o json  | jq '.spec.ports[0] += {"Nodeport":30389}' | jq '.spec.ports[1] += {"Nodeport":30686}' | jq '.spec.type |= "NodePort"' | oc apply -f -
    port=`oc get service ${ocname} -o json  | jq -r '.spec.ports[0].nodePort'`
    hostname=`oc get route ${ocname} -o json | jq -r '.spec.host'`
    envsubst < "${ldapdir}Import.tmpl" > "${ldapdir}Import.ldiff"
    ldapmodify -H ldap://$hostname:$port -D "$my_dn_openldap" -w admin -f ${ldapdir}Import.ldiff
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

##-- Create operator group in new namespace (if needed, not global: "global-operators": already exists)
#if [ "$my_oc_operators_project" != openshift-operators ];then
  check_create_oc_yaml "${yamldir}operator-group.yaml"
#fi

##-- add ibm entitlement key to namespace
AddIBMEntitlement

##-- add ibm catalog
check_create_oc_yaml "${yamldir}ibm-operator-catalog.yaml"

if $my_install_all_with_cp4i_operator;then
  InstallAllWithCP4IOperator
else
  ##-- instantiate subscriptions
  Create_Subscriptions
fi

##-- instantiate capabilities
Create_Capabilities 

##-- Add OpenLdap app to openshift
$my_install_openldap && Create_LDAP
