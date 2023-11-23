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
CreateOpenshiftClusterClassic () {

  SECONDS=0
  var_fail my_cluster_name "Choose a unique name for the cluster"
  mylog check "Checking OpenShift: $my_cluster_name"
  if ibmcloud ks cluster get --cluster $my_cluster_name > /dev/null 2>&1; then 
    mylog ok ", cluster exists"
    mylog info "Checking Openshift cluster took: $SECONDS seconds." 1>&2
  else
    mylog warn ", cluster does not exist"
    var_fail my_oc_version 'mylog warn "Choose one of:" 1>&2;ibmcloud ks versions -q --show-version OpenShift'
    var_fail my_cluster_zone 'mylog warn "Choose one of:" 1>&2;ibmcloud ks zone ls -q --provider classic'
    var_fail my_cluster_flavor_classic 'mylog warn "Choose one of:" 1>&2;ibmcloud ks flavors -q --zone $my_cluster_zone'
    var_fail my_cluster_workers 'Speficy number of worker nodes in cluster'
    mylog info "Getting current version for OC: $my_oc_version"
    oc_version_full=$(ibmcloud ks versions -q --show-version OpenShift|grep $my_oc_version| awk '{print $1}')
    if test -z "${oc_version_full}";then
      mylog error "Failed to find full version for ${my_oc_version}" 1>&2
      fix_oc_version
      exit 1
    fi
    mylog info "Found: ${oc_version_full}"
    # create
    mylog info "Creating OpenShift cluster: $my_cluster_name"

    SECONDS=0
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
    mylog info "Creation of the cluster took: $SECONDS seconds." 1>&2
  fi
}

################################################
# Create openshift cluster using VPC infra
# use terraform because creation is more complex than classic
# function
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
    mylog error "Only classic and vpc for my_cluster_infra"
    ;;
  esac
}

################################################
# wait for ingress address availability
# function
Wait4IngressAddressAvailability () {
  SECONDS=0
  
  mylog check "Checking Ingress address"
  firsttime=true
  case $my_cluster_infra in

  esac

  while true;do
    ingress_address=$(ibmcloud ks cluster get --cluster $my_cluster_name --output json|jq -r "$gbl_ingress_hostname_filter")
	  if test -n "$ingress_address";then
		  mylog ok ", $ingress_address"
      mylog info "Checking Ingress address took: $SECONDS seconds." 1>&2
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
  mylog info "To have ingress available took $SECONDS seconds to execute." 1>&2
}

################################################
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
# function
AddIBMEntitlement () {
  local ns=$1
  mylog check "Checking ibm-entitlement-key in $ns"
  if oc get secret ibm-entitlement-key --namespace=$ns > /dev/null 2>&1
  then mylog ok
  else
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
  local ns=$1

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

  ## event endpoint management
  ## to get the name of the pak to use : oc ibm-pak list
  ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
  check_add_cs_ibm_pak ibm-eventendpointmanagement $my_ibm_eventendpointmanagement_case amd64
  oc ibm-pak launch ibm-eventendpointmanagement --version $my_ibm_eventendpointmanagement_case --inventory eemOperatorSetup --action installCatalog -n $ns

  ## SB]20231020 For Flink and Event processing first you have to apply the catalog source to your cluster :
  ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter Applying catalog sources to your cluster
  ## event flink
  check_add_cs_ibm_pak ibm-eventautomation-flink $my_ibm_eventautomation_flink_case amd64
  oc ibm-pak launch ibm-eventautomation-flink --version $my_ibm_eventautomation_flink_case --inventory flinkKubernetesOperatorSetup --action installCatalog -n $ns

  ## event processing
  check_add_cs_ibm_pak ibm-eventprocessing $my_ibm_eventprocessing_case amd64
  oc ibm-pak launch ibm-eventprocessing --version $my_ibm_eventprocessing_case --inventory epOperatorSetup --action installCatalog -n  $ns
}

################################################
# Install Operators
## operator_name = "Literal name", https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=operators-installing-using-cli#operators-available
## current_channel = "Operator channel", : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=reference-operator-channel-versions-this-release
## catalog_source_name = catalog source created for this operator : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
# @param ns: namespace to install the operators
# resource is the result of the check_resource_availability command
Install_Operators () {
  local ns=$1
  local resource

  # export are important because they are used to replace the variable in the subscription.yaml (envsubst command)
  
  # Creating Navigator operator subscription
  if $my_ibm_navigator;then
    SECONDS=0
    export operator_name=ibm-integration-platform-navigator
    export current_channel=$my_ibm_navigator_operator_channel
    export catalog_source_name=ibm-integration-platform-navigator-catalog

    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating Asset Repository operator subscription
  if $my_ibm_asset_repository;then
    SECONDS=0
    export operator_name=ibm-integration-asset-repository
    export current_channel=$my_ibm_ar_operator_channel
    export catalog_source_name=ibm-integration-asset-repository-catalog

    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating ACE operator subscription
  if $my_ibm_appconnect;then
    SECONDS=0
    export operator_name=ibm-appconnect
    export current_channel=$my_ibm_ace_operator_channel
    export catalog_source_name=appconnect-operator-catalogsource

    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating APIC operator subscription
  if $my_ibm_apiconnect;then
    SECONDS=0
    export operator_name=ibm-apiconnect
    export current_channel=$my_ibm_apic_operator_channel
    export catalog_source_name=ibm-apiconnect-catalog

    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating MQ operator subscription
  if $my_ibm_mq;then
    SECONDS=0
    export operator_name=ibm-mq
    export current_channel=$my_ibm_mq_operator_channel
    export catalog_source_name=ibmmq-operator-catalogsource

    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating EventStreams operator subscription
  if $my_ibm_eventstreams;then
    SECONDS=0
    export operator_name=ibm-eventstreams
    export current_channel=$my_ibm_es_channel
    export catalog_source_name=ibm-eventstreams

    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating DP Gateway operator subscription
  ## SB]202302001 attention au dp la souscription porte un nom particulier voir la variable dp ci-dessous.
  if $my_ibm_datapower;then
    SECONDS=0
    export operator_name=datapower-operator
    export current_channel=$my_ibm_dpgw_operator_channel
    export catalog_source_name=ibm-datapower-operator-catalog
    dp=${operator_name}-${current_channel}-${catalog_source_name}-openshift-marketplace

    check_create_oc_yaml "subscription" $dp "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating Aspera HSTS operator subscription
  if $my_ibm_aspera_hsts;then
    SECONDS=0
    export operator_name=aspera-hsts-operator
    export current_channel=$my_ibm_hsts_operator_channel
    export catalog_source_name=aspera-operators
  
    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  ## SB]20231020 For Flink and Event processing install the operator with the following command :
  ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter : Install the operator by using the CLI (oc ibm-pak)
  ## event flink
  ## Creating Eventautomation Flink operator subscription
  if $my_ibm_eventautomation_flink;then
    SECONDS=0
    operator_name=ibm-eventautomation-flink

    oc ibm-pak launch ibm-eventautomation-flink --version $my_ibm_eventautomation_flink_case --inventory flinkKubernetesOperatorSetup --action installOperator -n $ns 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

  ## event processing
  ## Creating Event processing operator subscription
  if $my_ibm_eventprocessing;then
    SECONDS=0
    operator_name=ibm-eventprocessing

    oc ibm-pak launch ibm-eventprocessing --version $my_ibm_eventprocessing_case --inventory epOperatorSetup --action installOperator -n $ns
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi 

  #SB]20230130 Ajout du repository Nexus
  # Creating Nexus operator subscription
  if $my_install_nexus;then
    SECONDS=0
    export operator_name=nxrm-operator-certified
    export current_channel=$my_sonatype_nexus_operator_channel
    export catalog_source=certified-operators
    
    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of Nexus operator took $SECONDS seconds to execute." 1>&2
  fi

  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $my_instana_agent_operator;then
    SECONDS=0
    export operator_name=instana-agent-operator
    export current_channel=$my_ibm_instana_agent_operator_channel
    export catalog_source_name=certified-operators

    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    CreateNameSpace $my_instana_agent_project
    oc adm policy add-scc-to-user privileged -z instana-agent -n $my_instana_agent_project

    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of Instana agent operator took $SECONDS seconds to execute." 1>&2
  fi

  # Creating Event Endpoint Management operator subscription
  if $my_ibm_eventendpointmanagement;then
    SECONDS=0
    export operator_name=ibm-eventendpointmanagement
    export current_channel=$my_ibm_eventendpointmanagement_operator_channel
    export catalog_source_name=ibm-eventendpointmanagement-catalog
  
    check_create_oc_yaml "subscription" "${operator_name}" "${operatorsdir}subscription.yaml" $ns

    #SB]20231013 the function check_resource_availability will "return" the resource 
    resource=$(check_resource_availability "clusterserviceversion" "${operator_name}" $ns)
    wait_for_oc_state clusterserviceversion $resource Succeeded '.status.phase' $ns
    mylog info "Creation of $operator_name operator took $SECONDS seconds to execute." 1>&2
  fi

}

################################################
# create capabilities
# @param ns namespace where capabilities are created
# function
Install_Operands () {
  local ns=$1

  # Creating Navigator instance
  if $my_ibm_navigator;then
    check_create_oc_yaml PlatformNavigator $my_cp_navigator_instance_name "${operandsdir}Navigator-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state PlatformNavigator "$my_cp_navigator_instance_name" Ready '.status.conditions[0].type' $ns
    mylog info "Creation of Navigator instance took $SECONDS seconds to execute." 1>&2
  fi

  # Creating Integration Assembly instance
  if $my_ibm_intassembly;then
    check_create_oc_yaml IntegrationAssembly $my_cp_intassembly_instance_name "${operandsdir}IntegrationAssembly-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state IntegrationAssembly "$my_cp_intassembly_instance_name" Ready '.status.conditions[0].type' $ns
    mylog info "Creation of Integration Assembly instance took $SECONDS seconds to execute." 1>&2
  fi
  
  # Creating ACE Dashboard instance
  if $my_ibm_appconnect;then
    check_create_oc_yaml Dashboard $my_cp_ace_dashboard_instance_name "${operandsdir}ACE-Dashboard-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state Dashboard "$my_cp_ace_dashboard_instance_name" Ready '.status.conditions[0].type' $ns
    mylog info "Creation of ACE Dashboard instance took $SECONDS seconds to execute." 1>&2    
  fi
  
  # Creating ACE Designer instance
  if $my_ibm_appconnect;then
    check_create_oc_yaml DesignerAuthoring $my_cp_ace_designer_instance_name "${operandsdir}ACE-Designer-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state DesignerAuthoring "$my_cp_ace_designer_instance_name" Ready '.status.conditions[0].type' $ns
    mylog info "Creation of ACE Designer instance took $SECONDS seconds to execute." 1>&2    
  fi

  # Creating Aspera HSTS instance
  if $my_ibm_aspera_hsts;then
    oc apply -f "${operandsdir}AsperaCM-cp4i-hsts-prometheus-lock.yaml"
    oc apply -f "${operandsdir}AsperaCM-cp4i-hsts-engine-lock.yaml"

    check_create_oc_yaml IbmAsperaHsts $my_cp_hsts_instance_name "${operandsdir}AsperaHSTS-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state IbmAsperaHsts "$my_cp_hsts_instance_name" Ready '.status.conditions[0].type' $ns
    mylog info "Creation of Aspera HSTS instance took $SECONDS seconds to execute." 1>&2    
  fi

  # Creating APIC instance
  if $my_ibm_apiconnect;then
    check_create_oc_yaml APIConnectCluster $my_cp_apic_instance_name "${operandsdir}APIC-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state APIConnectCluster "$my_cp_apic_instance_name" Ready '.status.phase' $ns
    mylog info "Creation of APIC instance took $SECONDS seconds to execute." 1>&2    
  fi

  # Creating Asset Repository instance
  if $my_ibm_asset_repository;then
    check_create_oc_yaml AssetRepository $my_cp_ar_instance_name ${operandsdir}AR-Capability.yaml $ns
    SECONDS=0
    wait_for_oc_state AssetRepository "$my_cp_ar_instance_name" Ready '.status.phase' $ns
    mylog info "Creation of Asset Repository instance took $SECONDS seconds to execute." 1>&2    
  fi

  # Creating Event Streams instance
  if $my_ibm_eventstreams;then       
    check_create_oc_yaml EventStreams $my_cp_es_instance_name ${operandsdir}ES-Capability.yaml $ns
    SECONDS=0
    wait_for_oc_state EventStreams "$my_cp_es_instance_name" Ready '.status.phase' $ns
    mylog info "Creation of Event Streams instance took $SECONDS seconds to execute." 1>&2    
  fi

  # Creating EventEndpointManager instance (Event Processing)
  if $my_ibm_eventendpointmanagement;then
    check_create_oc_yaml EventEndpointManagement $my_ev_eem_instance_name "${operandsdir}EventEndpointManagement-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state EventEndpointManagement "$my_ev_eem_instance_name" Ready '.status.conditions[0].type' $ns
    mylog info "Creation of EventEndpointManagement instance took $SECONDS seconds to execute." 1>&2
  fi

  export my_eem_manager_gateway_route=`oc get eem $my_ev_eem_instance_name -o json | jq -r '.status.endpoints[1].uri'`
  # Creating EventGateway instance (Event Gateway)
  if $my_ibm_eventgateway;then
    check_create_oc_yaml EventGateway $my_ev_gw_instance_name "${operandsdir}EventGateway-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state EventGateway "$my_ev_gw_instance_name" Ready '.status.conditions[0].type' $ns
    mylog info "Creation of EventGateway instance took $SECONDS seconds to execute." 1>&2
  fi


  ## SB]20231023 Creation of Event automation Flink PVC and instance
  if $my_ibm_eventautomation_flink;then
    ## create PVC
    check_create_oc_yaml PersistentVolumeClaim ibm-flink-pvc "${operandsdir}Flink-PVC.yaml" $ns
    SECONDS=0
    wait_for_oc_state PersistentVolumeClaim ibm-flink-pvc Bound '.status.phase' $ns
    mylog info "Creation of PersistentVolumeClaim instance took $SECONDS seconds to execute." 1>&2
  fi

  ## SB]20231023 to check the status of Flink instance : https://ibm.github.io/event-automation/ep/installing/post-installation/
  ## The status field displays the current state of the FlinkDeployment custom resource. 
  ## When the Flink instance is ready, the custom resource displays status.lifecycleState: STABLE and status.jobManagerDeploymentStatus: READY.
  ## STANLE and READY (uppercase!!!)
  ## oc get flinkdeployment <instance-name> -n <namespace> -o jsonpath='{.status.lifecycleState}'
  ## oc get flinkdeployment <instance-name> -n <namespace> -o jsonpath='{.status.jobManagerDeploymentStatus}'

  if $my_ibm_eventautomation_flink;then
    ## create Flink instance
    check_create_oc_yaml FlinkDeployment $my_ev_flink_instance_name "${operandsdir}Flink-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state FlinkDeployment "$my_ev_flink_instance_name" STABLE '.status.lifecycleState' $ns
    wait_for_oc_state FlinkDeployment "$my_ev_flink_instance_name" READY '.status.jobManagerDeploymentStatus' $ns
    mylog info "Creation of FlinkDeployment instance took $SECONDS seconds to execute." 1>&2
  fi

  ## SB]20231023 to check the status of Event processing : https://ibm.github.io/event-automation/ep/installing/post-installation/
  ## The Status column displays the current state of the EventProcessing custom resource. 
  ## When the Event Processing instance is ready, the phase displays Phase: Running.
  ## Creating EventProcessing instance (Event Processing)
  ## oc get eventprocessing <instance-name> -n <namespace> -o jsonpath='{.status.phase}'

  if $my_ibm_eventprocessing;then
    check_create_oc_yaml EventProcessing $my_ev_ep_instance_name "${operandsdir}EventProcessing-Capability.yaml" $ns
    SECONDS=0
    wait_for_oc_state EventProcessing "$my_ev_ep_instance_name" Running '.status.phase' $ns
    mylog info "Creation of EventProcessing instance took $SECONDS seconds to execute." 1>&2
  fi


  ## Creating Nexus Repository instance (An open source repository for build artifacts)
    if $my_install_nexus;then
    check_create_oc_yaml NexusRepo $my_nexus_instance_name ${operandsdir}Nexus-Capability.yaml $ns
    SECONDS=0
    wait_for_oc_state NexusRepo "$my_nexus_instance_name" Deployed '[.status.conditions[].type][1]' $ns
    # add route to access Nexus from outside cluster
    check_create_oc_yaml Route $my_nexus_route_name ${operandsdir}Nexus-Route.yaml $ns
    mylog info "Creation of Nexus instance took $SECONDS seconds to execute." 1>&2    
  fi

  # Creating Instana agent
  if $my_instana_agent_operator;then
    check_create_oc_yaml InstanaAgent $my_instana_agent_instance_name ${operandsdir}Instana-Agent-Capability-CloudIBM.yaml $my_instana_agent_project
    SECONDS=0
    wait_for_oc_state DaemonSet $my_instana_agent_instance_name $my_cluster_workers '.status.numberReady' $my_instana_agent_project
    mylog info "Creation of Instana agent instance took $SECONDS seconds to execute." 1>&2    
  fi
}

################################################
# start customization
# @param ns namespace where operands were instantiated
# function
Start_Customization () {
  local ns=$1
  local varb64
  
  # Creating Eventstream topic,
  # SB]20231019 
  # 2 options : 
  #   Option1 : using the es plugin : cloudctl es topic-create.
  #   You have to install the ES plugin for ibmcloud command : cloudct. 
  #   https://ibm.github.io/event-automation/es/installing/post-installation/#installing-the-event-streams-command-line-interface, part : IBM Cloud Pak CLI plugin (cloudctl es)
  #  
  #   Option2 : using a yaml configuration file
  # SB]20231019 
  #if $my_customisation_eventstreams;then
  #fi

  # SB]20231026 Creating : 
  # - operands properties file, 
  # - topics, ...
  if $my_customisation_eventstreams;then
    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    generate_files $es_tmpl_customdir $es_gen_customdir
  fi


  ## Creating EEM users and roles
  if $my_customisation_eventendpointmanagement;then
    # generate properties files
    cat  $eem_tmpl_user_credentials_customfile | envsubst >  $eem_gen_user_credentials_customfile
    cat  $eem_tmpl_user_roles_customfile | envsubst >  $eem_gen_user_roles_customfile

    # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
    # user credentials
    varb64=$(cat "$eem_gen_user_credentials_customfile" | base64 -w0)
    oc patch secret "${my_ev_eem_instance_name}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]" -n $ns

    # user roles
    varb64=$(cat "$eem_gen_user_roles_customfile" | base64 -w0)
    oc patch secret "${my_ev_eem_instance_name}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]" -n $ns
  fi

  ## Creating Event Processing users and roles
  if $my_customisation_eventprocessing;then
    # generate properties files
    cat  $ep_tmpl_user_credentials_customfile | envsubst >  $ep_gen_user_credentials_customfile
    cat  $ep_tmpl_user_roles_customfile | envsubst >  $ep_gen_user_roles_customfile

    # user credentials
    varb64=$(cat "$ep_gen_user_credentials_customfile" | base64 -w0)
    oc patch secret "${my_ev_ep_instance_name}-ibm-ep-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]" -n $ns

    # user roles
    varb64=$(cat "$ep_gen_user_roles_customfile" | base64 -w0)
    oc patch secret "${my_ev_ep_instance_name}-ibm-ep-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]" -n $ns
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
    curl --user "admin:bvn4KHQ*nep*zeb!qrp" \
      -F "maven2.generate-pom=true" \
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

######################################################################
# Create openshift cluster if it does not exist
# and wait for both availability of the cluster and the ingress address
# function 
CreateOpenshiftCluster_Wait4Availability ()  {
  # Create openshift cluster
  CreateOpenshiftCluster

  # Wait for Cluster availability
  wait_for_cluster_availability

  # Wait for ingress address availability
  Wait4IngressAddressAvailability
}

################################################
# Add OpenLdap app to openshift
# function 
AddOpenLdap () {
  oc project $my_oc_project
  if $my_install_openldap;then
      check_create_oc_openldap "deployment" "openldap" "ldap"
  fi
}

################################################
# Display information to access CP4I
# function 
DisplayAccessInfo () {
  if $my_ibm_navigator;then
    get_navigator_access
  fi
}

################################################
# Add Catalog sources using IBM Pak plugin
# SB]202300201 https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
# function 
AddIbmPakCS () {
  if $my_ibm_pak; then
    Add_Catalog_Sources_ibm_pak $operators_project
  fi
}

################################################################################################
# Start of the script main entry
################################################################################################
# @param my_properties_file: file path and name of the properties file
# @param my_oc_project: namespace where to create the operators and capabilities
# @param my_cluster_name: name of the cluster
# example of invocation: ./provision_cluster-v2.sh private/my-cp4i.properties sbtest cp4i-sb-cluster
# other example: ./provision_cluster-v2.sh ./cp4i.properties cp4i cp4iad22023
my_properties_file=$1
export my_oc_project=$2
my_cluster_name=$3

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
mainscriptdir=$(dirname "$0")/

if (($# < 3)); then
  mylog error "The number of arguments should be 3" 1>&2
elif (($# > 3)); then
  mylog error "The number of arguments should be 3" 1>&2
else 
  mylog info "The provided arguments are: $@" 1>&2
fi

# load helper functions
. "${mainscriptdir}"lib.sh

# Read all the properties
read_config_file "$my_properties_file"

# check the differents pre requisites
check_exec_prereqs

# Log to IBM Cloud
Login2IBMCloud

# Create Openshift cluster
CreateOpenshiftCluster_Wait4Availability

# Log to openshift cluster
Login2OpenshiftCluster

# Create project namespace.
CreateNameSpace $my_oc_project

# Add ibm entitlement key to namespace
# SB]20230209 Aspera hsts service cannot be created because a problem with the entitlement, it muste be added in the openshift-operators namespace.
AddIBMEntitlement $operators_project
AddIBMEntitlement $my_oc_project


#SB]20231021 when installing event processing and flink operator, we get the error :
#Error from server (NotFound): catalogsources.operators.coreos.com "ea-flink-operator-catalog" not found
#[ERROR] expected catalog source 'ea-flink-operator-catalog' expected to be installed namespace 'openshift-marketplace'
oc apply -f ./ibm_catalogsource.yaml

#SB]202300201 https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
# Instantiate catalog sources
mylog info "==== Adding catalog sources using ibm pak plugin." 1>&2
AddIbmPakCS

# Install operators
mylog info "==== Installation of operators." 1>&2
Install_Operators $operators_project

# Instantiate operands
mylog info "==== Installation of operands." 1>&2
Install_Operands $my_oc_project

# Add OpenLdap app to openshift
mylog info "==== Adding OpenLdap." 1>&2
AddOpenLdap

## Display information to access CP4I
mylog info "==== Displaying Access Info to CP4I." 1>&2
DisplayAccessInfo

# Start customization
mylog info "==== Customization." 1>&2
Start_Customization $my_oc_project

#work in progress
# exit
#SB]20230214 Ajout Configuration ACE
# export my_global_index="04"
# Configure_ACE_IS $my_oc_project
#Configure_ACE_IS cp4i cp4i-ace-is-02 ./tmpl/configuration/ACE/ACE-IS-02.yaml cp4i-ace-barauth-02 ./tmpl/configuration/ACE/ACE-barauth-02.yaml
