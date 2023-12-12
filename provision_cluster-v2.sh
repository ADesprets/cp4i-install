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
  mylog info "Checking ngress availability took $SECONDS seconds to execute." 1>&2
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
  if $my_ibm_navigator;then
    check_add_cs_ibm_pak ibm-integration-platform-navigator $my_ibm_navigator_case amd64
  fi

  # ibm-integration-asset-repository
  if $my_ibm_ar;then
    check_add_cs_ibm_pak ibm-integration-asset-repository $my_ibm_ar_case amd64
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
   # The question : suppose we have installed the datapower operator case first, does the apic operator case installation ovverides it ? 
   # ibm-adatapower
  if $my_ibm_dpgw;then
    check_add_cs_ibm_pak ibm-datapower-operator $my_ibm_dpgw_case amd64
  fi

  # ibm-apiconnect
  if $my_ibm_apic;then
    check_add_cs_ibm_pak ibm-apiconnect $my_ibm_apic_case amd64
  fi

  # ibm-appconnect
  if $my_ibm_ace;then
    check_add_cs_ibm_pak ibm-appconnect $my_ibm_ace_case amd64
  fi

  # ibm-mq
  if $my_ibm_mq;then
    check_add_cs_ibm_pak ibm-mq $my_ibm_mq_case amd64
  fi 

  # ibm-eventstreams
  if $my_ibm_es;then
    check_add_cs_ibm_pak ibm-eventstreams $my_ibm_es_case amd64
  fi 

  # ibm-aspera-hsts-operator
  if $my_ibm_hsts;then
    check_add_cs_ibm_pak ibm-aspera-hsts-operator $my_ibm_hsts_case amd64
  fi

  ## ibm-cp-common-services
  if $my_ibm_cs;then
    check_add_cs_ibm_pak ibm-cp-common-services $my_ibm_cs_case amd64
  fi 

  ## event endpoint management
  ## to get the name of the pak to use : oc ibm-pak list
  ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
  if $my_ibm_eem;then
    check_add_cs_ibm_pak ibm-eventendpointmanagement $my_ibm_eem_case amd64
    oc ibm-pak launch ibm-eventendpointmanagement --version $my_ibm_eem_case --inventory eemOperatorSetup --action installCatalog -n $ns
  fi 

  if $my_ibm_flink;then
    ## SB]20231020 For Flink and Event processing first you have to apply the catalog source to your cluster :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter Applying catalog sources to your cluster
    # event flink
    check_add_cs_ibm_pak ibm-eventautomation-flink $my_ibm_flink_case amd64
    oc ibm-pak launch ibm-eventautomation-flink --version $my_ibm_flink_case --inventory flinkKubernetesOperatorSetup --action installCatalog -n $ns
  fi 

  if $my_ibm_ep;then
    # event processing
    check_add_cs_ibm_pak ibm-eventprocessing $my_ibm_ep_case amd64
    oc ibm-pak launch ibm-eventprocessing --version $my_ibm_ep_case --inventory epOperatorSetup --action installCatalog -n  $ns
  fi
}

################################################
# Install Operators
## name = "Literal name", https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=operators-installing-using-cli#operators-available
## current_channel = "Operator channel", : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=reference-operator-channel-versions-this-release
## catalog_source_name = catalog source created for this operator : https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
# @param ns: namespace to install the operators
# resource is the result of the check_resource_availability command
# SB]20231129 Adding the IBM Cloud Pak Foundational Services operator
Install_Operators () {

  # Creating foundational services operator subscription
  if $my_ibm_cs;then
    create_operator_subscription "ibm-common-service-operator" $my_ibm_cs_chl "ibm-operator-catalog" $operators_project "Automatic"
  fi
  
  # Creating IBM license operator subscription
  # SB]20231130 https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=administering-deploying-license-service#deploy-cli
  if $my_ibm_lic_srv;then
    create_operator_subscription "ibm-licensing-operator" $my_ibm_lic_srv_chl "opencloud-operators" $my_oc_cs_project "Automatic"
  fi

  # Creating DP Gateway operator subscription
  ## SB]202302001 attention au dp la souscription porte un nom particulier voir la variable dp ci-dessous
  ## SB]20231204 je me débarrasse du dp=${operator_name}-${current_channel}-${catalog_source_name}-openshift-marketplace
  if $my_ibm_dpgw;then
    create_operator_subscription "datapower-operator" $my_ibm_dpgw_chl "ibm-datapower-operator-catalog" $operators_project "Automatic"
  fi
  
  # Creating Navigator operator subscription
  if $my_ibm_navigator;then
    create_operator_subscription "ibm-integration-platform-navigator" $my_ibm_navigator_chl "ibm-integration-platform-navigator-catalog" $operators_project "Automatic"
  fi

  # Creating ACE operator subscription
  if $my_ibm_ace;then
    create_operator_subscription "ibm-appconnect" $my_ibm_ace_chl "appconnect-operator-catalogsource" $operators_project "Automatic"
  fi

  # Creating APIC operator subscription
  if $my_ibm_apic;then
    create_operator_subscription "ibm-apiconnect" $my_ibm_apic_chl "ibm-apiconnect-catalog" $operators_project "Automatic"
  fi

  # Creating Asset Repository operator subscription
  if $my_ibm_ar;then
    create_operator_subscription "ibm-integration-asset-repository" $my_ibm_ar_chl "ibm-integration-asset-repository-catalog" $operators_project "Automatic"
  fi

  # Creating Event Endpoint Management operator subscription
  if $my_ibm_eem;then
    create_operator_subscription "ibm-eventendpointmanagement" $my_ibm_eem_chl "ibm-eventendpointmanagement-catalog" $operators_project "Automatic"
  fi

  ## SB]20231020 For Flink and Event processing install the operator with the following command :
  ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter : Install the operator by using the CLI (oc ibm-pak)
  ## event flink
  ## Creating Eventautomation Flink operator subscription

  if $my_ibm_flink;then
    create_ea_operators flinkKubernetesOperatorSetup ibm-eventautomation-flink $operators_project "{.status.phase}" "Succeeded" "clusterserviceversion" $my_ibm_flink_case
  fi

  ## event processing
  ## Creating Event processing operator subscription
  if $my_ibm_ep;then
    create_ea_operators epOperatorSetup ibm-eventprocessing $operators_project "{.status.phase}" "Succeeded" "clusterserviceversion" $my_ibm_ep_case
  fi 

  # Creating EventStreams operator subscription
  if $my_ibm_es;then
    create_operator_subscription "ibm-eventstreams" $my_ibm_es_chl "ibm-eventstreams" $operators_project "Automatic"
  fi

  # Creating MQ operator subscription
  if $my_ibm_mq;then
    create_operator_subscription "ibm-mq" $my_ibm_mq_chl "ibmmq-operator-catalogsource" $operators_project "Automatic"
  fi

  # Creating Aspera HSTS operator subscription
  if $my_ibm_hsts;then
    create_operator_subscription "aspera-hsts-operator" $my_ibm_hsts_chl "aspera-operators" $operators_project "Automatic"
  fi


  #SB]20230130 Ajout du repository Nexus
  # Creating Nexus operator subscription
  if $my_install_nexus;then
    create_operator_subscription  "nxrm-operator-certified" $my_sonatype_nexus_chl "certified-operators" $operators_project "Automatic"
  fi

  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $my_ibm_instana_agent;then
    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    CreateNameSpace $my_instana_agent_project
    oc adm policy add-scc-to-user privileged -z instana-agent -n $my_instana_agent_project
    create_operator_subscription "instana-agent-operator" $my_ibm_instana_agent_chl "certified-operators" $operators_project "Automatic"
  fi
}

################################################
# create capabilities
# @param ns namespace where capabilities are created
# function
Install_Operands () {

  # SB]20231201 Creating OperandRequest for foundational services
  # SB]20231211 Creating IBM License Server Reporter Instance
  #             https://www.ibm.com/docs/en/cloud-paks/foundational-services/3.23?topic=reporter-deploying-license-service#lrcmd
  if $my_ibm_cs;then
    create_operand_instance "${operandsdir}OperandRequest.yaml" ${my_oc_cs_project} "{.status.conditions[0].type}" $my_ibm_cs_instance_name "Ready" "OperandRequest"
    # create_operand_instance "${operandsdir}LIC-Reporter-Capability.yaml" ${my_oc_cs_project} "{.status.LicensingReporterPods[0].phase}" $my_ibm_cs_lic_reporter_instance_name "Running" "IBMLicenseServiceReporter"
    #oc patch OperandConfig common-service --namespace ${my_oc_cs_project} --type merge -p '{"spec": {"services[?(@.name==\"ibm-licensing-operator\")]": {"spec": {"IBMLicenseServiceReporter": {}}}}}'
    #oc patch OperandConfig common-service --namespace ${my_oc_cs_project} --type merge -p '{"spec": {"services": [{"name": "ibm-licensing-operator", "spec": {"IBMLicenseServiceReporter": {}}}]}}'
    #oc patch commonservice common-service --namespace ${my_oc_cs_project} --type merge -p '{"spec": {"license": {"accept": true}}}'

    #oc patch OperandConfig common-service --namespace ${my_oc_cs_project} --type merge -p '{"spec": {"services[?(@.name==\"ibm-licensing-operator\")]": {"spec": {"IBMLicenseServiceReporter": {}}}}}'

  fi

  # Creating Navigator instance
  if $my_ibm_navigator;then
    create_operand_instance "${operandsdir}Navigator-Capability.yaml" ${my_oc_project} "{.status.conditions[0].type}" $my_ibm_navigator_instance_name "Ready" "PlatformNavigator"
  fi

  # Creating Integration Assembly instance
  if $my_ibm_intassembly;then
    create_operand_instance "${operandsdir}IntegrationAssembly-Capability.yaml" ${my_oc_project} "{.status.conditions[0].type}" $my_ibm_intassembly_instance_name "Ready" "IntegrationAssembly"
  fi
  
  # Creating ACE Dashboard instance
  if $my_ibm_ace;then
    create_operand_instance "${operandsdir}ACE-Dashboard-Capability.yaml" ${my_oc_project} "{.status.conditions[0].type}" $my_ibm_ace_dashboard_instance_name "Ready" "Dashboard"
  fi
  
  # Creating ACE Designer instance
  if $my_ibm_ace;then
    create_operand_instance "${operandsdir}ACE-Designer-Capability.yaml" ${my_oc_project} "{.status.conditions[0].type}" $my_ibm_ace_designer_instance_name "Ready" "DesignerAuthoring"
  fi

  # Creating Aspera HSTS instance
  if $my_ibm_hsts;then
    oc apply -f "${operandsdir}AsperaCM-cp4i-hsts-prometheus-lock.yaml"
    oc apply -f "${operandsdir}AsperaCM-cp4i-hsts-engine-lock.yaml"
    create_operand_instance "${operandsdir}AsperaHSTS-Capability.yaml" ${my_oc_project} "{.status.conditions[0].type}" $my_ibm_hsts_instance_name "Ready" "IbmAsperaHsts"
  fi

  # Creating APIC instance
  if $my_ibm_apic;then
    create_operand_instance "${operandsdir}APIC-Capability.yaml" ${my_oc_project} "{.status.phase}" $my_ibm_apic_instance_name "Ready" "APIConnectCluster"
  fi

  # Creating Asset Repository instance
  if $my_ibm_ar;then
    create_operand_instance "${operandsdir}AR-Capability.yaml" ${my_oc_project} "{.status.phase}" $my_ibm_ar_instance_name "Ready" "AssetRepository"
  fi

  # Creating Event Streams instance
  if $my_ibm_es;then       
    create_operand_instance "${operandsdir}ES-Capability.yaml" ${my_oc_project} "{.status.phase}" $my_ibm_es_instance_name "Ready" "EventStreams"
  fi

  # Creating EventEndpointManager instance (Event Endpoint Manager)
  if $my_ibm_eem;then
    create_operand_instance "${operandsdir}EEM-Capability.yaml" ${my_oc_project} "{.status.conditions[0].type}" $my_ibm_eem_instance_name "Ready" "EventEndpointManagement"
    export my_eem_manager_gateway_route=$(oc get eem $my_ibm_eem_instance_name -n $my_oc_project -o jsonpath='{.status.endpoints[1].uri}')
  fi
  
  # Creating EventGateway instance (Event Gateway)
  if $my_ibm_egw;then
    create_operand_instance "${operandsdir}EG-Capability.yaml" ${my_oc_project} "{.status.conditions[0].type}" $my_ibm_eg_instance_name "Ready" "EventGateway"
  fi

  ## SB]20231023 Creation of Event automation Flink PVC and instance
  if $my_ibm_flink;then
    # Even if it's a pvc we use the same generic function
    create_operand_instance "${operandsdir}EA-Flink-PVC.yaml" ${my_oc_project} "{.status.phase}" "ibm-flink-pvc" "Bound" "PersistentVolumeClaim"

    ## SB]20231023 to check the status of created Flink instance : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The status field displays the current state of the FlinkDeployment custom resource. 
    ## When the Flink instance is ready, the custom resource displays status.lifecycleState: STABLE and status.jobManagerDeploymentStatus: READY.
    ## STANLE and READY (uppercase!!!)
    create_operand_instance "${operandsdir}EA-Flink-Capability.yaml" ${my_oc_project} "{.status.lifecycleState}-{.status.jobManagerDeploymentStatus}" $my_ibm_flink_instance_name "STABLE-READY" "FlinkDeployment"
  fi

  ## SB]20231023 to check the status of Event processing : https://ibm.github.io/event-automation/ep/installing/post-installation/
  ## The Status column displays the current state of the EventProcessing custom resource. 
  ## When the Event Processing instance is ready, the phase displays Phase: Running.
  ## Creating EventProcessing instance (Event Processing)
  ## oc get eventprocessing <instance-name> -n <namespace> -o jsonpath='{.status.phase}'

  if $my_ibm_ep;then
    create_operand_instance "${operandsdir}EP-Capability.yaml" ${my_oc_project} "{.status.phase}" $my_ibm_ep_instance_name "Running" "EventProcessing"
  fi

  ## Creating Nexus Repository instance (An open source repository for build artifacts)
    if $my_install_nexus;then
    create_operand_instance "${operandsdir}Nexus-Capability.yaml" ${my_oc_project} "[.status.conditions[].type][1]" $my_nexus_instance_name "Deployed" "NexusRepo"

    # add route to access Nexus from outside cluster
    check_create_oc_yaml Route $my_nexus_route_name ${operandsdir}Nexus-Route.yaml $my_oc_project
    mylog info "Creation of Route (Nexus) took $SECONDS seconds to execute." 1>&2
  fi

  # Creating Instana agent
  if $my_ibm_instana_agent;then
    create_operand_instance "${operandsdir}Instana-Agent-CloudIBM-Capability.yaml" ${my_instana_agent_project} "{.status.numberReady}" $my_ibm_instana_agent_instance_name "$my_cluster_workers" "InstanaAgent"
  fi
}

################################################
# start customization
# @param ns namespace where operands were instantiated
# function
Start_Customization () {
  local ns=$1
  local varb64
  
  if $my_ibm_ace_custom;then
    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    generate_files $ace_tmpl_customdir $ace_gen_customdir
  fi

  if $my_ibm_apic_custom;then
    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    generate_files $apic_tmpl_customdir $apic_gen_customdir
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
  if $my_ibm_es_custom;then
    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    generate_files $es_tmpl_customdir $es_gen_customdir
  fi

  ## Creating EEM users and roles
  if $my_ibm_eem_custom;then
    # generate properties files
    cat  $eem_tmpl_user_credentials_customfile | envsubst >  $eem_gen_user_credentials_customfile
    cat  $eem_tmpl_user_roles_customfile | envsubst >  $eem_gen_user_roles_customfile

    # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
    # user credentials
    varb64=$(cat "$eem_gen_user_credentials_customfile" | base64 -w0)
    oc patch secret "${my_ibm_eem_instance_name}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]" -n $ns

    # user roles
    varb64=$(cat "$eem_gen_user_roles_customfile" | base64 -w0)
    oc patch secret "${my_ibm_eem_instance_name}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]" -n $ns
  fi

  ## Creating Event Processing users and roles
  if $my_ibm_ep_custom;then
    # generate properties files
    cat  $ep_tmpl_user_credentials_customfile | envsubst >  $ep_gen_user_credentials_customfile
    cat  $ep_tmpl_user_roles_customfile | envsubst >  $ep_gen_user_roles_customfile

    # user credentials
    varb64=$(cat "$ep_gen_user_credentials_customfile" | base64 -w0)
    oc patch secret "${my_ibm_ep_instance_name}-ibm-ep-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]" -n $ns

    # user roles
    varb64=$(cat "$ep_gen_user_roles_customfile" | base64 -w0)
    oc patch secret "${my_ibm_ep_instance_name}-ibm-ep-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]" -n $ns
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
  wait_for_state IntegrationServer "$ace_is" Ready '{.status.phase}' $ns
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
  #oc project $my_oc_project
  if $my_install_ldap;then
      check_create_oc_openldap "deployment" "openldap" "ldap"
  fi
}

################################################
# Display information to access CP4I
# function 
DisplayAccessInfo () {
  # Always display the platform console endpoint
  cp_console_url=$(oc -n ${my_oc_fs_project} get Route -o=jsonpath='{.items[?(@.metadata.name=="cp-console")].spec.host}')
  mylog info "Cloup Pak Console endpoint: ${cp_console_url}"
  cp_console_admin_pwd=$(oc -n ${my_oc_fs_project} get secret platform-auth-idp-credentials -o jsonpath='{.data.admin_password}' | base64 -d)
  mylog info "Cloup Pak Console admin password: ${cp_console_admin_pwd}"

  if $my_ibm_navigator;then
    get_navigator_access
  fi

  if $my_ibm_ace;then
    ace_ui_db_url=$(oc get Dashboard -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="Dashboard")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "ACE Dahsboard UI endpoint: " $ace_ui_db_url
    ace_ui_dg_url=$(oc get DesignerAuthoring -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="DesignerAuthoring")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "ACE Designer UI endpoint: " $ace_ui_dg_url
  fi	

  if $my_ibm_apic;then
    gtw_url=$(oc get GatewayCluster -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].status.endpoints[?(@.name=="gateway")].uri}')
	  mylog info "APIC Gateway endpoint: ${gtw_url}"
    apic_gtw_admin_pwd_secret_name=$(oc get GatewayCluster -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].spec.adminUser.secretName}')
    cm_admin_pwd=$(oc get secret ${apic_gtw_admin_pwd_secret_name} -n $my_oc_project -o jsonpath={.data.password} | base64 -d)
	  mylog info "APIC Gateway admin password: ${cm_admin_pwd}"
    cm_url=$(oc get APIConnectCluster -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="admin")].uri}')
	  mylog info "APIC Cloud Manager endpoint: ${cm_url}"
    cm_admin_pwd_secret_name=$(oc get ManagementCluster -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="ManagementCluster")].spec.adminUser.secretName}')
    cm_admin_pwd=$(oc get secret ${cm_admin_pwd_secret_name} -n $my_oc_project -o jsonpath='{.data.password}' | base64 -d)
    mylog info "APIC Cloud Manager admin password: ${cm_admin_pwd}"
    mgr_url=$(oc get APIConnectCluster -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "APIC API Manager endpoint: ${mgr_url}" 
    ptl_url=$(oc get PortalCluster -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="PortalCluster")].status.endpoints[?(@.name=="portalWeb")].uri}')
    mylog info "APIC Web Portal root endpoint: ${ptl_url}"
  fi

  if $my_ibm_eem;then
    eem_ui_url=$(oc get EventEndpointManagement -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "Event Endpoint Management UI endpoint: ${eem_ui_url}"
    eem_gtw_url=$(oc get EventEndpointManagement -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="gateway")].uri}')
	  mylog info "Event Endpoint Management Gateway endpoint: ${eem_gtw_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi

  if $my_ibm_es;then
    es_ui_url=$(oc get EventStreams -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="ui")].uri}')
	  mylog info "Event Streams Management UI endpoint: ${es_ui_url}"
    es_admin_url=$(oc get EventStreams -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="admin")].uri}')
	  mylog info "Event Streams Management admin endpoint: ${es_admin_url}"
    es_apicurioregistry_url=$(oc get EventStreams -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="apicurioregistry")].uri}')
	  mylog info "Event Streams Management apicurio registry endpoint: ${es_apicurioregistry_url}" 
    es_restproducer_url=$(oc get EventStreams -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="restproducer")].uri}')
	  mylog info "Event Streams Management REST Producer endpoint: ${es_restproducer_url}"
    es_bootstrap_urls=$(oc get EventStreams -n $my_oc_project -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.kafkaListeners[*].bootstrapServers}')
	  mylog info "Event Streams Bootstraps servers endpoints: ${es_bootstrap_urls}" 
  fi

  if $my_install_ldap;then
   mylog info "LDAP info"
  fi
  
  if $my_ibm_ar;then
   mylog info "LDAP info"
  fi

  if $my_ibm_dpgw;then
   mylog info "LDAP info"
  fi

  if $my_ibm_mq;then
   mylog info "LDAP info"
  fi

  if $my_ibm_lic_srv;then
    licensing_service_url=$(oc -n ${my_oc_fs_project} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-licensing-service-instance")].spec.host}')
    mylog info "Licensing service endpoint: ${licensing_service_url}"
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

################################################
# SB]20231021 when installing event processing and flink operator, we get the error :
# Error from server (NotFound): catalogsources.operators.coreos.com "ea-flink-operator-catalog" not found
# [ERROR] expected catalog source 'ea-flink-operator-catalog' expected to be installed namespace 'openshift-marketplace'
# SB]20231122 to check if this catalog source (ibm-operator-catalog) exists in the ns (openshift-marketplace)
# use the following solution (https://www.unix.com/shell-programming-and-scripting/193809-awk-output-multiple-variables.html)
# SB]20231129 also for installing the IBM COmmon Services Operator 
#  https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm
CreateCatalogsource () {
  local ns=$1
  local file=$2
  local type=$3
  local name=$4
  local path=$5
  local state=$6
  
  set -- $(oc get $type -A| grep $name| awk -v ORS=" " '{print $1,$2}')
  if [ "$1" = "$ns" ] && [ "$2" = "$name" ]; then
    mylog "info" "$name already exists in ns $ns"
  else  
    check_file_exist $file
    oc apply -f $file
    wait_for_state "$type $name $path is $state" "$state" "oc get ${type} ${name} -n ${ns} -o jsonpath='$path'"
  fi
}

################################################
# SB]20231130 patcher les foundational services en acceptant la license
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm
# 3.Setting the hardware profile and accepting the license
# License: Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
PatchFS () {
  local accept
  accept=$(oc get commonservice common-service -n ${my_oc_cs_project} -o jsonpath='{.spec.license.accept}')

  if [ $accept ]; then
    mylog info "license already accepted." 1>&2
  else
    oc patch commonservice common-service --namespace ${my_oc_cs_project} --type merge -p '{"spec": {"license": {"accept": true}}}'
  fi
}

################################################
# SB]20231201 configurer les foundational services
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=services-using-commonservice-custom-resource
ConfigureFS () {
  check_create_oc_yaml CommonService $my_ibm_cs_instance_name ${resourcesdir}foundational-services-cr.yaml ${my_oc_cs_project}
}

################################################################################################
# Start of the script main entry
################################################################################################
# @param my_properties_file: file path and name of the properties file
# @param my_oc_project: namespace where to create the operators and capabilities
# @param my_cluster_name: name of the cluster
# example of invocation: ./provision_cluster-v2.sh private/my-cp4i.properties sbtest cp4i-sb-cluster
# other example: ./provision_cluster-v2.sh ./cp4i.properties ./versions/cp4i-2023.2.properties cp4i sb20231129
# other example: ./provision_cluster-v2.sh ./cp4i.properties ./versions/cp4i-2023.2.properties cp4i cp4iad22023
my_properties_file=$1
my_versions_file=$2
export my_oc_project=$3
my_cluster_name=$4

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
mainscriptdir=$(dirname "$0")/

if [ $# -ne 4 ]; then
  echo "the number of arguments should be 4 : properties_file versions_file namespace cluster "
  exit
else echo "The provided arguments are: $@"
fi

# load helper functions
. "${mainscriptdir}"lib.sh

# Read all the properties
read_config_file "$my_properties_file"

# Read versions properties
read_config_file "$my_versions_file"

# : <<'END_COMMENT'
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
AddIBMEntitlement $my_oc_project
AddIBMEntitlement $operators_project

# Create catalog source ibm-operator-catalog
CreateCatalogsource "openshift-marketplace" "${resourcesdir}ibm_catalogsource.yaml" "catalogsource" "ibm-operator-catalog" "{.status.connectionState.lastObservedState}" "READY"

# SB]20231129 create config map for foundational services
check_create_oc_yaml "configmap" "common-service-maps" "${resourcesdir}common-service-cm.yaml" kube-public

# SB]20231130 create resources needed by the IBM Cloud Pak foundational services
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.2?topic=SSGT7J_23.2/installer/3.x.x/install_cs_cli.htm (part : a. Create a YAML file named def.yaml with the resources definitions that you need.)
check_create_oc_yaml "OperatorGroup" "operatorgroup" "${resourcesdir}operator-group.yaml" $my_oc_project

#SB]202300201 https://www.ibm.com/docs/en/cloud-paks/cp-integration/2022.4?topic=images-adding-catalog-sources-cluster
# Instantiate catalog sources
mylog info "==== Adding catalog sources using ibm pak plugin." 1>&2
AddIbmPakCS

# Install operators
mylog info "==== Installation of operators." 1>&2
Install_Operators

# SB]20231130 patcher les foundational services en acceptant la license
PatchFS

# SB]20231201 Configuring foundational services by using the CommonService custom resource.
ConfigureFS

# Add OpenLdap app to openshift
mylog info "==== Adding OpenLdap." 1>&2
AddOpenLdap

# Instantiate operands
mylog info "==== Installation of operands." 1>&2
Install_Operands

# END_COMMENT

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
