#!/bin/bash
# Main program to install CP4I end to end with customisation
# Laurent 2021
# Updated July 2023 Saad / Arnauld
################################################
# @param $1 cp4i properties file path (ex : ./cp4.properties)
# @param $2 cp4i versions file path (ex : ./versions/cp4-16.1.0.properties)
# @param $3 namespace
# @param $4 cluster_name
################################################

################################################
# Log in IBM Cloud
function login_2_ibm_cloud() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :login_2_ibm_cloud"

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
        decho 4 "F:OUT:login_2_ibm_cloud"
        SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
        exit 1
      else
        mylog ok
        mylog info "Connecting to IBM Cloud took: $SECONDS seconds." 1>&2
      fi
    fi
  fi

  decho 4 "F:OUT:login_2_ibm_cloud"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

######################################################################
# Create openshift cluster if it does not exist
# and wait for both availability of the cluster and the ingress address
function create_openshift_cluster_wait_4_availability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_openshift_cluster_wait_4_availability"

  if ! ${TECHZONE}; then
    # Create openshift cluster
    create_openshift_cluster

    # Wait for Cluster availability
    wait_for_cluster_availability

    # Wait for ingress address availability
    wait_4_ingress_address_availability
  fi

  decho 3 "F:OUT:create_openshift_cluster_wait_4_availability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Login to openshift cluster
# note that this login requires that you login to the cluster once (using sso or web): not sure why
# requires var my_cluster_url
function login_2_openshift_cluster() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 4 "F:IN :login_2_openshift_cluster"

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

  decho 4 "F:OUT:login_2_openshift_cluster"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# add ibm entitlement key to namespace
# @param ns namespace where secret is created
function add_ibm_entitlement() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :add_ibm_entitlement"

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
      decho 3 "F:OUT:add_ibm_entitlement"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
    mylog info "Adding ibm-entitlement-key to $lf_in_ns"
    if ! oc -n $lf_in_ns create secret docker-registry ibm-entitlement-key --docker-username=cp --docker-password=$MY_ENTITLEMENT_KEY --docker-server=cp.icr.io; then
      decho 3 "F:OUT:add_ibm_entitlement"
      SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
      exit 1
    fi
  fi

  decho 3 "F:OUT:add_ibm_entitlement"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Keycloak
function install_keycloak() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_keycloak"

  mylog info "==== Installing Redhat Openshift Keycloak." 1>&2
  create_namespace ${MY_KEYCLOAK_NAMESPACE} "${MY_KEYCLOAK_NAMESPACE} project" "For Keycloak"

  # Operator group for Keycloak in single namespace
  local lf_type="OperatorGroup"
  local lf_cr_name="${MY_KEYCLOAK_OPERATORGROUP}"
  local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
  local lf_namespace=$MY_KEYCLOAK_NAMESPACE
  mylog check "Checking $lf_type $lf_cr_name in $lf_namespace" 1>&2
  if oc get "$lf_type" -n "$lf_namespace" "$lf_cr_name" >/dev/null 2>&1; then
    mylog ok
  else
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  fi

  # Create a subscription for Keycloak Operator
  local lf_operator_name="$MY_KEYCLOAK_CASE"
  local lf_operator_namespace=$MY_KEYCLOAK_NAMESPACE
  local lf_operator_chl=$MY_KEYCLOAK_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_KEYCLOAK_CASE
  mylog check "Checking subscription $lf_operator_name in $lf_namespace" 1>&2
  if oc get subscription -n "$lf_namespace" "$lf_operator_name" >/dev/null 2>&1; then
    mylog ok
  else
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

#  if $; then
#    mylog info "HOLD PLACE"
#  else
#    # Creating  instance
#    local lf_file="${MY_OPERANDSDIR}APIC-Capability.yaml"
#    local lf_ns="${MY_OC_PROJECT}"
#    local lf_path="{.status.phase}"
#    local lf_resource="$MY_APIC_INSTANCE_NAME"
#    local lf_state="Ready"
#    local lf_type="APIConnectCluster"
#    local lf_wait_for_state=true
#    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
#  fi
  
  decho 3 "F:OUT:install_keycloak"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install SFTP server, it is usefull for example for backups
function install_sftp() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_sftp"

  mylog info "==== Installing an SFTP server." 1>&2

  create_namespace ${MY_SFTP_SERVER_NAMESPACE} "${MY_SFTP_SERVER_NAMESPACE} project" "For SFTP server"

  # Create secret with users
  mylog check "Checking Secret for credential ${MY_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" 1>&2
  if oc get secret -n ${MY_SFTP_SERVER_NAMESPACE} "${MY_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" >/dev/null 2>&1; then
    mylog ok
  else
    generate_password 32
    adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ users.conf
    unset $USER_PASSWORD_GEN
    oc -n $MY_SFTP_SERVER_NAMESPACE create secret generic "${MY_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/users.conf
  fi

  # Create configmap with SSH keys
  mylog check "Checking ConfigMap for ssh keys ${MY_SFTP_SERVER_NAMESPACE}-ssh-conf-cm" 1>&2
  if oc get configmap -n ${MY_SFTP_SERVER_NAMESPACE} "${MY_SFTP_SERVER_NAMESPACE}-ssh-conf-cm" >/dev/null 2>&1; then
    mylog ok
  else
    ssh-keygen -t ed25519 -f ${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key < /dev/null
    ssh-keygen -t rsa -b 4096 -f ${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key < /dev/null
    adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ sshd_config
    oc -n $MY_SFTP_SERVER_NAMESPACE create configmap ${MY_SFTP_SERVER_NAMESPACE}-ssh-conf-cm \
      --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key \
      --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key.pub \
      --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key \
      --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key.pub \
      --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/sshd_config
  fi

  # Create PVC
  export VAR_PVC_NAME="${MY_SFTP_SERVER_NAMESPACE}-sftp-pvc"
  export VAR_PVC_NAMESPACE=$MY_SFTP_SERVER_NAMESPACE
  export VAR_PVC_STORAGE_CLASS=$MY_FILE_STORAGE_CLASS
  mylog check "Checking Persistent Volume Claim $VAR_PVC_NAME" 1>&2
  if oc -n $MY_SFTP_SERVER_NAMESPACE get pvc "$VAR_PVC_NAME" >/dev/null 2>&1; then
    mylog ok
  else
 	  adapt_file ${MY_RESOURCESDIR} ${MY_SFTP_GEN_CUSTOMDIR}config/ pvc.yaml
	  oc -n ${MY_SFTP_SERVER_NAMESPACE} create -f ${MY_SFTP_GEN_CUSTOMDIR}config/pvc.yaml
	  wait_for_state "$VAR_PVC_NAME status.phase is Bound" "Bound" "oc -n ${MY_SFTP_SERVER_NAMESPACE} get pvc $VAR_PVC_NAME -o jsonpath='{.status.phase}'"
  fi

  # Check security context constraint
  mylog check "Security Context Constraint anyuid" 1>&2
  if oc get SecurityContextConstraints anyuid >/dev/null 2>&1; then
    mylog ok
  else
    oc adm policy add-scc-to-user anyuid -z default
    wait 10
    oc patch scc anyuid --type=merge --patch '{"users": ["system:serviceaccount:sftp:default\n"]}'
    oc patch scc anyuid --type=merge --patch '{"allowedCapabilities":["SYS_CHROOT\n"]}'
  fi

  # Create deployment including the resources generated
  mylog check "Checking Deployment ${MY_SFTP_SERVER_NAMESPACE}-sftp-server" 1>&2
  if oc -n ${MY_SFTP_SERVER_NAMESPACE} get deployment "${MY_SFTP_SERVER_NAMESPACE}-sftp-server" >/dev/null 2>&1; then
    mylog ok
  else
    adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ sftp_dep.yaml
    # oc -n  ${MY_SFTP_SERVER_NAMESPACE} new-app atmoz/sftp:alpine
    local lf_type="Deployment"
    local lf_cr_name="${MY_SFTP_SERVER_NAMESPACE}-sftp-server"
    local lf_yaml_file="${MY_SFTP_GEN_CUSTOMDIR}config/sftp_dep.yaml"
    local lf_namespace="${MY_SFTP_SERVER_NAMESPACE}"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}" 
  fi

  # Create the service to expose the SFTP server
  mylog check "Checking Service $MY_SFTP_SERVER_NAMESPACE-sftp-service" 1>&2
  if oc -n ${MY_SFTP_SERVER_NAMESPACE} get service "$MY_SFTP_SERVER_NAMESPACE-sftp-service" >/dev/null 2>&1; then
    mylog ok
  else
    adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ sftp_svc.yaml
    # oc -n  ${MY_SFTP_SERVER_NAMESPACE} new-app atmoz/sftp:alpine
    local lf_type="Service"
    local lf_cr_name="$MY_SFTP_SERVER_NAMESPACE-sftp-service"
    local lf_yaml_file="${MY_SFTP_GEN_CUSTOMDIR}config/sftp_svc.yaml"
    local lf_namespace="${MY_SFTP_SERVER_NAMESPACE}"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}" 
  fi

  # Create the route to expose the SFTP server
  mylog check "Checking Route $MY_SFTP_SERVER_NAMESPACE-sftp-route" 1>&2
  if oc -n ${MY_SFTP_SERVER_NAMESPACE} get route "$MY_SFTP_SERVER_NAMESPACE-sftp-route" >/dev/null 2>&1; then
    mylog ok
  else
    adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ sftp_route.yaml
    local lf_type="Route"
    local lf_cr_name="$MY_SFTP_SERVER_NAMESPACE-sftp-route"
    local lf_yaml_file="${MY_SFTP_GEN_CUSTOMDIR}config/sftp_route.yaml"
    local lf_namespace="${MY_SFTP_SERVER_NAMESPACE}"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}" 
  fi

  decho 3 "F:OUT :install_sftp"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install GitOps
function install_gitops() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_gitops"

  # https://docs.openshift.com/gitops/1.12/installing_gitops/installing-openshift-gitops.html

  mylog info "==== Installing Redhat Openshift GitOps." 1>&2

  create_namespace ${MY_GITOPS_NAMESPACE} "${MY_GITOPS_NAMESPACE} project" "For GitOps"

  local lf_operator_name="$MY_GITOPS_OPERATORGROUP"
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_operator_chl=$MY_GITOPS_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_GITOPS_CASE
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho 3 "F:OUT:install_gitops"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Install CP4I Cluster Logging : Loki log store
# use Openshift Logging
# https://docs.openshift.com/container-platform/4.16/observability/logging/cluster-logging-deploying.html#logging-loki-cli-install_cluster-logging-deploying
function install_logging_loki() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_logging_loki"

  # Openshift Logging
  if $MY_LOGGING_LOKI; then
    mylog info "==== Installing Cluster Logging : Loki log store." 1>&2

    # Create a namespace object for Loki Operator
    oc apply -f ${MY_RESOURCESDIR}loki-namespace.yaml

    # Operator group for Loki in all namespaces
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LOKI_OPERATORGROUP}"
    local lf_yaml_file="${MY_RESOURCESDIR}operator-group-all.yaml"
    local lf_namespace="openshift-operators-redhat"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"  

    # Create a subscription object for Loki Operator    
    local lf_operator_name=$MY_LOKI_OPERATOR
    local lf_operator_namespace="openshift-operators-redhat"
    local lf_operator_chl=$MY_LOKI_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="redhat-operators"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_LOKI_OPERATOR
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Create a namespace object for Red Hat Openshift Logging Operator
    oc apply -f ${MY_RESOURCESDIR}rhel-logging-namespace.yaml

    # Create an OperatorGroup object for Red Hat Openhsift Logging Operator
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LOGGING_OPERATORGROUP}"
    local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    export MY_OPERATORGROUP="${MY_LOGGING_OPERATORGROUP}"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    
    # Create a subscription object for Red Hat Openshift Logging Operator
    local lf_operator_name=$MY_LOGGING_OPERATORGROUP
    local lf_operator_namespace="${MY_LOGGING_NAMESPACE}"
    local lf_operator_chl=$MY_LOKI_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="redhat-operators"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_LOGGING_OPERATORGROUP
    #export MY_STARTING_CSV="${MY_LOKI_STARTINGCSV}"
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # create an ObjectBucketClaim in openshift-logging namespace
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/installing-log-storage.html#logging-loki-storage-odf_installing-log-storage
    local lf_operator_namespace=$MY_LOGGING_NAMESPACE
    local lf_type="ObjectBucketClaim"
    local lf_cr_name=$MY_LOKI_BUCKET_INSTANCE_NAME
    local lf_yaml_file="${MY_RESOURCESDIR}objectbucketclaim.yaml"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

    # get the needed parameters to create the object storage secret
    export MY_LOKI_ACCESS_KEY_ID=$(oc -n openshift-storage get secret  rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.AccessKey}'| base64 --decode)
    export MY_LOKI_ACCESS_KEY_SECRET=$(oc -n openshift-storage get secret  rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.SecretKey}'| base64 --decode)
    export MY_LOKI_ENDPOINT=$(oc -n openshift-storage get secret  rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.Endpoint}'| base64 --decode)
    local lf_operator_namespace="${MY_LOGGING_NAMESPACE}"
    local lf_type="Secret"
    local lf_cr_name=$MY_LOKI_SECRET
    local lf_yaml_file="${MY_RESOURCESDIR}loki-secret.yaml"
    decho 3 "MY_LOKI_ACCESS_KEY_ID=$MY_LOKI_ACCESS_KEY_ID|MY_LOKI_ACCESS_KEY_SECRET=$MY_LOKI_ACCESS_KEY_SECRET|MY_LOKI_ENDPOINT=$MY_LOKI_ENDPOINT"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

    # Create a LokiStack instance
    local lf_file="${MY_OPERANDSDIR}Loki-Capability.yaml"
    local lf_ns=$MY_LOGGING_NAMESPACE
    local lf_path="{.status.conditions[0].type}"
    local lf_resource="$MY_LOKI_INSTANCE_NAME"
    local lf_state="Ready"
    local lf_type="LokiStack"
    local lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # SB]20241204 Configuring LokiStack log store
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/cluster-logging-loki.html

    # Create a new group fro the cluster-admin user role
    oc adm groups new cluster-admin

    # add the desired user to the cluster-admin group
    oc adm groups add-users cluster-admin $MY_USER

    # add the cluster-admin user role to the cluster-admin group
    oc adm policy add-cluster-role-to-group cluster-admin cluster-admin
    
    # Fine grained access for Loki logs
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/cluster-logging-loki.html#logging-loki-log-access_cluster-logging-loki
    # TO DO ?!

    # SB]20241125 Attention, depuis la version 6.0 des APIs Logging, plus de ClusterLogging et ClusterLogForwarder:
    # Starting with this release, the operator no longer supports the ClusterLogging.logging.openshift.io and ClusterLogForwarder.logging.openshift.io 
    # custom resources. See the product documentation for additional details about the replacement features.
    # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/logging/logging-6-0#log6x0-release-notes
    # https://issues.redhat.com/browse/LOG-5803
    # https://docs.openshift.com/container-platform/4.16/observability/logging/logging-6.0/log6x-about.html
    # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/logging/logging-6-0#quick-start
    # https://docs.openshift.com/container-platform/4.16/observability/logging/logging-6.1/log6x-about-6.1.html
    # Sur ce dernier lien, dans le pargraphe Quick start sont décrites les deux options suivantes:
    # ViaQ (General Availability) et OpenTelemetry (Technology Preview)
    # TODO CONFIGURE ClusterLogForwarder

  fi

  decho 3 "F:OUT:install_logging_loki"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Install Redhat Cluster Observability Operator
# # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview
function install_cluster_observability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_cluster_observability"

  # Openshift Observability
  if $MY_COO; then
    # Create a service account for the collector
    oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    # Create a ClusterRole for the collector
    oc apply -f "${MY_RESOURCESDIR}collector-ClusterRole.yaml"

    # Bind the ClusterRole to the service account
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # SB]20241203 https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/logging/logging-6-0#cluster-role-binding-for-your-service-account
    envsubst <"${MY_RESOURCESDIR}role_binding.yaml" | oc apply -f - || exit 1

    # Install the Cluster Observability Operator
    # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview

    # Create a subscription object for Cluster Observability Operator
    local lf_operator_name="$MY_COO_OPERATOR"
    local lf_operator_namespace="$MY_OPERATORS_NAMESPACE"
    local lf_operator_chl=$MY_COO_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="redhat-operators"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_COO_OPERATOR
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

  decho 3 "F:OUT:install_cluster_observability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Install Logging ViaQ (Create policies for access, will be replaced by OpenTelemetry)
# https://docs.openshift.com/container-platform/4.16/observability/logging/logging-6.1/log6x-about-6.1.html
# Pre requisite : Install the Red Hat OpenShift Logging Operator, Loki Operator, and Cluster Observability Operator (COO)
# Do not forget to login/logout if logs do not appear under the Observe section of the OpenShift Web UI

function install_logging_viaq() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_logging_viaq"

  # Openshift Observability
  if $MY_COO; then
    # Create a service account for the collector
    oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    # Allow the collector’s service account to write data to the LokiStack CR
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to collect logs
    oc project $MY_LOGGING_NAMESPACE
    oc adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA

    # Create a UIPlugi CR to enable the Log section in the Observe tab
    envsubst <"${MY_RESOURCESDIR}uiplugin.yaml" | oc apply -f - || exit 1

    # Create a ClusterLogForwarder CR to configure log forwarding
    envsubst <"${MY_RESOURCESDIR}clusterlogforwarder-viaq.yaml" | oc apply -f - || exit 1
  fi

  decho 3 "F:OUT:install_logging_viaq"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Install Logging OpenTelemetry
# https://docs.openshift.com/container-platform/4.16/observability/logging/logging-6.1/log6x-about-6.1.html
# Pre requisite : Install the Red Hat OpenShift Logging Operator, Loki Operator, and Cluster Observability Operator (COO)
function install_logging_otel() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_logging_otel"

  # Openshift Observability
  if $MY_COO; then
    # Create a service account for the collector
    oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    # Allow the collector’s service account to write data to the LokiStack CR
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to collect logs
    oc project $MY_LOGGING_NAMESPACE
    oc adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA

    # Create a UIPlugin CR to enable the Log section in the Observe tab
    decho 3 "install_openshift_monitoring create the UI plugin"
    envsubst <"${MY_RESOURCESDIR}uiplugin.yaml" | oc apply -f - || exit 1

    # Create a ClusterLogForwarder CR to configure log forwarding
    envsubst <"${MY_RESOURCESDIR}clusterlogforwarder-otel.yaml" | oc apply -f - || exit 1

    # Bind the ClusterRole to the service account
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA
  fi

  decho 3 "F:OUT:install_logging_otel"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}


###############################################
# Install/Configure Redhat Cluster Monitoring
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/index
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/common-monitoring-configuration-scenarios#configuring-core-platform-monitoring-postinstallation-steps_common-monitoring-configuration-scenarios
# 
function install_cluster_monitoring() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_cluster_monitoring"

  # Openshift cluster monitoring
  if $MY_CLUSTER_MONITORING; then
    # Create the cluster-monitoring-config cm
    export MY_MONITORING_CM_NAME="cluster-monitoring-config"
    export MY_MONITORING_NAMESPACE="openshift-monitoring"
    envsubst <"${MY_RESOURCESDIR}monitoring-cm.yaml" | oc apply -f - || exit 1

    # Enable monitoring for user-defines projects
    # If you enable monitoring for user-defined projects, the user-workload-monitoring-config ConfigMap object is created by default.
    # The enableUserWorkload parameter enables monitoring for user-defined projects in the OpenShift cluster. 
    # This action creates a prometheus-operated service in the openshift-user-workload-monitoring namespace.

    #export MY_MONITORING_CM_NAME="user-workload-monitoring-config"
    #export MY_MONITORING_NAMESPACE="openshift-user-workload-monitoring"
    #envsubst <"${MY_RESOURCESDIR}monitoring-cm.yaml" | oc apply -f - || exit 1 
    oc patch configmap cluster-monitoring-config -n openshift-monitoring --type=merge --patch '{"data":{"config.yaml":"enableUserWorkload: true\n"}}'

    # Granting users permissions for core platform monitoring
  fi

  decho 3 "F:OUT:install_cluster_monitoring"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

##################################################
# Install OADP (OpenShift API for Data Protection)
function install_oadp() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_oadp"

  mylog info "==== Redhat Openshift OADP." 1>&2
  # OpenShift restricts creating namespaces with the openshift- prefix via oc create namespace. 
  # AD]20250115: Not sure if this is still true
  # However, you can bypass this limitation using oc apply:
  create_namespace $MY_OADP_NAMESPACE $MY_OADP_NAMESPACE "For OpenShift API for Data Protection"
  # export MY_NAMESPACE=$MY_OADP_NAMESPACE
  # envsubst <"${MY_RESOURCESDIR}namespace.yaml" | oc apply -f - || exit 1

  # Operator group for OADP in single namespace
  local lf_type="OperatorGroup"
  local lf_cr_name="${MY_OADP_OPERATORGROUP}"
  local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
  local lf_namespace=$MY_OADP_NAMESPACE
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"  

  # SB]20241120 Pour obtenir le template de l'operateur oadp de Redhat, je l'ai installé avec la console, j'ai récupéré le Yaml puis désinstallé.
  local lf_operator_name="redhat-oadp-operator"
  local lf_operator_namespace=$MY_OADP_NAMESPACE
  local lf_operator_chl=$MY_OADP_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_OADP_OPERATOR
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho 3 "F:OUT:install_oadp"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install redhat Pipelines (tekton)
function install_pipelines() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_pipelines"

  # https://docs.openshift.com/pipelines/1.14/install_config/installing-pipelines.html

  mylog info "==== Redhat Openshift Pipelines (tekton)." 1>&2
  local lf_operator_name="$MY_PIPELINES_OPERATORGROUP"
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_operator_chl="latest"
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_PIPELINES_CASE
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho 3 "F:OUT:install_pipelines"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Add mailhog app to openshift
# Port is hard coded to 8025 and is defined by mailhog (default port)
function install_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_mailhog"

  if $MY_MAILHOG; then
    mylog info "==== Installing mailhog (server and client)." 1>&2
    local lf_type="deployment"
    local lf_name="mailhog"

    # May need some properties
    # read_config_file "${MY_YAMLDIR}ldap/ldap.properties"

    # create namespace if needed
    create_namespace ${MY_MAIL_SERVER_NAMESPACE} "${MY_MAIL_SERVER_NAMESPACE} project" "For Mailhog fake SMTP server deployment"

    deploy_mailhog ${lf_type} ${lf_name} ${MY_MAIL_SERVER_NAMESPACE}
    expose_service_mailhog ${lf_name} ${MY_MAIL_SERVER_NAMESPACE} '8025'
  fi

  decho 3 "F:OUT:install_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Add OpenLdap app to openshift
function install_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_openldap"

  if $MY_LDAP; then
    mylog info "==== Installing OpenLdap." 1>&2
    local lf_type="deployment"
    local lf_name="openldap"

    read_config_file "${MY_YAMLDIR}ldap/ldap.properties"

    # create namespace if needed
    create_namespace ${MY_LDAP_NAMESPACE} "${MY_LDAP_NAMESPACE} project" "For OpenLDAP deployment"

    #SB]20231207 checks if used directories and files exists
    check_file_exist ${MY_YAMLDIR}ldap/ldap-pvc.main.yaml
    check_file_exist ${MY_YAMLDIR}ldap/ldap-pvc.config.yaml
    check_file_exist ${MY_YAMLDIR}ldap/ldap-config.json
    check_file_exist ${MY_YAMLDIR}ldap/ldap-users.ldif

    provision_persistence_openldap ${MY_LDAP_NAMESPACE}
    deploy_openldap ${lf_type} ${lf_name} ${MY_LDAP_NAMESPACE}
    expose_service_openldap ${lf_name} ${MY_LDAP_NAMESPACE}
  fi

  decho 3 "F:OUT:install_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Cert Manager
function install_cert_manager() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_cert_manager"

  mylog info "==== Redhat Cert Manager catalog." 1>&2
  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="redhat-operators"
  lf_catalogsource_dspname="Red Hat Operators"
  lf_catalogsource_image="registry.redhat.io/redhat/redhat-operator-index:v4.12"
  lf_catalogsource_publisher="Red Hat"
  lf_catalogsource_interval="10m"
  decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
  create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

  # SB]20231215 Pour obtenir le template de l'operateur cert-manager de Redhat, je l'ai installé avec la console, j'ai récupéré le Yaml puis désinstallé.
  local lf_operator_name="openshift-cert-manager-operator"
  local lf_operator_namespace=$MY_CERTMANAGER_OPERATOR_NAMESPACE
  local lf_operator_chl=$MY_CERT_MANAGER_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_CERTMANAGER_CASE
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho 3 "F:OUT:install_cert_manager"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Licensing Server
function install_lic_srv() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_lic_srv"

  # ibm-license-server
  if $MY_LIC_SRV; then
    mylog info "==== IBM License Server." 1>&2
    check_add_cs_ibm_pak ibm-licensing amd64

    # Operator group for License Service Reporter in single namespace
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LICENSE_SERVER_OPERATORGROUP}"
    local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
    local lf_namespace=$MY_LICENSE_SERVER_NAMESPACE
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    #mylog info "Creating Licensing service catalog source in ns : openshift-marketplace." 1>&2
    lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
    lf_catalogsource_name="ibm-licensing-catalog"
    lf_catalogsource_dspname="ibm-licensing"
    lf_catalogsource_image="icr.io/cpopen/ibm-licensing-catalog"
    lf_catalogsource_publisher="IBM"
    lf_catalogsource_interval="45m"
    decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
    create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

    #mylog info "Creating License Service Reporter catalog source in ns : openshift-marketplace." 1>&2
    lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
    lf_catalogsource_name="ibm-license-service-reporter-operator-catalog"
    lf_catalogsource_dspname="IBM License Service Reporter Catalog"
    lf_catalogsource_image="icr.io/cpopen/ibm-license-service-reporter-operator-catalog"
    lf_catalogsource_publisher="IBM"
    lf_catalogsource_interval="45m"
    decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
    create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

    # ATTENTION : pour le licensing server ajouter dans la partie spec.startingCSV: ibm-licensing-operator.v4.2.1 (sinon erreur).
    local lf_operator_name="ibm-licensing-operator-app"
    local lf_operator_namespace=$MY_LICENSE_SERVER_NAMESPACE
    local lf_operator_chl=$MY_LIC_SRV_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-licensing-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_LICENSE_SERVER_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    mylog info "Installing the License Service Reporter operator" 1>&2
    local lf_operator_name="ibm-license-service-reporter-operator"
    local lf_operator_namespace=$MY_LICENSE_SERVER_NAMESPACE
    local lf_operator_chl=$MY_LIC_SRV_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-license-service-reporter-operator-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_LICENSE_SERVER_REPORTER_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    mylog info "Creating the License Service Reporter instance" 1>&2
    # Creating Creating the License Service Reporter instance 
    lf_file="${MY_OPERANDSDIR}LIC-Reporter-Capability.yaml"
    lf_ns="${MY_LICENSE_SERVER_NAMESPACE}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_LICENSE_SERVER_REPORTER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IBMLicenseServiceReporter"
    mylog warn "Saad: Check that it is working to wait for the state, if not we need a temporisation" 1>&2
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
    
    # Add license service to the reporter
    mylog info "Add license service to the reporter" 1>&2
    decho 3 "oc -n ${MY_LICENSE_SERVER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name==\"ibm-license-service-reporter\")].spec.host}'"
    lf_licensing_service_reporter_url=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-license-service-reporter")].spec.host}')
    decho 4 "License Service Reporter URL: $lf_licensing_service_reporter_url"
    oc -n $MY_LICENSE_SERVER_NAMESPACE patch IBMLicensing instance --type merge --patch "{\"spec\":{\"sender\":{\"reporterSecretToken\":\"ibm-license-service-reporter-token\",\"reporterURL\":\"https://$lf_licensing_service_reporter_url/\",\"clusterID\":\"MyClusterTest1\",\"clusterName\":\"MyClusterTest1\"}}}"
  fi

  decho 3 "F:OUT:install_lic_srv"
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
  decho 3 "F:IN :install_fs"

  mylog info "==== IBM Common Services." 1>&2
  # ibm-cp-common-services
  check_add_cs_ibm_pak $MY_COMMONSERVICES_CASE amd64

  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="opencloud-operators"
  lf_catalogsource_dspname="IBMCS Operators"
  # lf_catalogsource_image="icr.io/cpopen/ibm-common-service-catalog:4.3"
  lf_catalogsource_image="icr.io/cpopen/ibm-common-service-catalog:latest"
  lf_catalogsource_publisher="IBM"
  lf_catalogsource_interval="45m"
  decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
  create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

  local lf_operator_name="ibm-common-service-operator"
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_operator_chl=$MY_FOUNDATIONALSERVICES_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="opencloud-operators"
  local lf_wait_for_state=true
  local lf_csv_name="ibm-common-service-operator"
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  ## Setting hardware  Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
  #accept_license_fs $MY_OPERATORS_NAMESPACE
  accept_license_fs $lf_operator_namespace

  # Configuring foundational services by using the CommonService custom resource.
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_type="CommonService"
  local lf_cr_name=$MY_COMMONSERVICES_INSTANCE_NAME
  local lf_yaml_file="${MY_RESOURCESDIR}foundational-services-cr.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

  decho 3 "F:OUT:install_fs"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Open Liberty
function install_openliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_openliberty"

  # backend J2EE applications
  if $MY_OPENLIBERTY; then
    mylog info "==== Installing OPEN Liberty." 1>&2

    create_namespace $MY_BACKEND_NAMESPACE "$MY_BACKEND_NAMESPACE project" "For Open Liberty instances and create custom API"

    # TODO other approach is to use the catalog which already inludes the Open Liberty operator and use a subscription
    # Case exists 1.3.1, and IBM/RedHat Catalog

    export OPEN_LIBERTY_OPERATOR_NAMESPACE=$MY_BACKEND_NAMESPACE
    export OPEN_LIBERTY_OPERATOR_WATCH_NAMESPACE=$MY_BACKEND_NAMESPACE

    # TODO Check that is this value
    export WATCH_NAMESPACE='""'
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}config/ ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-rbac-watch-all.yaml
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}config/ ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-crd.yaml
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}config/ ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-operator.yaml

    # Creating Open Liberty operator subscription (Check arbitrarely one resource, the deployment of the operator)
    local lf_octype='deployment'
    local lf_name='olo-controller-manager'

    # check if deployment of the operator already performed
    mylog check "Checking ${lf_octype} ${lf_name} in ${MY_BACKEND_NAMESPACE}"
    if oc -n ${MY_BACKEND_NAMESPACE} get ${lf_octype} ${lf_name} >/dev/null 2>&1; then
      mylog ok
    else
      oc apply --server-side -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml
      oc apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml
      oc -n ${MY_BACKEND_NAMESPACE} apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml
    fi

  fi

  decho 3 "F:OUT:install_openliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install WebSphere Liberty
function install_wasliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_wasliberty"

  if $MY_WASLIBERTY; then
    mylog info "==== Installing WAS Liberty." 1>&2

    create_namespace $MY_BACKEND_NAMESPACE "$MY_BACKEND_NAMESPACE project" "For WebSphere Application Server (Liberty) instances and create custom API"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_WL_CASE amd64

    # mylog info "==== Adding IBM Operator catalog source in ns : openshift-marketplace." 1>&2
    lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
    lf_catalogsource_name="ibm-operator-catalog"
    lf_catalogsource_dspname="IBM Operator Catalog"
    lf_catalogsource_image="icr.io/cpopen/ibm-operator-catalog"
    lf_catalogsource_publisher="IBM"
    lf_catalogsource_interval="45m"
    decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
    create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

    # Operator group for WAS Liberty in single namespace
    lf_type="OperatorGroup"
    lf_cr_name="${MY_WAS_LIBERTY_OPERATORGROUP}"
    lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
    lf_namespace=$MY_BACKEND_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    # Creating WebSphere Liberty operator subscription
    local lf_operator_name="ibm-websphere-liberty"
    local lf_operator_namespace=$MY_BACKEND_NAMESPACE
    local lf_operator_chl=$MY_WL_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-operator-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_WL_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

  decho 3 "F:OUT:install_wasliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Navigator (depending on two boolean)
function install_navigator() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_navigator"

  ## ibm-integration-platform-navigator
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  # Creating Navigator operator subscription
  if $MY_NAVIGATOR; then
    mylog info "==== Installing Navigator." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_NAVIGATOR_CASE amd64

    # Creating Navigator operator subscription
    local lf_operator_name="$MY_NAVIGATOR_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_NAVIGATOR_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-integration-platform-navigator-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_NAVIGATOR_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"
  fi

  if $MY_NAVIGATOR_INSTANCE; then
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_NAVIGATOR_VERSION" ]; then
      export MY_NAVIGATOR_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_NAVIGATOR_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
      decho 3 "MY_NAVIGATOR_VERSION=$MY_NAVIGATOR_VERSION"
    fi

    # Creating Navigator instance
    lf_file="${MY_OPERANDSDIR}Navigator-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_NAVIGATOR_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="PlatformNavigator"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:install_navigator"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Asset Repository
function install_assetrepo() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_assetrepo"

  if $MY_ASSETREPO; then
    mylog info "==== Installing Asset Repository." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak ibm-integration-asset-repository amd64

    # Creating Asset Repository operator subscription
    local lf_operator_name="ibm-integration-asset-repository"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_ASSETREPO_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-integration-asset-repository-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_ASSETREPO_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    if $MY_ASSETREPO_INSTANCE; then
      #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
      if [ -z "$MY_ASSETREPO_VERSION" ]; then
        export MY_ASSETREPO_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ASSETREPO_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
        decho 3 "MY_ASSETREPO_VERSION=$MY_ASSETREPO_VERSION"
      fi

      # Creating Asset Repository instance
      lf_file="${MY_OPERANDSDIR}AR-Capability.yaml"
      lf_ns="${MY_OC_PROJECT}"
      lf_path="{.status.phase}"
      lf_resource="$MY_ASSETREPO_INSTANCE_NAME"
      lf_state="Ready"
      lf_type="AssetRepository"
      lf_wait_for_state=true
      create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
    fi

  fi

  decho 3 "F:OUT:install_assetrepo"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Integration Assembly
function install_intassembly() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_intassembly"

  # Creating Integration Assembly instance
  if $MY_INTASSEMBLY; then
    mylog info "==== Installing Integration Assembly." 1>&2
    lf_file="${MY_OPERANDSDIR}IntegrationAssembly-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_INTASSEMBLY_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IntegrationAssembly"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:install_intassembly"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install ACE
function install_ace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_ace"

  # ibm-appconnect
  if $MY_ACE; then
    mylog info "==== Installing ACE." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ACE_CASE amd64

    # Creating ACE operator subscription
    local lf_operator_name="$MY_ACE_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_ACE_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="appconnect-operator-catalogsource"
    local lf_csv_name=$MY_ACE_CASE
    local lf_wait_for_state=true
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_ACE_VERSION" ]; then
      export MY_ACE_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ACE_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # Creating ACE Switch Server instance (used for callable flows)
    lf_file="${MY_OPERANDSDIR}ACE-SwitchServer-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_SWITCHSERVER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="SwitchServer"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Creating ACE Dashboard instance
    lf_file="${MY_OPERANDSDIR}ACE-Dashboard-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DASHBOARD_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="Dashboard"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Creating ACE Designer instance
    lf_file="${MY_OPERANDSDIR}ACE-Designer-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DESIGNER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="DesignerAuthoring"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:install_ace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install APIC
function install_apic() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_apic"

  # ibm-apiconnect
  if $MY_APIC; then
    mylog info "==== Installing APIC." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_APIC_CASE amd64

    # Creating APIC operator subscription
    local lf_operator_name="$MY_APIC_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_APIC_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-apiconnect-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_APIC_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_APIC_VERSION" ]; then
      export MY_APIC_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_APIC_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    if $MY_APIC_BY_COMPONENT; then
      mylog info "HOLD PLACE"
    else
      # Creating APIC instance
      local lf_file="${MY_OPERANDSDIR}APIC-Capability.yaml"
      local lf_ns="${MY_OC_PROJECT}"
      local lf_path="{.status.phase}"
      local lf_resource="$MY_APIC_INSTANCE_NAME"
      local lf_state="Ready"
      local lf_type="APIConnectCluster"
      local lf_wait_for_state=true
      create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
    fi

    #AD/SB]20240703 enable the Gateway Cluster webGui Management and add webgui-port to set it accessible
    mylog info "Enable web console of the API Connect Gateway"
    oc -n "${MY_OC_PROJECT}" patch GatewayCluster "${MY_APIC_INSTANCE_NAME}-gw" --type merge -p '{"spec": {"webGUIManagementEnabled": true}}'

    local lf_type="Route"
    local lf_cr_name="${MY_APIC_INSTANCE_NAME}-gw-webconsole"
    local lf_yaml_file="${MY_RESOURCESDIR}route.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    
    export MY_NAMESPACE="${MY_OC_PROJECT}"
    export MY_ROUTE_NAME="${MY_APIC_INSTANCE_NAME}-gw-webconsole"
    export MY_ROUTE_BALANCE="roundrobin"
    export MY_ROUTE_INSTANCE="${MY_APIC_INSTANCE_NAME}-gw"
    export MY_ROUTE_PARTOF="${MY_APIC_INSTANCE_NAME}"
    export lf_ingress=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
    export MY_ROUTE_HOST="${MY_ROUTE_NAME}.${lf_ingress}"
    export MY_ROUTE_PORT=9090
    export MY_ROUTE_SERVICE=${MY_APIC_INSTANCE_NAME}-gw-datapower

    decho 3 "${MY_NAMESPACE}, ${MY_ROUTE_NAME}, ${MY_ROUTE_BALANCE}, ${MY_ROUTE_INSTANCE}, ${MY_ROUTE_PARTOF}, ${MY_ROUTE_HOST}, ${MY_ROUTE_PORT}, ${MY_ROUTE_SERVICE}"

    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    save_certificate ${MY_OC_PROJECT} cp4i-apic-ingress-ca ca.crt ${MY_WORKINGDIR}
    save_certificate ${MY_OC_PROJECT} cp4i-apic-gw-gateway ca.crt ${MY_WORKINGDIR}
  fi

  decho 3 "F:OUT:install_apic"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install APIC Graphql (Ex Stepzen)
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=installing-maintaining-api-connect-graphql
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=graphql-installing-api-connect
function install_apic_graphql() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_apic_graphql"

  # ibm apic graphql
  if $MY_APIC_GRAPHQL; then
    mylog info "==== Installing APIC Graphql." 1>&2

    # Create namespace for IBM Stepzen.
    create_namespace $MY_IBM_STEPZEN_NAMESPACE
    add_ibm_entitlement $MY_IBM_STEPZEN_NAMESPACE $MY_CONTAINER_ENGINE

    local lf_namespace="${MY_IBM_STEPZEN_NAMESPACE}"
    local lf_postgresql_host lf_dsn lf_type lf_cr_name
    local lf_case_version lf_file lf_deploy_dir
    local lf_path lf_state lf_resource lf_url

    # create a generic secret for the PostgreSQL server
    # there are three postgresql services : 
    # - ${MY_POSTGRESQL_CLUSTER}-r"  : for read-only workloads across all nodes
    # - ${MY_POSTGRESQL_CLUSTER}-ro" : for read-only workloads on replicas only
    # - ${MY_POSTGRESQL_CLUSTER}-rw" : for read-write workloads on the primary node

    lf_postgresql_host="${MY_POSTGRESQL_CLUSTER}-rw.${MY_POSTGRESQL_NAMESPACE}.svc.cluster.local"
    lf_dsn="postgresql://${MY_POSTGRESQL_USER}:${MY_POSTGRESQL_PASSWORD}@${lf_postgresql_host}/${MY_POSTGRESQL_DATABASE}"
    lf_type="Secret"
    lf_cr_name="${MY_POSTGRESQL_DSN_PASSWORD}"
    if oc -n ${lf_namespace} get ${lf_type} ${lf_cr_name} >/dev/null 2>&1; then
      mylog info "Custom Resource $lf_type/$lf_cr_name already exists"
    else
      oc -n ${lf_namespace} create secret generic $lf_cr_name --from-literal=DSN="${lf_dsn}"
    fi

    # Download and extract the CASE bundle.
    lf_case_version=$(oc ibm-pak list -o json | jq -r --arg case "$MY_APIC_GRAPHQL_CASE" '.[] | select (.name == $case ) | .latestVersion')
    oc ibm-pak get ${MY_APIC_GRAPHQL_CASE} --version ${lf_case_version} 1>&2

    lf_file=${MY_IBMPAK_CASESDIR}${MY_APIC_GRAPHQL_CASE}/${lf_case_version}/${MY_APIC_GRAPHQL_CASE}-${lf_case_version}.tgz
    if [ -e "$lf_file" ]; then
      tar xvzf ${lf_file} -C ${MY_WORKINGDIR} >/dev/null 2>&1
    fi    
    
    # Apply the operator manifest files to the cluster
    lf_deploy_dir="${MY_WORKINGDIR}/${MY_APIC_GRAPHQL_CASE}/inventory/stepzenGraphOperator/files/deploy/"
    decho 3 "Applying the operator manifest files to the cluster : crd.yaml." 1>&2
    oc -n ${lf_namespace} apply -f ${lf_deploy_dir}crd.yaml
    decho 3 "Applying the operator manifest files to the cluster : operator.yaml." 1>&2
    oc -n ${lf_namespace} apply -f ${lf_deploy_dir}operator.yaml
    sleep 10

    # Configuring APIC Graphql
    decho 3 "Configuring APIC Graphql." 1>&2
    envsubst <"${MY_RESOURCESDIR}stepzen.yaml" | oc -n ${lf_namespace} apply -f - || exit 1

    #local lf_resource=$(oc -n $lf_namespace get $lf_type -o json | jq -r --arg my_resource "$lf_cr_name" '.items[0].metadata | select (.name | contains ($my_resource)).name')
    lf_type="StepZenGraphServer"
    lf_cr_name="stepzen"
    lf_path="{.status.conditions[-1].type}"
    lf_state="Ready"

    lf_resource=$(oc -n $lf_namespace get $lf_type -o jsonpath="{.items[0].metadata.name}")
    decho 3 "wait_for_state \"$lf_type $lf_resource is $lf_state\" \"$lf_state\" \"oc -n $lf_namespace get $lf_type $lf_resource -o jsonpath='$lf_path'\""
    wait_for_state "$lf_type $lf_resource $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_resource -o jsonpath='$lf_path'"

    # Creating APIC Graphql route
    # first create a cluster issuer
    #envsubst <"${MY_RESOURCESDIR}self-signed-cluster-issuer.yaml" | oc apply -f - || exit 1
    envsubst <"${MY_RESOURCESDIR}letsencrypt-cluster-issuer.yaml" | oc -n ${lf_namespace} apply -f - || exit 1

    # The first method to get the cluster domain
    #lf_url=$(oc get infrastructure cluster -o jsonpath='{.status.apiServerURL}')
    #export MY_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1)
    #export MY_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1 | cut -d'.' -f2-)

    # The second method to get the cluster domain
    export MY_CLUSTER_DOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
    decho 3 "MY_CLUSTER_DOMAIN=$MY_CLUSTER_DOMAIN"

    # Add the certificate csr for routes (following chatgpt advice)
    envsubst <"${MY_RESOURCESDIR}stepzen-graphql-csr.yaml" | oc apply -f - || exit 1

    # Then Install OpenShift Route Support for cert-manager (openshift-routes).
    # ATTENTION REVOIR le namespace : c'est cert-manager et non pas cert-manager-namespace (https://github.com/cert-manager/openshift-routes?tab=readme-ov-file)
    # https://github.com/cert-manager/openshift-routes
    helm install openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes
    #oc -n cert-manager apply -f <(helm template openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes --set omitHelmLabels=true)

    # Set up a stepzen-graph-server route for the stepzen account. This is the "root" account of the API Connect Graphql service, 
    # which is used to host endpoints that modify the metadata database but does not serve application requests. 
    # The stepzen-graph-server route is required for the API Connect Graphql CLI to function.
    envsubst <"${MY_RESOURCESDIR}stepzen-route.yaml" | oc -n ${lf_namespace} apply -f - || exit 1

    # Set up stepzen-graph-server and stepzen-graph-server-subscriptions routes for the graphql account.
    # This is the default account for serving application requests.
    envsubst <"${MY_RESOURCESDIR}graphql-route.yaml" | oc -n ${lf_namespace} apply -f - || exit 1

    # Install Introspection service
    envsubst <"${MY_RESOURCESDIR}introspection.yaml" | oc -n ${lf_namespace} apply -f - || exit 1

  fi

  decho 3 "F:OUT:install_apic_graphql"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}


################################################
# Uninstall APIC Graphql (Ex Stepzen)
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=installing-maintaining-api-connect-graphql
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=graphql-installing-api-connect
function uninstall_apic_graphql() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_apic_graphql"

  # ibm apic graphql
  if $MY_APIC_GRAPHQL; then
    mylog info "==== Uninstalling APIC Graphql." 1>&2

    local lf_namespace="${MY_IBM_STEPZEN_NAMESPACE}"
    #-- Uninstall start here
    # delete stepzen-graph-server and stepzen-graph-server-subscriptions routes for the graphql account.
    # This is the default account for serving application requests.
    envsubst <"${MY_RESOURCESDIR}graphql-route.yaml" | oc -n ${lf_namespace} delete -f - #|| exit 1

    # delete stepzen-graph-server route for the stepzen account. This is the "root" account of the API Connect Graphql service, 
    # which is used to host endpoints that modify the metadata database but does not serve application requests. 
    # The stepzen-graph-server route is required for the API Connect Graphql CLI to function.
    local lf_url=$(oc get infrastructure cluster -o jsonpath='{.status.apiServerURL}')
    export MY_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1)
    envsubst <"${MY_RESOURCESDIR}stepzen-route.yaml" | oc -n ${lf_namespace} delete -f - #|| exit 1

    # delete OpenShift Route Support for cert-manager (openshift-routes).
    # ATTENTION REVOIR le namespace : c'est cert-manager et non pas cert-manager-namespace (https://github.com/cert-manager/openshift-routes?tab=readme-ov-file)
    # https://github.com/cert-manager/openshift-routes
    #oc delete -f <(helm template openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes --set omitHelmLabels=true)
    helm uninstall openshift-routes -n cert-manager

    # delete the certificate csr for routes (following chatgpt advice)
    envsubst <"${MY_RESOURCESDIR}stepzen-graphql-csr.yaml" | oc delete -f - #|| exit 1
    
    # delete APIC Graphql route
    # first create a cluster issuer
    envsubst <"${MY_RESOURCESDIR}self-signed-cluster-issuer.yaml" | oc delete -f - #|| exit 1
    #envsubst <"${MY_RESOURCESDIR}letsencrypt-cluster-issuer.yaml" | oc delete -f - #|| exit 1

    # Deleteing APIC Graphql
    envsubst <"${MY_RESOURCESDIR}stepzen.yaml" | oc delete -n ${lf_namespace} -f - #|| exit 1

    # Delete the operator manifest files to the cluster
    #lf_namespace="${MY_IBM_STEPZEN_NAMESPACE}"
    local lf_deploy_dir="${MY_WORKINGDIR}/${MY_APIC_GRAPHQL_CASE}/inventory/stepzenGraphOperator/files/deploy/"
    oc -n ${lf_namespace} delete -f ${lf_deploy_dir}crd.yaml
    oc -n ${lf_namespace} delete -f ${lf_deploy_dir}operator.yaml

    rm -rf ${MY_WORKINGDIR}${MY_APIC_GRAPHQL_CASE}

    # delete catalog sources using ibm_pak plugin
    check_delete_cs_ibm_pak $MY_APIC_GRAPHQL_CASE amd64

    local lf_type="Secret"
    local lf_cr_name="${MY_POSTGRESQL_DSN_PASSWORD}"    
    lf_namespace="${MY_IBM_STEPZEN_NAMESPACE}"
    if oc -n ${lf_namespace} get ${lf_type} ${lf_cr_name} >/dev/null 2>&1; then
      oc -n ${lf_namespace} delete secret $lf_cr_name
    else
      mylog info "Custom Resource $lf_type/$lf_cr_name already deleted"
    fi

    # Create namespace for IBM Stepzen.
    delete_ibm_entitlement $MY_IBM_STEPZEN_NAMESPACE $MY_CONTAINER_ENGINE
    delete_namespace $MY_IBM_STEPZEN_NAMESPACE
  fi

  decho 3 "F:OUT:uninstall_apic_graphql"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install IBM Event streams
function install_es() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_es"

  # ibm-eventstreams
  if $MY_ES; then
    mylog info "==== Installing Event Streams." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ES_CASE amd64

    # Creating EventStreams operator subscription
    local lf_operator_name="$MY_ES_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_ES_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-eventstreams"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_ES_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_ES_VERSION" ]; then
      export MY_ES_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ES_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # Creating Event Streams instance
    lf_file="${MY_OPERANDSDIR}ES-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_ES_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventStreams"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3  "F:OUT:install_es"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install EEM
function install_eem() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_eem"

  local lf_in_ns=$1
  local varb64

  if $MY_EEM; then
    mylog info "==== Installing Event Endpoint Management." 1>&2
    ## event endpoint management
    ## to get the name of the pak to use : oc ibm-pak list
    ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
    check_add_cs_ibm_pak $MY_EEM_CASE amd64

    # Creating Event Endpoint Management operator subscription
    lf_operator_name="ibm-eventendpointmanagement"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_operator_chl=$MY_EEM_CHL
    lf_strategy="Automatic"
    lf_catalog_source_name="ibm-eventendpointmanagement-catalog"
    lf_wait_for_state=true
    lf_csv_name=$MY_EEM_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_EEM_VERSION" ]; then
      export MY_EEM_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_EEM_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # Creating EventEndpointManager instance (Event Processing)
    if $MY_KEYCLOAK_INTEGRATION; then
      export MY_EEM_AUTH_TYPE=INTEGRATION_KEYCLOAK
    else
      export MY_EEM_AUTH_TYPE=LOCAL
    fi
    
    lf_file="${MY_OPERANDSDIR}EEM-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EEM_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventEndpointManagement"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    ## Creating EEM users and roles
    if $MY_KEYCLOAK_INTEGRATION; then
      # generate properties files
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ keycloak-user-roles
      # keycloak user roles
      varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/keycloak-user-roles.yaml" | base64 -w0)
      oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]"
    else
      # generate properties files
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ local-user-credentials.yaml
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ local-user-roles.yaml
      # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
      # local user credentials
      varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/local-user-credentials.yaml" | base64 -w0)
      oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]"
      # local user roles
      varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/local-user-roles.yaml" | base64 -w0)
      oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]"
    fi
  fi
  
  decho 3 "F:OUT:install_eem"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install EGW
function install_egw() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_egw"

  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW; then
    mylog info "==== Installing Event Endpoint Gateway." 1>&2
    export MY_EEM_MANAGER_GATEWAY_ROUTE=$(oc -n $MY_OC_PROJECT get eem $MY_EEM_INSTANCE_NAME -o jsonpath='{.status.endpoints[1].uri}')

    lf_file="${MY_OPERANDSDIR}EG-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EGW_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventGateway"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:install_egw"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create keycloak client
function create_keycloak_client() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_keycloak_client"

  local lf_keycloak_admin
  local lf_keycloak_admin_passwordkeycloak_access_token
  local lf_keycloak_host
  local lf_keycloak_access_token
  local lf_keycloak_refresh_token
  local lf_keycloak_client
  
  # get keycloak infos
  lf_keycloak_admin=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret cs-keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode)
  lf_keycloak_admin_password=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret cs-keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode)
  lf_keycloak_host=$(oc -n $MY_COMMONSERVICES_NAMESPACE get route keycloak -o jsonpath='{.spec.host}')

  local lf_keycloak_access_token=$(curl -X POST "https://${lf_keycloak_host}/realms/master/protocol/openid-connect/token" \
                                        -H "Content-Type: application/x-www-form-urlencoded" \
                                        -d "username=${lf_keycloak_admin}" \
                                        -d "password=${lf_keycloak_admin_password}" \
                                        -d "grant_type=password" \
                                        -d "client_id=admin-cli" 2> /dev/null | jq -r .access_token)

  decho 3 "lf_keycloak_admin=$lf_keycloak_admin|lf_keycloak_admin_password=$lf_keycloak_admin_password"
  decho 3 "lf_keycloak_access_token=$lf_keycloak_access_token"
  # Create a keycloak client
  curl -X POST "https://${lf_keycloak_host}/admin/realms/master/clients" \
       -H "Authorization: Bearer $lf_keycloak_access_token" \
       -H "Content-Type: application/json" \
       -d '{
             "clientId": "'"${MY_KEYCLOAK_CLIENT}"'",
             "enabled": true,
             "redirectUris": ["https://my-app.example.com/callback"],
             "publicClient": false,
             "protocol": "openid-connect"
         }'
  # Get the created client
  lf_keycloak_client=$(curl -X GET "https://${lf_keycloak_host}/admin/realms/master/clients" \
                            -H "Authorization: Bearer $lf_keycloak_access_token" \
                            -H "Content-Type: application/json" | jq --arg clientId "$MY_KEYCLOAK_CLIENT" '.[] | select (.clientId == $clientId)' )
                                             

  # SB]20240612 prise en compte de l'existence ou non de la variable portant la version
  if [ -z "$lf_keycloak_client" ]; then
    mylog info "no keycloak client created"
  else
    decho 3 "lf_keycloak_client=$lf_keycloak_client"
  fi
  
  decho 3 "F:OUT:create_keycloak_client"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install EP
function install_ep() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_ep"

  local lf_in_ns=$1
  local varb64

  if $MY_EP; then
    mylog info "==== Installing Event Processing." 1>&2
    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_EP_CASE amd64

    ## Creating Event processing operator subscription
    local lf_operator_name="$MY_EP_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_EP_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-eventprocessing-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_EP_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_EP_VERSION" ]; then
      export MY_EP_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_EP_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    ## SB]20231023 to check the status of Event processing : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The Status column displays the current state of the EventProcessing custom resource.
    ## When the Event Processing instance is ready, the phase displays Phase: Running.
    ## Creating EventProcessing instance (Event Processing)
    ## oc -n <namespace> get eventprocessing <instance-name> -o jsonpath='{.status.phase}'
    ## Creating Event processing instance

    # 20241127 : Problem The EventProcessing "cp4i-ep" is invalid: spec.authoring.authConfig.authType: Unsupported value: "INTEGRATION_KEYCLOAK": supported values: "LOCAL", "OIDC"
    # so use LOCAL or OIDC
    if $MY_KEYCLOAK_INTEGRATION; then
      export MY_EP_AUTH_TYPE=LOCAL
      # export MY_EP_AUTH_TYPE=OIDC
    else
      export MY_EP_AUTH_TYPE=LOCAL
    fi
    lf_file="${MY_OPERANDSDIR}EP-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_EP_INSTANCE_NAME"
    lf_state="Running"
    lf_type="EventProcessing"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # generate properties files
    adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-credentials.yaml
    adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-roles.yaml

    # user credentials
    varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-credentials.yaml" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$varb64\"}]"

    # user roles
    varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-roles.yaml" | base64 -w0)
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$varb64\"}]"
  fi

  decho 3 "F:OUT:install_ep"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Flink
function install_flink() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_flink"

  local lf_in_ns=$1
  if $MY_FLINK; then
    mylog info "==== Installing Flink." 1>&2
    # add catalog sources using ibm_pak plugin
    ## SB]20231020 For Flink and Event processing first you have to apply the catalog source to your cluster :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter Applying catalog sources to your cluster
    # event flink
    check_add_cs_ibm_pak $MY_FLINK_CASE amd64

    ## SB]20231020 For Flink and Event processing install the operator with the following command :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter : Install the operator by using the CLI (oc ibm-pak)
    ## event flink
    ## Creating Eventautomation Flink operator subscription
    ## Creating Event processing operator subscription
    local lf_operator_name="$MY_FLINK_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_FLINK_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-eventautomation-flink-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_FLINK_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    ## Creation of Event automation Flink PVC and instance
    # Even if it's a pvc we use the same generic function
    lf_file="${MY_OPERANDSDIR}EA-Flink-PVC.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="ibm-flink-pvc"
    lf_state="Bound"
    lf_type="PersistentVolumeClaim"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_FLINK_VERSION" ]; then
      export MY_FLINK_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_FLINK_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    ## SB]20231023 to check the status of created Flink instance : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The status field displays the current state of the FlinkDeployment custom resource.
    ## When the Flink instance is ready, the custom resource displays status.lifecycleState: STABLE and status.jobManagerDeploymentStatus: READY.
    ## STANLE and READY (uppercase!!!)
    lf_file="${MY_OPERANDSDIR}EA-Flink-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.lifecycleState}-{.status.jobManagerDeploymentStatus}"
    lf_resource="$MY_FLINK_INSTANCE_NAME"
    lf_state="STABLE-READY"
    lf_type="FlinkDeployment"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:install_flink"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Aspera HSTS
function install_hsts() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_hsts"

  # ibm aspera hsts
  if $MY_HSTS; then
    mylog info "==== Installing HSTS." 1>&2

    # Asperac License
    export MY_ASPERA_LICENSE_FILE="${MY_PRIVATEDIR}aspera-license"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_HSTS_CASE amd64

    # Creating Aspera HSTS operator subscription
    local lf_operator_name="aspera-hsts-operator"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_HSTS_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="aspera-operators"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_HSTS_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    lf_file="${MY_OPERANDSDIR}AsperaHSTS-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_HSTS_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IbmAsperaHsts"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:install_hsts"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install MQ
function install_mq() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_mq"

  # ibm-mq
  if $MY_MQ; then
    mylog info "==== Installing MQ." 1>&2

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_MQ_CASE amd64

    # Creating MQ operator subscription
    local lf_operator_name="$MY_MQ_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_MQ_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibmmq-operator-catalogsource"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_MQ_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Use the new CRD MessagingServer(available since CP4I 16.1.0-SC2) 
    if $MY_MESSAGINGSERVER; then
      # Creating MQ MessagingServer instance
      lf_file="${MY_OPERANDSDIR}MessagingServer-Capability.yaml"
      lf_ns="${MY_OC_PROJECT}"
      lf_path="{.status.conditions[0].type}"
      lf_resource="$MY_MSGSRV_INSTANCE_NAME"
      lf_state="Ready"
      lf_type="MessagingServer"
      lf_wait_for_state=true
      create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
    fi

  fi

  decho 3 "F:OUT:install_mq"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install Instana
function install_instana() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_instana"

  # SB]20240629 Instana Agent key
  export MY_INSTANA_AGENT_KEY=$(cat "${MY_PRIVATEDIR}instana_agent_key.txt")
  export MY_INSTANA_EP_HOST=ingress-orange-saas.instana.io
  export MY_INSTANA_ZONE_NAME="${MY_USER_EMAIL%@*}"

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA; then
    mylog info "==== Adding Instana." 1>&2
    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    create_namespace $MY_INSTANA_AGENT_NAMESPACE "$MY_INSTANA_AGENT_NAMESPACE project" "For monitoring with Instana"
    oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy add-scc-to-user privileged -z instana-agent

    local lf_operator_name="instana-agent-operator"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_INSTANA_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="certified-operators"
    local lf_csv_name=$MY_INSTANA_CSV_NAME
    local lf_wait_for_state=true
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Creating Instana agent
    lf_file="${MY_OPERANDSDIR}Instana-Agent-CloudIBM-Capability.yaml"
    lf_ns="${MY_INSTANA_AGENT_NAMESPACE}"
    lf_path="{.status.numberReady}"
    lf_resource="$MY_INSTANA_INSTANCE_NAME"
    lf_state="$MY_CLUSTER_WORKERS"
    lf_type="daemonset"
    lf_wait_for_state=true
    create_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:install_instana"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Install PostGreSQL cloudnative-pg, see https://github.com/cloudnative-pg/cloudnative-pg TODO This does not work
# SB]20241228 : after many tentatives to install PostgrSQL, getting errors (conflict errors, no operator errors, ...). I found that PostgreSQL operator
# is already installed and a subscription already exists (edb-keycloak)
#  !!! check to see how to use it because it's a pre requisite for installing IBM APIC Graphql
function install_postgresql() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_postgresql"

  if $MY_POSTGRESQL; then

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_POSTGRESQL_CASE amd64

    mylog info "==== Adding PostGreSQL." 1>&2
    # Create namespace for PostGreSQL.
    create_namespace $MY_POSTGRESQL_NAMESPACE

   ## # Catalog source for CloudNativePG
   ## mylog info "==== cloudnative-pg-catalog catalog." 1>&2
   ## lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
   ## lf_catalogsource_name="cloud-native-postgresql-catalog"
   ## lf_catalogsource_dspname="ibm-cloud-native-postgresql-4.25.0"
   ## lf_catalogsource_image="icr.io/cpopen/ibm-cpd-cloud-native-postgresql-operator-catalog@sha256:0b46a3ec66622dd4a96d96243602a21d7a29cd854f67a876ad745ec524337a1f"
   ## lf_catalogsource_publisher="IBM"
   ## lf_catalogsource_interval="10m"
   ## decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
   ## create_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

   ## # Operator group for PostGreSQL in single namespace (TODO should it be operators.coreos.com/v1 instead of operators.coreos.com/v1alpha2)
   ## lf_type="OperatorGroup"
   ## lf_cr_name="${MY_POSTGRESQL_OPERATORGROUP}"
   ## lf_yaml_file="${MY_RESOURCESDIR}operator-group-singlev1.yaml"
   ## lf_namespace=$MY_POSTGRESQL_NAMESPACE
   ## check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    # Creating EDB Postgres for Kubernetes operator subscription
    local lf_operator_name="edb-cloud-native-postgresql"
    #local lf_operator_namespace=$MY_POSTGRESQL_NAMESPACE
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_POSTGRESQL_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="cloud-native-postgresql-catalog"
    #local lf_catalog_source_name="integration-ibm-cloud-native-postgresql"
    local lf_csv_name=$MY_POSTGRESQL_CASE
    local lf_wait_for_state=true
    #export MY_STARTING_CSV="${MY_POSTGRESQL_STARTINGCSV}"
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # todo postgres : which operator to use :
    # oc ibm-pak list | grep post
    # CASE repository: IBM Cloud-Pak Github Repo (https://github.com/IBM/cloud-pak/raw/master/repo/case/)
    # ibm-cloud-native-postgresql                         5.10.0+20241023.134419.2070          1.22.7
    # ibm-postgreservice                                  1.3.1                                3.5.1-rc1-202210172202
  fi

  decho 3 "F:OUT:install_postgresql"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Create a PostGreSQL DB
#
function create_postgresql_db() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :create_postgresql_db"

  if $MY_POSTGRESQL_DB; then
    
    # Create namespace for PostGreSQL.
    #export MY_NAMESPACE=$MY_POSTGRESQL_NAMESPACE
    #envsubst <"${MY_RESOURCESDIR}namespace.yaml" | oc apply -f - || exit 1
    create_namespace $MY_POSTGRESQL_NAMESPACE

    # Create a PostGreSQL DB secret
    local lf_type="Secret"
    local lf_cr_name="${MY_POSTGRESQL_SECRET}"
    local lf_namespace=$MY_POSTGRESQL_NAMESPACE
    #local lf_secret_type="Opaque"
    local lf_username=${MY_POSTGRESQL_USER}
    local lf_password=${MY_POSTGRESQL_PASSWORD}
    #local lf_username=$(echo -n "${MY_POSTGRESQL_USER}" | base64 -w0)
    #local lf_password=$(echo -n "${MY_POSTGRESQL_PASSWORD}" | base64 -w0)
    #local lf_yaml_file="${MY_RESOURCESDIR}secret.yaml"
    #check_create_secret "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    if oc -n ${lf_namespace} get ${lf_type} ${lf_cr_name} >/dev/null 2>&1; then
      mylog info "Custom Resource $lf_type/$lf_cr_name already exists"
    else
      oc -n $lf_namespace create secret generic $lf_cr_name --from-literal=username=$MY_POSTGRESQL_USER --from-literal=password=$MY_POSTGRESQL_PASSWORD
    fi

    # PostGreSQL DB
    local lf_type="Cluster"
    local lf_cr_name="${MY_POSTGRESQL_CLUSTER}"
    local lf_yaml_file="${MY_RESOURCESDIR}postgresql-cluster.yaml"
    local lf_namespace=$MY_POSTGRESQL_NAMESPACE
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    #local lf_resource=$(oc -n $lf_namespace get $lf_type -o json | jq -r --arg my_resource "$lf_cr_name" '.items[0].metadata | select (.name | contains ($my_resource)).name')
    local lf_resource=$(oc -n $lf_namespace get $lf_type -o jsonpath="{.items[0].metadata.name}")
    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    decho 3 "wait_for_state \"$lf_type $lf_resource is $lf_state\" \"$lf_state\" \"oc -n $lf_namespace get $lf_type $lf_resource -o jsonpath='$lf_path'\""
    wait_for_state "$lf_type $lf_resource $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_resource -o jsonpath='$lf_path'"

    # Authorize superuser access
    oc -n $lf_namespace patch $lf_type $lf_cr_name --type=merge -p '{"spec":{"enableSuperuserAccess":true}}'

    # Here after how to check the status of the PostGreSQL DB and connect to it
    # oc run pg-check --image=postgres:15 --restart=Never -- sleep 3600
    # oc exec -it pg-check -- bash
    # psql -h <postgresql_svc> -U <postgres_user> -d <database_name> // password is asked
    # \q to quit

  fi

  decho 3 "F:OUT:create_postgresql_db"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise ldap adding users and groups
function customise_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN:customise_openldap"

  if $MY_LDAP_CUSTOM; then
    mylog info "==== Customise ldap ()." 1>&2
    read_config_file "${MY_YAMLDIR}ldap/ldap.properties"
    check_file_exist ${MY_YAMLDIR}ldap/ldap-config.json
    check_file_exist ${MY_YAMLDIR}ldap/ldap-users.ldif
  fi

  decho 3 "F:OUT:customise_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Open Liberty
function customise_openliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_openliberty"

  # backend J2EE applications
  if $MY_OPENLIBERTY_CUSTOM; then
  mylog info "==== Customise Open Liberty (olp.config.sh)." 1>&2
    . ${MY_OPENLIBERTY_SCRIPTDIR}scripts/olp.config.sh
  fi

  decho 3 "F:OUT:customise_openliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise WebSphere Liberty
function customise_wasliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN:customise_wasliberty"

  if $MY_WASLIBERTY_CUSTOM; then
  mylog info "==== Customise WAS Liberty (was.config.sh)." 1>&2
    . ${MY_WASLIBERTY_SCRIPTDIR}scripts/was.config.sh
    fi

  decho 3 "F:OUT:customise_wasliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise ACE
function customise_ace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_ace"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_ACE_CUSTOM; then
    mylog info "==== Customise ACE (ace.config.sh)." 1>&2
    . ${MY_ACE_SCRIPTDIR}scripts/ace.config.sh
  fi

  decho 3 "F:OUT:customise_ace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise APIC
function customise_apic() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_apic"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_APIC_CUSTOM; then
    mylog info "==== Customise APIC (apic.config.sh)." 1>&2
    . ${MY_APIC_SCRIPTDIR}scripts/apic.config.sh
  fi

  decho 3 "F:OUT:customise_apic"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise IBM Event streams
function customise_es() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_es"

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
      mylog info "==== Customise Event Streams (es.config.sh)." 1>&2

    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    if [ ! -d ${MY_ES_GEN_CUSTOMDIR}scripts ]; then
      mkdir -p ${MY_ES_GEN_CUSTOMDIR}scripts
    fi
    if [ ! -d ${MY_ES_GEN_CUSTOMDIR}config ]; then
      mkdir -p ${MY_ES_GEN_CUSTOMDIR}config
    fi
    generate_files $MY_ES_SCRIPTDIR $MY_ES_GEN_CUSTOMDIR false

    # SB]20231211 https://ibm.github.io/event-automation/es/installing/installing/
    # Question : Do we have to create this configmap before installing ES or even after ? Used for monitoring
    lf_type="configmap"
    lf_cr_name="cluster-monitoring-config"
    lf_yaml_file="${MY_RESOURCESDIR}openshift-monitoring-cm.yaml"
    lf_namespace="openshift-monitoring"
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    . ${MY_ES_SCRIPTDIR}scripts/es.config.sh
  fi

  decho 3 "F:OUT:customise_es"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise EEM
function customise_eem() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_eem"

  if $MY_EEM_CUSTOM; then
    mylog info "==== Customise Event Endpoint Management (eem.config.sh)." 1>&2
    # launch custom script
      . ${MY_EEM_SCRIPTDIR}scripts/eem.config.sh
  fi

  decho 3 "F:OUT:customise_eem"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise EGW
function customise_egw() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_egw"

  if $MY_EGW_CUSTOM; then
    mylog info "==== Customise Event Endpoint Gateway ()." 1>&2
  fi

  decho 3 "F:OUT:customise_egw"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise EP
function customise_ep() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_ep"

  local lf_in_ns=$1
  local varb64

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  ## Creating Event Processing users and roles
  if $MY_EP_CUSTOM; then
    mylog info "==== Customise Event Endpoint Processing ()." 1>&2
    # launch custom script
  fi

  decho 3 "F:OUT:customise_ep"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Flink
function customise_flink() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_flink"

  local lf_in_ns=$1
  if $MY_FLINK_CUSTOM; then
    mylog info "==== Customise Flink ()." 1>&2
  fi

  decho 3 "F:OUT:customise_flink"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Aspera HSTS
function customise_hsts() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_hsts"

  # ibm aspera hsts
  if $MY_HSTS_CUSTOM; then
    mylog info "==== Customise HSTS ()." 1>&2
  fi

  decho 3 "F:OUT:customise_hsts"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise MQ
function customise_mq() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_mq"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_MQ_CUSTOM; then
 
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_MQ_VERSION" ]; then
      export MY_MQ_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_MQ_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # launch custom script
    mylog info "Customise MQ (mq.config.sh)."
    . ${MY_MQ_SCRIPTDIR}scripts/mq.config.sh -i ${sc_properties_file} ${sc_versions_file} ${MY_MQ_INSTANCE_NAME}
    mylog info "Customise MQ (mq.demo.config.sh)."
    . ${MY_MQ_SCRIPTDIR}scripts/mq.demo.config.sh -i ${sc_properties_file} ${sc_versions_file} ${MY_MQ_INSTANCE_NAME}

  fi

  decho 3 "F:OUT:customise_mq"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Customise Instana
function customise_instana() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_instana"

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA_CUSTOM; then
    mylog info "==== Customise Instana ()." 1>&2
  fi

  decho 3 "F:OUT:customise_instana"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Display information to access CP4I
function display_access_info() {
  # To start displaying access info from the start of the line
  #SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  SC_SPACES_COUNTER=0
  decho 3 "F:IN  :display_access_info"

  mylog info "==== Displaying Access Info to CP4I." 1>&2
  # Temporary access with Keycloack

  local lf_mailhog_hostname
  lf_mailhog_hostname=$(oc -n ${MY_MAIL_SERVER_NAMESPACE} get route mailhog -o jsonpath='{.spec.host}')
  mylog info "MailHog accessible at http://${lf_mailhog_hostname}"

  lf_keycloak_admin_ui=$(oc -n $MY_COMMONSERVICES_NAMESPACE get route keycloak --template='{{ .spec.host }}')
  mylog info "Keycloak admin UI URL: " $lf_keycloak_admin_ui
  lf_keycloak_admin_pwd=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret cs-keycloak-initial-admin -o jsonpath={.data.password} | base64 -d)
  mylog info "Keycloak admin password: " $lf_keycloak_admin_pwd
  
  local lf_temp_integration_admin_pwd cp4i_url
  if $MY_NAVIGATOR_INSTANCE; then
    lf_temp_integration_admin_pwd=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret integration-admin-initial-temporary-credentials -o jsonpath={.data.password} | base64 -d)
    mylog info "Integration admin password: ${lf_temp_integration_admin_pwd}"
    cp4i_url=$(oc -n $MY_OC_PROJECT get platformnavigator cp4i-navigator -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
    mylog info "CP4I Platform UI URL: " $cp4i_url  
  fi

  local lf_ace_ui_db_url lf_ace_ui_dg_url
  if $MY_ACE; then
    lf_ace_ui_db_url=$(oc -n $MY_OC_PROJECT get Dashboard -o=jsonpath='{.items[?(@.kind=="Dashboard")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Dahsboard UI endpoint: " $lf_ace_ui_db_url
    lf_ace_ui_dg_url=$(oc -n $MY_OC_PROJECT get DesignerAuthoring -o=jsonpath='{.items[?(@.kind=="DesignerAuthoring")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Designer UI endpoint: " $lf_ace_ui_dg_url
  fi

  local lf_gtw_url lf_apic_gtw_admin_pwd_secret_name lf_cm_admin_pwd lf_cm_url lf_cm_admin_pwd_secret_name lf_cm_admin_pwd lf_mgr_url lf_ptl_url lf_jwks_url
  if $MY_APIC; then
    lf_gtw_url=$(oc -n $MY_OC_PROJECT get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "APIC Gateway endpoint: ${lf_gtw_url}"
    lf_gtw_webconsole_url=$(oc -n $MY_OC_PROJECT get Route ${MY_APIC_INSTANCE_NAME}-gw-webconsole -o=jsonpath='{.spec.host}')
    mylog info "APIC Gateway web console endpoint: ${lf_gtw_webconsole_url}"
    lf_apic_gtw_admin_pwd_secret_name=$(oc -n $MY_OC_PROJECT get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].spec.adminUser.secretName}')
    lf_cm_admin_pwd=$(oc -n $MY_OC_PROJECT get secret ${lf_apic_gtw_admin_pwd_secret_name} -o jsonpath={.data.password} | base64 -d)
    mylog info "APIC Gateway admin password: ${lf_cm_admin_pwd}"
    lf_cm_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "APIC Cloud Manager endpoint: ${lf_cm_url}"
    lf_cm_admin_pwd_secret_name=$(oc -n $MY_OC_PROJECT get ManagementCluster -o=jsonpath='{.items[?(@.kind=="ManagementCluster")].spec.adminUser.secretName}')
    lf_cm_admin_pwd=$(oc -n $MY_OC_PROJECT get secret ${lf_cm_admin_pwd_secret_name} -o jsonpath='{.data.password}' | base64 -d)
    mylog info "APIC Cloud Manager admin password: ${lf_cm_admin_pwd}"
    lf_mgr_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "APIC API Manager endpoint: ${lf_mgr_url}"
    lf_ptl_url=$(oc -n $MY_OC_PROJECT get PortalCluster -o=jsonpath='{.items[?(@.kind=="PortalCluster")].status.endpoints[?(@.name=="portalWeb")].uri}')
    mylog info "APIC Web Portal root endpoint: ${lf_ptl_url}"
    lf_jwks_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="jwksUrl")].uri}')
    mylog info "APIC jwksUrl endpoint for EEM: ${lf_jwks_url}"
  fi

  local lf_es_ui_url lf_es_admin_url lf_es_apicurioregistry_url lf_es_restproducer_url lf_es_bootstrap_urls lf_es_admin_pwd
  if $MY_ES; then
    lf_es_ui_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Streams Management UI endpoint: ${lf_es_ui_url}"
    lf_es_admin_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "Event Streams Management admin endpoint: ${lf_es_admin_url}"
    lf_es_apicurioregistry_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="apicurioregistry")].uri}')
    mylog info "Event Streams Management apicurio registry endpoint: ${lf_es_apicurioregistry_url}"
    lf_es_restproducer_url=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="restproducer")].uri}')
    mylog info "Event Streams Management REST Producer endpoint: ${lf_es_restproducer_url}"
    lf_es_bootstrap_urls=$(oc -n $MY_OC_PROJECT get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.kafkaListeners[*].bootstrapServers}')
    mylog info "Event Streams Bootstraps servers endpoints: ${lf_es_bootstrap_urls}"
    lf_es_admin_pwd=$(oc -n $MY_OC_PROJECT get secret es-admin -o jsonpath={.data.password} | base64 -d)
    mylog info "Event Streams UI Credentials: es-admin/${lf_es_admin_pwd}"
  fi

  local lf_eem_ui_url lf_eem_lf_gtw_url
  if $MY_EEM; then
    lf_eem_ui_url=$(oc -n $MY_OC_PROJECT get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Endpoint Management UI endpoint: ${lf_eem_ui_url}"
    lf_eem_lf_gtw_url=$(oc -n $MY_OC_PROJECT get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "Event Endpoint Management Gateway endpoint: ${lf_eem_lf_gtw_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi

  local lf_ep_ui_url
  if $MY_EP; then
    lf_ep_ui_url=$(oc -n $MY_OC_PROJECT get EventProcessing -o=jsonpath='{.items[?(@.kind=="EventProcessing")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Processing UI endpoint: ${lf_ep_ui_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi
  
  local lf_ldap_hostname lf_ldap_port
  if $MY_LDAP; then
    read_config_file "${MY_YAMLDIR}ldap/ldap.properties"
    lf_ldap_hostname=$(oc -n ${MY_LDAP_NAMESPACE} get route openldap-external -o jsonpath='{.spec.host}')
    lf_ldap_port=$(oc -n ${MY_LDAP_NAMESPACE} get route openldap-external -o jsonpath='{.spec.port.targetPort}')
    mylog info "LDAP hostname:port: ${lf_ldap_hostname}:${lf_ldap_port}"
    mylog info "LDAP admin dn/password: ${ldap_admin_dn}/${ldap_admin_password}"
  fi

  local lf_ar_ui_url
  if $MY_ASSETREPO; then
    lf_ar_ui_url=$(oc -n $MY_OC_PROJECT get AssetRepository -o=jsonpath='{.items[?(@.kind=="AssetRepository")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Asset Repository UI endpoint: ${lf_ar_ui_url}"
  fi

  if $MY_DPGW; then
    mylog info "Datapower Gateway UI endpoint/admin password are the same as : APIC Gateway endpoint/APIC Gateway admin password"
  fi

  local lf_mq_admin_url
  if $MY_MQ; then
    if $MY_MESSAGINGSERVER; then
      lf_mq_qm_url=$(oc -n $MY_OC_PROJECT get MessagingServer $MY_MSGSRV_INSTANCE_NAME -o jsonpath='{.status.adminUiUrl}')
    fi
    lf_mq_admin_url=$(oc -n $MY_OC_PROJECT get QueueManager $MY_MQ_INSTANCE_NAME -o jsonpath='{.status.adminUiUrl}')
    mylog info "MQ Management Console : ${lf_mq_admin_url}"
  fi

  local lf_was_liberty_app_demo_url
  if $MY_WASLIBERTY_CUSTOM; then
    lf_was_liberty_app_demo_url=$(oc -n $MY_BACKEND_NAMESPACE get route demo -o jsonpath='{.status.ingress[0].host}')
    mylog info "WAS Liberty $MY_WLA_APP_NAME application URL : https://${lf_was_liberty_app_demo_url}/$MY_WLA_APP_NAME"
  fi

  local lf_licensing_service_url lf_licensing_secret_token lf_licensing_service_reporter_url lf_licensing_reporter_password
  if $MY_LIC_SRV; then
    lf_licensing_service_url=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-licensing-service-instance")].spec.host}')
    mylog info "Licensing service endpoint: https://${lf_licensing_service_url}"
    lf_licensing_secret_token=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get secret ibm-licensing-token -o jsonpath='{.data.token}' | base64 -d)
    mylog info "Licensing service token: ${lf_licensing_secret_token}"
    lf_licensing_service_reporter_url=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get Route ibm-lsr-console -o=jsonpath='{.status.ingress[0].host}')
    mylog info "Licensing service reporter console endpoint: https://${lf_licensing_service_reporter_url}/license-service-reporter/"
    lf_licensing_reporter_password=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get secret ibm-license-service-reporter-credentials -o jsonpath='{.data.password}' | base64 -d)
    mylog info "Licensing service reporter credential: license-administrator/${lf_licensing_reporter_password}"
  fi

  decho 3 "F:OUT:display_access_info"
  #SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Quic Start Logging 
function quick_start_logging() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :quick_start_logging"

  # SB]20241202  test logging using loki
  # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/logging/index#quick-start
  # Pre requisite : call this functio after the function install_loggig_loki

  mylog info "call this function after the function install_logging_loki"
  install_cluster_observability
  install_logging_viaq

  decho 3 "F:OUT:quick_start_logging"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# function for the installtion of needed resources
# namespaces, operatorgroup, entitlement, ...
################################################
function install_needed_resources_part() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_needed_resources_part"

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
    oc -n $MY_OC_PROJECT adm policy add-cluster-role-to-user self-provisioner $MY_USER_ID
  fi
  
  # https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=operators-installing-by-using-cli
  # (Only if your preferred installation mode is a specific namespace on the cluster) Create an OperatorGroup
  # We decided to install in openshift-operators so no need to OperatorGroup !
  # TODO # nommer correctement les operatorgroup
  create_namespace $MY_OC_PROJECT
  create_namespace $MY_COMMONSERVICES_NAMESPACE
  
  create_namespace $MY_CERTMANAGER_OPERATOR_NAMESPACE
  local lf_type="OperatorGroup"
  local lf_cr_name="${MY_CERTMANAGER_OPERATORGROUP}"
  local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
  local lf_namespace=$MY_CERTMANAGER_OPERATOR_NAMESPACE
  export MY_OPERATORGROUP="${MY_CERTMANAGER_OPERATORGROUP}"
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  
  create_namespace $MY_LICENSE_SERVER_NAMESPACE
  local lf_type="OperatorGroup"
  local lf_cr_name="${MY_LICENSE_SERVER_OPERATORGROUP}"
  local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
  local lf_namespace=$MY_LICENSE_SERVER_NAMESPACE
  export MY_OPERATORGROUP="${MY_LICENSE_SERVER_OPERATORGROUP}"
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  
  # Add ibm entitlement key to namespace
  # SB]20230209 Aspera hsts service cannot be created because a problem with the entitlement, it must be added in the openshift-operators namespace.
  mylog info "Creating entitlement, need to check if it is needed or works"
  add_ibm_entitlement $MY_OC_PROJECT $MY_CONTAINER_ENGINE
  add_ibm_entitlement $MY_OPERATORS_NAMESPACE $MY_CONTAINER_ENGINE

  decho 3 "F:OUT:install_needed_resources_part"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# function for the installtion part of the script
################################################
function install_part() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :install_part"

  # Start by installing Redhat needed/useful features
  install_gitops
  install_cluster_observability
  install_logging_loki
  #quick_start_logging
  install_logging_viaq
  install_oadp
  install_pipelines
  
  #SB]20241121 install other useful tools
  install_mailhog
  install_openldap
  install_sftp
  
  #SB]20231214 Installing Foundation services
  #mylog info "==== Installing foundational services (Cert Manager, Licensing Server and Common Services)." 1>&2
  install_cert_manager
  
  install_lic_srv
  install_fs
  
  # install_xxx: For each capability install : case, operator, operand
  
  # install_openliberty
  
  install_wasliberty
  
  install_navigator
  
  install_assetrepo
  
  install_intassembly
  
  install_ace
  
  install_apic
  
  install_es
  
  install_eem $MY_CATALOGSOURCES_NAMESPACE
  install_egw
  
  create_keycloak_client
  install_ep $MY_CATALOGSOURCES_NAMESPACE
  install_flink $MY_CATALOGSOURCES_NAMESPACE
  
  install_hsts
  
  install_mq
  
  install_instana
  
  install_postgresql

  install_cluster_monitoring

  decho 3 "F:OUT:install_part"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# function for the customization part of the script
################################################
function customise_part() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :customise_part"

  customise_openldap
  
  # customise_openliberty
  
  customise_wasliberty
  
  customise_ace
  
  customise_apic
  
  customise_es
  
  customise_eem
  
  customise_egw
  
  customise_ep
  
  customise_flink
  
  customise_hsts
  
  customise_mq
  
  customise_instana

  decho 3 "F:OUT:customise_part"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

function mytest(){
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :mytest"

  echo "mytest"

  decho 3 "F:OUT:mytest"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# function to run the whole script
function run_all() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :run_all"

  # Start installation capabilities
  install_part
  
  # Start customization capabilities
  # No need to customise navigator, intassembly, assetrepo
  customise_part

  decho 3 "F:OUT:run_all"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Function to process calls
function process_calls() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :process_calls"

  local lf_calls="$1"  # Get the full string of calls and parameters
  local lf_commands    # Array to store the commands
  local lf_cmd         # Command to process
  local lf_func        # Function name
  local lf_params      # Parameters
  local lf_list        # List of available functions

    # Split the calls by comma and loop through each
    IFS=',' read -ra lf_commands <<< "$lf_calls"
    for lf_cmd in "${lf_commands[@]}"; do
      # Trim leading/trailing spaces from the command
      lf_cmd=$(echo "$lf_cmd" | xargs)
      decho 3 "Command: $lf_cmd"

      # Extract the function name and parameters
      lf_func=$(echo "$lf_cmd" | awk '{print $1}')
      lf_params=$(echo "$lf_cmd" | cut -d' ' -f2-)  # Get all the parameters after the function name

      # Check if the function exists and call it
      if declare -f "$lf_func" > /dev/null; then
        if [ "$lf_func" = "main" ]; then
          mylog error "Function 'main' cannot be called."
          return 1
        fi
        #install_needed_resources_part
        $lf_func $lf_params
      else
        mylog error "Function '$lf_func' not found."
        lf_list=$(grep -E '^\s*(function\s+\w+|\w+\s*\(\))' $(basename "$0") | sed -E 's/^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\2/')
        mylog error "Available functions are:"
        mylog error "$lf_list"
        return 1
      fi
    done

  decho 3 "F:OUT:process_calls"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# main function
# SB]20241220 : this script is idempotent and with Arnauld we have run it many times using comments 
#               to avoid the execution of some parts of the script.
#               Sometimes also we have run it just to execute one function. 
#               So that's why we added the following section to have the choice between executing 
#               the whole script or execute one to many functions
# Main logic
function main() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :main"

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    return 1
  fi

  # Main script logic
  local lf_calls=""  # Initialize calls variable
  local lf_key

  while [[ $# -gt 0 ]]; do
    lf_key="$1"
    decho 3 "Key: $lf_key"
    case $lf_key in
      --all)
        install_needed_resources_part
        run_all
        ;;
      --call)
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          lf_calls+="$1 "  # Accumulate all arguments after --call
          shift
        done
        ;;
      *)
        mylog error "Invalid option '$1'. Use --all or --call function_name parameters, function_name parameters, ...."
        return 1
        ;;
      esac
  done
  lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces

  # Call processing function if --call was used
  if [[ -n $lf_calls ]]; then
    process_calls "$lf_calls"
  else
    mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
    return 1
  fi

  decho 3 "F:OUT:main"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
  
  exit 0
}

################################################################################################
# Start of the script main entry
################################################################################################
# other example: ./provision_cluster-v2.sh --all
# other example: ./provision_cluster-v2.sh --call <function_name>

#
export ADEBUG=1
export TECHZONE=true
export TRACELEVEL=4

# SB]20240404 Global Index sequence for incremental output for each function call
export SC_SPACES_COUNTER=0
export SC_SPACES_INCR=3

sc_parameters=./script-parameters.properties
sc_properties_file=./cp4i.properties
sc_versions_file=./versions/versions.properties
sc_user_file="./private/user.properties"
sc_lib_file=./lib.sh

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
# MAINSCRIPTDIR=$(dirname "$0")/
MAINSCRIPTDIR=${PWD}/

# toto trap 'display_access_info' EXIT
# load helper functions
. ${sc_lib_file}

# Read user file properties
read_config_file "$sc_user_file"

# Read all the properties
read_config_file "$sc_parameters"

# Read all the properties
read_config_file "$sc_properties_file"

# Read versions properties
read_config_file "$sc_versions_file"

# check the differents pre requisites
check_exec_prereqs

check_directory_exist_create "$MY_WORKINGDIR"

: <<'END_COMMENT'
END_COMMENT

######################################################
# main entry
######################################################
main "$@"
