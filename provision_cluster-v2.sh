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
  var_fail my_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $my_cluster_name"
  if ibmcloud ks cluster get --cluster $my_cluster_name > /dev/null 2>&1; then 
    mylog ok ", cluster exists"
    mylog info "Checking Openshift cluster took: $SECONDS seconds." 1>&2
  else
    mylog warn ", cluster does not exist"
    var_fail MY_OC_VERSION 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
    var_fail MY_CLUSTER_ZONE 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider classic'
    var_fail MY_CLUSTER_FLAVOR_CLASSIC 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $MY_CLUSTER_ZONE'
    var_fail MY_CLUSTER_WORKERS 'Speficy number of worker nodes in cluster'
    mylog info "Getting current version for OC: $MY_OC_VERSION"
    res=$(check_openshift_version $MY_OC_VERSION)
    if [ -z "$res" ]; then
      mylog error "Failed to find full version for ${MY_OC_VERSION}" 1>&2
      #fix_oc_version
      exit 1
    fi
    res=$(echo "[$res]" | jq -r '.[] | (.major|tostring) + "." + (.minor|tostring) + "." + (.patch|tostring)')
    mylog info "Found: ${res}"
    # create
    mylog info "Creating OpenShift cluster: $my_cluster_name"

    SECONDS=0
    vlans=$(ibmcloud ks vlan ls --zone $MY_CLUSTER_ZONE --output json|jq -j '.[]|" --" + .type + "-vlan " + .id')
    if ! ibmcloud oc cluster create classic \
      --name    $my_cluster_name \
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
  export TF_VAR_openshift_cluster_name="$my_cluster_name"
  pushd terraform
  terraform init
  terraform apply -var-file=var_override.tfvars
  popd
}

################################################
# TBC
function create_openshift_cluster () {
  var_fail MY_CLUSTER_INFRA 'mylog warn "Choose one of: classic or vpc" 1>&2'
  case "${MY_CLUSTER_INFRA}" in
  classic)
    create_openshift_cluster_classic
    gbl_ingress_hostname_filter=.ingressHostname
    gbl_cluster_url_filter=.serverURL
    ;;
  vpc)
    create_openshift_cluster_vpc
    gbl_ingress_hostname_filter=.ingress.hostname
    gbl_cluster_url_filter=.masterURL
    ;;
  *)
    mylog error "Only classic and vpc for MY_CLUSTER_INFRA"
    ;;
  esac
}

################################################
# wait for ingress address availability
function wait_4_ingress_address_availability () {
  SECONDS=0
  
  mylog check "Checking Ingress address"
  firsttime=true
  case $MY_CLUSTER_INFRA in

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
    # It takes about 15 minutes (21 Aug 2023)
	  sleep 90
  done
  mylog info "Checking Ingress availability took $SECONDS seconds to execute." 1>&2
}

################################################
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
function add_ibm_entitlement () {
  local lf_in_ns=$1
  mylog check "Checking ibm-entitlement-key in $lf_in_ns"
  if oc get secret ibm-entitlement-key --namespace=$lf_in_ns > /dev/null 2>&1
  then mylog ok
  else
    var_fail MY_ENTITLEMENT_KEY "Missing entitlement key"
    mylog info "Checking ibm-entitlement-key validity"
    docker -h > /dev/null 2>&1
    if test $? -eq 0 && ! echo $MY_ENTITLEMENT_KEY | docker login cp.icr.io --username cp --password-stdin;then
      mylog error "Invalid entitlement key" 1>&2
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $lf_in_ns"
    if ! oc create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io --namespace=$lf_in_ns;then
      exit 1
    fi
  fi
}

################################################
# add catalog sources using ibm_pak plugin
function add_catalog_sources_ibm_pak () {
  local lf_in_ns=$1
  
  ## ibm-integration-platform-navigator
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  if $MY_NAVIGATOR;then
    check_add_cs_ibm_pak ibm-integration-platform-navigator MY_NAVIGATOR_CASE amd64
  fi

  # ibm-integration-asset-repository
  if $MY_ASSETREPO;then
    check_add_cs_ibm_pak ibm-integration-asset-repository MY_ASSETREPO_CASE amd64
  fi

  # SB]20231204 https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=cluster-mirroring-images-bastion-host
  # For Datapower operator, take care about this note (from above link) :
  # (1) The IBM API Connect CASE also mirrors the IBM DataPower Gateway CASE using the Cloud Pak for Integration image group.
  # (2) The IBM DataPower Gateway CASE contains multiple image groups. To mirror images for Cloud Pak for Integration, use the ibmdpCp4i image group.
  # the following link https://www.ibm.com/docs/en/datapower-operator/1.8?topic=install-case
  # provides a sample when installing datapower operator :
  # https://www.ibm.com/docs/en/datapower-operator/1.8?topic=install-case
  # Note: When deploying within IBM Cloud Pak for Integration, use image group ibmdpCp4i.
  # oc ibm-pak generate mirror-manifests $CASE_NAME --version $CASE_VERSION $TARGET_REGISTRY --filter ibmdpCp4i
  # The question : suppose we have installed the datapower operator case first, does the apic operator case installation overrides it ? 
  # ibm-adatapower
  if $MY_DPGW;then
    check_add_cs_ibm_pak ibm-datapower-operator MY_DPGW_CASE amd64
  fi

  # ibm-appconnect
  if $MY_ACE;then
    check_add_cs_ibm_pak ibm-appconnect MY_ACE_CASE amd64
  fi

  # ibm-apiconnect
  if $MY_APIC;then
    check_add_cs_ibm_pak ibm-apiconnect MY_APIC_CASE amd64
  fi

  # ibm-cp-common-services
  if $MY_COMMONSERVICES;then
    check_add_cs_ibm_pak ibm-cp-common-services MY_COMMONSERVICES_CASE amd64
  fi 

  ## event endpoint management
  ## to get the name of the pak to use : oc ibm-pak list
  ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
  if $MY_EEM;then
    check_add_cs_ibm_pak ibm-eventendpointmanagement MY_EEM_CASE amd64
    #oc ibm-pak launch ibm-eventendpointmanagement --version $MY_EEM_CASE --inventory eemOperatorSetup --action installCatalog -n $lf_in_ns
  fi 

  if $MY_EP;then
    # event processing
    check_add_cs_ibm_pak ibm-eventprocessing MY_EP_CASE amd64
    oc ibm-pak launch ibm-eventprocessing --version $MY_EP_CASE --inventory epOperatorSetup --action installCatalog -n  $lf_in_ns
  fi

  # ibm-eventstreams 
  if $MY_ES;then
    check_add_cs_ibm_pak ibm-eventstreams MY_ES_CASE amd64
  fi 

  if $MY_FLINK;then
    ## SB]20231020 For Flink and Event processing first you have to apply the catalog source to your cluster :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter Applying catalog sources to your cluster
    # event flink
    check_add_cs_ibm_pak ibm-eventautomation-flink MY_FLINK_CASE amd64
    oc ibm-pak launch ibm-eventautomation-flink --version $MY_FLINK_CASE --inventory flinkKubernetesOperatorSetup --action installCatalog -n $lf_in_ns
  fi 

  # ibm-aspera-hsts-operator
  if $MY_HSTS;then
    check_add_cs_ibm_pak ibm-aspera-hsts-operator MY_HSTS_CASE amd64
  fi

  # ibm-license-server
  if $MY_LIC_SRV;then
    check_add_cs_ibm_pak ibm-licensing MY_LIC_SRV_CASE amd64
  fi 

  # ibm-mq
  if $MY_MQ;then
    check_add_cs_ibm_pak ibm-mq MY_MQ_CASE amd64
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
function install_fs_catalogsources () {
  ## SB]20231129 create config map for foundational services
  #lf_type="configmap"
  #lf_cr_name="common-service-maps"
  #lf_yaml_file="${RESOURCSEDIR}common-service-cm.yaml"
  #lf_namespace="kube-public"
  #check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  
  #mylog info "==== Redhat Cert Manager catalog." 1>&2
  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="redhat-operators"
  lf_catalogsource_dspname="Red Hat Operators"
  lf_catalogsource_image="registry.redhat.io/redhat/redhat-operator-index:v4.12"
  lf_catalogsource_publisher="Red Hat"
  lf_catalogsource_interval="10m"
  create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

  #mylog info "==== Foundational services catalog source." 1>&2
  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="opencloud-operators"
  lf_catalogsource_dspname="IBMCS Operators"
  lf_catalogsource_image="icr.io/cpopen/ibm-common-service-catalog:4.3"
  lf_catalogsource_publisher="IBM"
  lf_catalogsource_interval="45m"
  create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"
  
  #mylog info "==== Adding Licensing service catalog source in ns : openshift-marketplace." 1>&2
  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="ibm-licensing-catalog"
  lf_catalogsource_dspname="ibm-licensing"
  lf_catalogsource_image="icr.io/cpopen/ibm-licensing-catalog"
  lf_catalogsource_publisher="IBM"
  lf_catalogsource_interval="45m"
  create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"
}

function install_fs_operators () {

  local lf_operator_name lf_current_chl lf_catalogsource_name lf_operator_namespace lf_strategy lf_type

  # SB]20231215 Pour obtenir le template de l'operateur cert-manager de Redhat, je l'ai installé avec la console, j'ai récupéré le Yaml puis désinstallé.
  lf_operator_name="openshift-cert-manager-operator"
  lf_current_chl=$MY_CERT_MANAGER_CHL
  lf_catalog_source_name="redhat-operators"
  lf_namespace=$MY_CERT_MANAGER_NAMESPACE
  lf_strategy="Automatic"
  lf_startingcsv=$MY_CERT_MANAGER_STARTINGCSV
  create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_namespace}" "${lf_strategy}" "${lf_startingcsv}"

  # ATTENTION : pour le licensing server ajouter dans la partie spec.startingCSV: ibm-licensing-operator.v4.2.1 (sinon erreur).
  lf_operator_name="ibm-licensing-operator-app"
  lf_current_chl=$MY_LIC_SRV_CHL
  lf_catalog_source_name="ibm-licensing-catalog"
  lf_namespace=$MY_LICENSE_SERVER_NAMESPACE
  lf_strategy="Automatic"
  lf_startingcsv=$MY_LICENSING_OPERATOR_STARTINGCSV
  create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_namespace}" "${lf_strategy}" "${lf_startingcsv}"


  # Pour les operations suivantes : utiliser un seul namespace
  #lf_namespace=$MY_COMMON_SERVICES_NAMESPACE
  lf_namespace=$MY_OPERATORS_NAMESPACE

  #create_operator_subscription "ibm-common-service-operator" $MY_COMMONSERVICES_CHL "opencloud-operators" $MY_COMMON_SERVICES_NAMESPACE "Automatic" $MY_STARTING_CSV
  lf_operator_name="ibm-common-service-operator"
  lf_current_chl=$MY_COMMONSERVICES_CHL
  lf_catalog_source_name="opencloud-operators"
  lf_strategy="Automatic"
  lf_startingcsv=$MY_COMMONSERVICES_OPERATOR_STARTINGCSV
  create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_namespace}" "${lf_strategy}" "${lf_startingcsv}"
 
  ## Setting hardware  Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
  #accept_license_fs $MY_OPERATORS_NAMESPACE
  accept_license_fs $lf_namespace

  # Configuring foundational services by using the CommonService custom resource.
  lf_type="CommonService"
  lf_cr_name=$MY_COMMONSERVICES_INSTANCE_NAME
  lf_yaml_file="${RESOURCSEDIR}foundational-services-cr.yaml"
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
}

################################################
# Install Operators
## name = "Literal name", https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=operators-installing-using-cli#operators-available
## MY_CURRENT_CHL = "Operator channel", : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=reference-operator-channel-versions-this-release
## MY_CATALOG_SOURCE_NAME = catalog source created for this operator : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
# @param ns: namespace to install the operators
# resource is the result of the check_resource_availability command
# SB]20231129 Adding the IBM Cloud Pak Foundational Services operator
function install_operators () {

  # Creating DP Gateway operator subscription
  ## SB]202302001 attention au dp la souscription porte un nom particulier voir la variable dp ci-dessous
  ## SB]20231204 je me débarrasse du dp=${MY_OPERATOR_NAME}-${MY_CURRENT_CHL}-${MY_CATALOG_SOURCE_NAME}-openshift-marketplace
  if $MY_DPGW;then
    lf_operator_name="datapower-operator"
    lf_current_chl=$MY_DPGW_CHL
    lf_catalog_source_name="ibm-datapower-operator-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_DPGW_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  # Creating Navigator operator subscription
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  if $MY_NAVIGATOR;then
    lf_operator_name="ibm-integration-platform-navigator"
    lf_current_chl=$MY_NAVIGATOR_CHL
    lf_catalog_source_name="ibm-integration-platform-navigator-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_NAVIGATOR_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  # Creating ACE operator subscription
  if $MY_ACE;then
    lf_operator_name="ibm-appconnect"
    lf_current_chl=$MY_ACE_CHL
    lf_catalog_source_name="appconnect-operator-catalogsource"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_ACE_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  # Creating APIC operator subscription 
  if $MY_APIC;then
    lf_operator_name="ibm-apiconnect"
    lf_current_chl=$MY_APIC_CHL
    lf_catalog_source_name="ibm-apiconnect-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_APIC_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  # Creating Asset Repository operator subscription
  if $MY_ASSETREPO;then
    lf_operator_name="ibm-integration-asset-repository"
    lf_current_chl=$MY_ASSETREPO_CHL
    lf_catalog_source_name="ibm-integration-asset-repository-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_ASSETREPO_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  # Creating Event Endpoint Management operator subscription
  if $MY_EEM;then
    lf_operator_name="ibm-eventendpointmanagement"
    lf_current_chl=$MY_EEM_CHL
    lf_catalog_source_name="ibm-eventendpointmanagement-catalog"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_EEM_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  ## SB]20231020 For Flink and Event processing install the operator with the following command :
  ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter : Install the operator by using the CLI (oc ibm-pak)
  ## event flink
  ## Creating Eventautomation Flink operator subscription

  if $MY_FLINK;then
    lf_inventory="flinkKubernetesOperatorSetup"
    lf_resource_name="ibm-eventautomation-flink"
    lf_namespace=$MY_OPERATORS_NAMESPACE
    lf_path="{.status.phase}"
    lf_state="Succeeded"
    lf_type="clusterserviceversion" 
    lf_version=$MY_FLINK_CASE
    lf_startingcsv=$MY_FLINK_OPERATOR_SARTINGCSV
    create_ea_operators "${lf_inventory}" "${lf_resource_name}" "${lf_namespace}" "${lf_path}" "${lf_state}" "${lf_type}" "${lf_version}" "${lf_startingcsv}"
  fi

  ## event processing
  ## Creating Event processing operator subscription
  if $MY_EP;then
    lf_inventory="epOperatorSetup"
    lf_resource_name="ibm-eventprocessing"
    lf_namespace=$MY_OPERATORS_NAMESPACE
    lf_path="{.status.phase}"
    lf_state="Succeeded"
    lf_type="clusterserviceversion" 
    lf_version=$MY_EP_CASE
    create_ea_operators "${lf_inventory}" "${lf_resource_name}" "${lf_namespace}" "${lf_path}" "${lf_state}" "${lf_type}" "${lf_version}"
  fi 

  # Creating EventStreams operator subscription 
  if $MY_ES;then
    lf_operator_name="ibm-eventstreams"
    lf_current_chl=$MY_ES_CHL
    lf_catalog_source_name="ibm-eventstreams"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_ES_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  # Creating MQ operator subscription
  if $MY_MQ;then
    lf_operator_name="ibm-mq"
    lf_current_chl=$MY_MQ_CHL
    lf_catalog_source_name="ibmmq-operator-catalogsource"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_MQ_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  # Creating Aspera HSTS operator subscription
  if $MY_HSTS;then
    lf_operator_name="aspera-hsts-operator"
    lf_current_chl=$MY_HSTS_CHL
    lf_catalog_source_name="aspera-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_HSTS_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi


  #SB]20230130 Ajout du repository Nexus
  # Creating Nexus operator subscription
  if $MY_NEXUS;then
    lf_operator_name="nxrm-operator-certified"
    lf_current_chl=$MY_NEXUS_CHL
    lf_catalog_source_name="certified-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_EEM_OPERATOR_STARTINGCSV
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi

  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA;then
    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    lf_operator_name="instana-agent-operator"
    lf_current_chl=$MY_INSTANA_CHL
    lf_catalog_source_name="certified-operators"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_strategy="Automatic"
    lf_startingcsv=$MY_EEM_OPERATOR_STARTINGCSV
    create_namespace $MY_INSTANA_AGENT_NAMESPACE    oc adm policy add-scc-to-user privileged -z instana-agent -n $MY_INSTANA_AGENT_NAMESPACE    
    create_operator_subscription "${lf_operator_name}" "${lf_current_chl}" "${lf_catalog_source_name}" "${lf_operator_namespace}" "${lf_strategy}" "${lf_startingcsv}"
  fi
}

################################################
# create capabilities
# @param ns namespace where capabilities are created
function install_operands () {

  # SB]20231201 Creating OperandRequest for foundational services
  # SB]20231211 Creating IBM License Server Reporter Instance
  #             https://www.ibm.com/docs/en/cloud-paks/foundational-services/3.23?topic=reporter-deploying-license-service#lrcmd
  #if $MY_COMMONSERVICES;then
  #  lf_file="${OPERANDSDIR}OperandRequest.yaml"
  #  lf_ns="${MY_COMMON_SERVICES_NAMESPACE}"
  #  lf_path="{.status.phase}"
  #  lf_resource="$MY_COMMONSERVICES_INSTANCE_NAME"
  #  lf_state="Succeeded"
  #  lf_type="commonservice"
  #  create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  #fi

  # Creating Navigator instance
  if $MY_NAVIGATOR_INSTANCE;then
    lf_file="${OPERANDSDIR}Navigator-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_NAVIGATOR_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="PlatformNavigator"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  # Creating Integration Assembly instance
  if $MY_INTASSEMBLY;then
    lf_file="${OPERANDSDIR}IntegrationAssembly-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_INTASSEMBLY_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IntegrationAssembly"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi
  
  # Creating ACE Dashboard instance
  if $MY_ACE;then
    lf_file="${OPERANDSDIR}ACE-Dashboard-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DASHBOARD_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="Dashboard"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"    
  fi
  
  # Creating ACE Designer instance
  if $MY_ACE;then
    lf_file="${OPERANDSDIR}ACE-Designer-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DESIGNER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="DesignerAuthoring"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  # Creating Aspera HSTS instance
  if $MY_HSTS;then
    oc apply -f "${OPERANDSDIR}AsperaCM-cp4i-hsts-prometheus-lock.yaml"
    oc apply -f "${OPERANDSDIR}AsperaCM-cp4i-hsts-engine-lock.yaml"

    lf_file="${OPERANDSDIR}AsperaHSTS-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_HSTS_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IbmAsperaHsts"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  # Creating APIC instance
  if $MY_APIC;then
    lf_file="${OPERANDSDIR}APIC-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_APIC_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="APIConnectCluster"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  # Creating Asset Repository instance
  if $MY_ASSETREPO;then
    lf_file="${OPERANDSDIR}AR-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_ASSETREPO_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="AssetRepository"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  # Creating Event Streams instance
  if $MY_ES;then
    lf_file="${OPERANDSDIR}ES-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_ES_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventStreams"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  # Creating EventEndpointManager instance (Event Processing)
  if $MY_EEM;then
    lf_file="${OPERANDSDIR}EEM-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EEM_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventEndpointManagement"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  export my_eem_manager_gateway_route=$(oc get eem $MY_EEM_INSTANCE_NAME -n $MY_OC_PROJECT -o jsonpath='{.status.endpoints[1].uri}')
  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW;then
    lf_file="${OPERANDSDIR}EG-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EGW_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventGateway"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  ## SB]20231023 Creation of Event automation Flink PVC and instance
  if $MY_FLINK;then
    # Even if it's a pvc we use the same generic function
    lf_file="${OPERANDSDIR}EA-Flink-PVC.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="ibm-flink-pvc"
    lf_state="Bound"
    lf_type="PersistentVolumeClaim"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"

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
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  ## SB]20231023 to check the status of Event processing : https://ibm.github.io/event-automation/ep/installing/post-installation/
  ## The Status column displays the current state of the EventProcessing custom resource. 
  ## When the Event Processing instance is ready, the phase displays Phase: Running.
  ## Creating EventProcessing instance (Event Processing)
  ## oc get eventprocessing <instance-name> -n <namespace> -o jsonpath='{.status.phase}'

  if $MY_EP;then
    lf_file="${OPERANDSDIR}EP-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_EP_INSTANCE_NAME"
    lf_state="Running"
    lf_type="EventProcessing"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi

  ## Creating Nexus Repository instance (An open source repository for build artifacts)
  if $MY_NEXUS;then
    lf_file="${OPERANDSDIR}Nexus-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="[.status.conditions[].type][1]"
    lf_resource="$MY_NEXUS_INSTANCE_NAME"
    lf_state="Deployed"
    lf_type="NexusRepo"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"

    # add route to access Nexus from outside cluster
    lf_type="Route"
    lf_cr_name=$MY_NEXUS_ROUTE_NAME
    lf_yaml_file="${OPERANDSDIR}Nexus-Route.yaml"
    lf_namespace=$MY_OC_PROJECT
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    mylog info "Creation of Route (Nexus) took $SECONDS seconds to execute." 1>&2
  fi

  # Creating Instana agent
  if $MY_INSTANA;then
    lf_file="${OPERANDSDIR}Instana-Agent-CloudIBM-Capability.yaml" 
    lf_ns="${MY_INSTANA_AGENT_NAMESPACE}"
    lf_path="{.status.numberReady}"
    lf_resource="$MY_INSTANA_INSTANCE_NAME"
    lf_state="$MY_CLUSTER_WORKERS"
    lf_type="InstanaAgent"
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}"
  fi
}

################################################
# start customization
# @param ns namespace where operands were instantiated
function start_customization () {
  local ns=$1
  local varb64
  
  if $MY_ACE_CUSTOM;then
    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    generate_files $ACE_TMPL_CUSTOMDIR $ACE_GEN_CUSTOMDIR
  fi

  if $MY_APIC_CUSTOM;then
    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    generate_files $APIC_TMPL_CUSTOMDIR $APIC_GEN_CUSTOMDIR
  fi

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
    generate_files $ES_TMPL_CUSTOMDIR $ES_GEN_CUSTOMDIR

    # SB]20231211 https://ibm.github.io/event-automation/es/installing/installing/
    # Question : Do we have to create this configmap before installing ES or even after ? Used for monitoring
    lf_type="configmap"
    lf_cr_name="cluster-monitoring-config"
    lf_yaml_file="${RESOURCSEDIR}openshift-monitoring-cm.yaml"
    lf_namespace="openshift-monitoring"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  fi

  ## Creating EEM users and roles
  if $MY_EEM_CUSTOM;then
    # generate properties files
    cat  $EEM_TMPL_USER_CREDENTIALS_CUSTOMFILE | envsubst >  $EEM_GEN_USER_CREDENTIALS_CUSTOMFILE
    cat  $EEM_TMPL_USER_ROLES_CUSTOMFILE | envsubst >  $EEM_GEN_USER_ROLES_CUSTOMFILE

    # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
    # user credentials
    varb64=$(cat "$EEM_GEN_USER_CREDENTIALS_CUSTOMFILE" | base64 -w0)
    oc patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]" -n $ns

    # user roles
    varb64=$(cat "$EEM_GEN_USER_ROLES_CUSTOMFILE" | base64 -w0)
    oc patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]" -n $ns
  fi

  ## Creating Event Processing users and roles
  if $MY_EP_CUSTOM;then
    # generate properties files
    cat  $EP_TMPL_USER_CREDENTIALS_CUSTOMFILE | envsubst >  $EP_GEN_USER_CREDENTIALS_CUSTOMFILE
    cat  $EP_TMPL_USER_ROLE_CUSTOMFILE | envsubst >  $EP_GEN_USER_ROLES_CUSTOMFILE

    # user credentials
    varb64=$(cat "$EP_GEN_USER_CREDENTIALS_CUSTOMFILE" | base64 -w0)
    oc patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]" -n $ns

    # user roles
    varb64=$(cat "$EP_GEN_USER_ROLES_CUSTOMFILE" | base64 -w0)
    oc patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]" -n $ns
  fi
}

################################################
# launch customization
# @param ns namespace where operands were instantiated
function launch_customization () {
    if $MY_APIC_CUSTOM;then
    $APIC_GEN_CUSTOMDIR/scripts/configure.sh
  fi
}


##SB]20230215 load bar files in nexus repository
################################################
# Load bar files into nexus repository
function load_ace_bars () {
  # the input parameters :
  # - the directory containing the bar files to be loaded

  local ns=$1
  local directory=$2

  export my_nexus_url=`oc get route $MY_NEXUS_ROUTE_NAME -n $ns -o jsonpath='{.spec.host}'`

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
  if oc get secret $ace_bar_secret -n=$ns > /dev/null 2>&1; then mylog ok;else
    oc create secret generic $ace_bar_secret --from-file=configuration="${ACE_CONFIGDIR}ACE-basic-auth.json" -n=$ns
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

######################################################################
# Create openshift cluster if it does not exist
# and wait for both availability of the cluster and the ingress address
function create_openshift_cluster_wait_4_availability () {
  # Create openshift cluster
  create_openshift_cluster

  # Wait for Cluster availability
  wait_for_cluster_availability

  # Wait for ingress address availability
  wait_4_ingress_address_availability
}

################################################
# Add OpenLdap app to openshift
function add_openldap () {
  #oc project $MY_OC_PROJECT
  if $MY_LDAP;then
      check_create_oc_openldap "deployment" "openldap" "ldap"
  fi
}

################################################
# Display information to access CP4I
function display_access_info () {
  # Always display the platform console endpoint
  cp_console_url=$(oc -n ${my_oc_fs_project} get Route -o=jsonpath='{.items[?(@.metadata.name=="cp-console")].spec.host}')
  mylog info "Cloup Pak Console endpoint: ${cp_console_url}"
  cp_console_admin_pwd=$(oc -n ${my_oc_fs_project} get secret platform-auth-idp-credentials -o jsonpath='{.data.admin_password}' | base64 -d)
  mylog info "Cloup Pak Console admin password: ${cp_console_admin_pwd}"

  if $MY_NAVIGATOR;then
    get_navigator_access
  fi

  if $MY_ACE;then
    ace_ui_db_url=$(oc get Dashboard -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="Dashboard")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "ACE Dahsboard UI endpoint: " $ace_ui_db_url
    ace_ui_dg_url=$(oc get DesignerAuthoring -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="DesignerAuthoring")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "ACE Designer UI endpoint: " $ace_ui_dg_url
  fi	

  if $MY_APIC;then
    gtw_url=$(oc get GatewayCluster -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].status.endpoints[?(@.name=="gateway")].uri}')
	  mylog info "APIC Gateway endpoint: ${gtw_url}"
    apic_gtw_admin_pwd_secret_name=$(oc get GatewayCluster -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].spec.adminUser.secretName}')
    cm_admin_pwd=$(oc get secret ${apic_gtw_admin_pwd_secret_name} -n $MY_OC_PROJECT -o jsonpath={.data.password} | base64 -d)
	  mylog info "APIC Gateway admin password: ${cm_admin_pwd}"
    cm_url=$(oc get APIConnectCluster -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="admin")].uri}')
	  mylog info "APIC Cloud Manager endpoint: ${cm_url}"
    cm_admin_pwd_secret_name=$(oc get ManagementCluster -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="ManagementCluster")].spec.adminUser.secretName}')
    cm_admin_pwd=$(oc get secret ${cm_admin_pwd_secret_name} -n $MY_OC_PROJECT -o jsonpath='{.data.password}' | base64 -d)
    mylog info "APIC Cloud Manager admin password: ${cm_admin_pwd}"
    mgr_url=$(oc get APIConnectCluster -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "APIC API Manager endpoint: ${mgr_url}" 
    ptl_url=$(oc get PortalCluster -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="PortalCluster")].status.endpoints[?(@.name=="portalWeb")].uri}')
    mylog info "APIC Web Portal root endpoint: ${ptl_url}"
  fi

  if $MY_EEM;then
    eem_ui_url=$(oc get EventEndpointManagement -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "Event Endpoint Management UI endpoint: ${eem_ui_url}"
    eem_gtw_url=$(oc get EventEndpointManagement -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="gateway")].uri}')
	  mylog info "Event Endpoint Management Gateway endpoint: ${eem_gtw_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi

  if $MY_ES;then
    es_ui_url=$(oc get EventStreams -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "Event Streams Management UI endpoint: ${es_ui_url}"
    es_admin_url=$(oc get EventStreams -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="admin")].uri}')
	  mylog info "Event Streams Management admin endpoint: ${es_admin_url}"
    es_apicurioregistry_url=$(oc get EventStreams -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="apicurioregistry")].uri}')
	  mylog info "Event Streams Management apicurio registry endpoint: ${es_apicurioregistry_url}" 
    es_restproducer_url=$(oc get EventStreams -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="restproducer")].uri}')
	  mylog info "Event Streams Management REST Producer endpoint: ${es_restproducer_url}"
    es_bootstrap_urls=$(oc get EventStreams -n $MY_OC_PROJECT -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.kafkaListeners[*].bootstrapServers}')
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
    licensing_service_url=$(oc -n ${my_oc_fs_project} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-licensing-service-instance")].spec.host}')
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
  echo "oc get commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} -n ${lf_in_namespace} -o jsonpath='{.spec.license.accept}'"
  accept=$(oc get commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} -n ${lf_in_namespace} -o jsonpath='{.spec.license.accept}')
  echo "accept=$accept"
  if [ "$accept" == "true" ]; then
    mylog info "license already accepted." 1>&2
  else
    oc patch commonservice ${MY_COMMONSERVICES_INSTANCE_NAME} --namespace ${lf_in_namespace} --type merge -p '{"spec": {"license": {"accept": true}}}'
  fi
}

################################################
# Log in IBM Cloud
function login_2_ibm_cloud () {
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
    mylog check "Login to cluster"
    # SB 20231208 The following command sets your command line context for the cluster and download the TLS certificates and permission files for the administrator.
    # more details here : https://cloud.ibm.com/docs/openshift?topic=openshift-access_cluster#access_public_se
    ibmcloud ks cluster config --cluster ${my_cluster_name} --admin
    while ! oc login -u apikey -p $MY_IC_APIKEY --server=$my_cluster_url > /dev/null;do
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
# @param my_properties_file: file path and name of the properties file
# @param MY_OC_PROJECT: namespace where to create the operators and capabilities
# @param my_cluster_name: name of the cluster
# example of invocation: ./provision_cluster-v2.sh private/my-cp4i.properties sbtest cp4i-sb-cluster
# other example: ./provision_cluster-v2.sh cp4i.properties ./versions/cp4i-2023.4.properties cp4i sb20240102
# other example: ./provision_cluster-v2.sh cp4i.properties ./versions/cp4i-2023.4.properties cp4i cp4iad22023
my_properties_file=$1
my_versions_file=$2
export MY_OC_PROJECT=$3
my_cluster_name=$4

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
MAINSCRIPTDIR=$(dirname "$0")/

if [ $# -ne 4 ]; then
  echo "the number of arguments should be 4 : properties_file versions_file namespace cluster "
  exit
else echo "The provided arguments are: $@"
fi

# load helper functions
. "${MAINSCRIPTDIR}"lib.sh

# Read all the properties
read_config_file "$my_properties_file"

#SB]20230104 test monospace
#export MY_OPERATORS_NAMESPACE=$MY_OC_PROJECT

# Read versions properties
read_config_file "$my_versions_file"

# Read user file properties
my_user_file="${PRIVATEDIR}user.properties"
read_config_file "$my_user_file"

# : <<'END_COMMENT'

# check the differents pre requisites
check_exec_prereqs

# Log to IBM Cloud
login_2_ibm_cloud

# Create Openshift cluster
create_openshift_cluster_wait_4_availability

# Log to openshift cluster
login_2_openshift_cluster

# END_COMMENT
# Instantiate catalog sources

mylog info "==== Adding catalog sources using ibm pak plugin." 1>&2
add_catalog_sources_ibm_pak $MY_CATALOGSOURCES_NAMESPACE

# Create project namespace.
# SB]20231213 erreur obtenue juste après la création du cluster openshift : Error from server (Forbidden): You may not request a new project via this API.
# Solution : https://stackoverflow.com/questions/51657711/openshift-allow-serviceaccount-to-create-project
#          : https://stackoverflow.com/questions/44349987/error-from-server-forbidden-error-when-creating-clusterroles-rbac-author
#          : https://bugzilla.redhat.com/show_bug.cgi?id=1639197
# extrait du lien ci-dessus:
# You'll need to add the "self-provisioner" role to your service account as well. Although you've made it project admin, that only means its admin rights are scoped to that one project, which is not enough to allow it to request new projects.
# oc adm policy add-cluster-role-to-user self-provisioner system:serviceaccount:<project>:<cx-jenkins
# oc create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=IAM#saad.benachi@fr.ibm.com
oc create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=$MY_USER
oc adm policy add-cluster-role-to-user self-provisioner $MY_USER -n $MY_OC_PROJECT

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
# SB]20230209 Aspera hsts service cannot be created because a problem with the entitlement, it muste be added in the openshift-operators namespace.
add_ibm_entitlement $MY_OC_PROJECT
add_ibm_entitlement $MY_OPERATORS_NAMESPACE

#SB]20231214 Installing Foundation services
mylog info "==== Installation of foundational services." 1>&2
install_fs_catalogsources
install_fs_operators

# Install operators
mylog info "==== Installation of capability operators." 1>&2
install_operators

#SB]20231213 pour la version 2023.4 https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=SSGT7J_23.4/upgrade/upgrade_dummy_binding.htm
# Installing keycloak
#mylog info "==== Installation of keycloak. TBD" 1>&2
#check_create_oc_yaml "Cp4iServicesBinding" "manual-binding-for-iam" "${RESOURCSEDIR}keycloak.yaml" $MY_OC_PROJECT

# Add OpenLdap app to openshift
mylog info "==== Adding OpenLdap." 1>&2
add_openldap

# Instantiate operands
mylog info "==== Installation of operands." 1>&2
install_operands

## Display information to access CP4I
mylog info "==== Displaying Access Info to CP4I." 1>&2
display_access_info

# Start customization
mylog info "==== Customization." 1>&2
start_customization $MY_OC_PROJECT

#work in progress
#SB]20230214 Ajout Configuration ACE
# export my_global_index="04"
# configure_ace_is $MY_OC_PROJECT
#configure_ace_is cp4i cp4i-ace-is-02 ./tmpl/configuration/ACE/ACE-IS-02.yaml cp4i-ace-barauth-02 ./tmpl/configuration/ACE/ACE-barauth-02.yaml
