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
# Install SFTP server, it is usefull for example for backups
function install_sftp() {
  SECONDS=0
  local lf_starting_date=$(date)  
  mylog info "==== Installing SFTP server (${FUNCNAME[0]}) [started : $lf_starting_date]." 0 

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_sftp

  decho $lf_tracelevel "Parameters: |no parameters|"
  
  if $MY_SFTP; then
    check_directory_exist_create "${MY_SFTP_WORKINGDIR}"
  
    create_project "${VAR_SFTP_SERVER_NAMESPACE}" "${VAR_SFTP_SERVER_NAMESPACE} project" "For SFTP server" "${MY_RESOURCESDIR}" "${MY_SFTP_WORKINGDIR}"
  
    # Create secret with users
    mylog check "Checking Secret for credential ${VAR_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" 1>&2
    if ! $MY_CLUSTER_COMMAND -n ${VAR_SFTP_SERVER_NAMESPACE} get secret "${VAR_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" >/dev/null 2>&1; then
      generate_password 32
      adapt_file ${MY_SFTP_SCRIPTDIR}resources/ ${MY_SFTP_WORKINGDIR}resources/ users.conf
      unset USER_PASSWORD_GEN
      $MY_CLUSTER_COMMAND -n $VAR_SFTP_SERVER_NAMESPACE create secret generic "${VAR_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" --from-file=${MY_SFTP_WORKINGDIR}resources/users.conf
    fi
  
    # Create configmap with SSH keys
    mylog check "Checking ConfigMap for ssh keys ${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm" 1>&2
    if ! $MY_CLUSTER_COMMAND -n ${VAR_SFTP_SERVER_NAMESPACE} get configmap "${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm" >/dev/null 2>&1; then
      ssh-keygen -t ed25519 -f ${MY_SFTP_WORKINGDIR}resources/ssh_host_ed25519_key < /dev/null
      ssh-keygen -t rsa -b 4096 -f ${MY_SFTP_WORKINGDIR}resources/ssh_host_rsa_key < /dev/null
      adapt_file ${MY_SFTP_SCRIPTDIR}resources/ ${MY_SFTP_WORKINGDIR}resources/ sshd_config
      local lf_apply_cmd="$MY_CLUSTER_COMMAND -n $VAR_SFTP_SERVER_NAMESPACE create configmap ${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_ed25519_key \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_ed25519_key.pub \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_rsa_key \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_rsa_key.pub \
        --from-file=${MY_SFTP_WORKINGDIR}resources/sshd_config"

      $MY_CLUSTER_COMMAND -n $VAR_SFTP_SERVER_NAMESPACE create configmap ${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_ed25519_key \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_ed25519_key.pub \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_rsa_key \
        --from-file=${MY_SFTP_WORKINGDIR}resources/ssh_host_rsa_key.pub \
        --from-file=${MY_SFTP_WORKINGDIR}resources/sshd_config
    fi
  
    # Check security context constraint
    mylog check "Security Context Constraint anyuid" 1>&2
    if ! $MY_CLUSTER_COMMAND get SecurityContextConstraints anyuid >/dev/null 2>&1; then
      $MY_CLUSTER_COMMAND adm policy add-scc-to-user anyuid -z default
      wait 10
      
      $MY_CLUSTER_COMMAND patch scc anyuid --type=merge --patch '{"users": ["system:serviceaccount:sftp:default\n"]}'      
      $MY_CLUSTER_COMMAND patch scc anyuid --type=merge --patch '{"allowedCapabilities":["SYS_CHROOT\n"]}'
    fi
  
    ## Creation of sftp PVC
    # Even if it's a pvc we use the same generic function
    # Create PVC
    export VAR_PVC_NAME="${VAR_SFTP_SERVER_NAMESPACE}-sftp-pvc"
    export VAR_VAR_PVC_NAMEPVC_NAMESPACE=$VAR_SFTP_SERVER_NAMESPACE
    export VAR_PVC_STORAGE_CLASS=$MY_FILE_STORAGE_CLASS
    create_operand_instance "PersistentVolumeClaim" "${VAR_PVC_NAME}" "${MY_RESOURCESDIR}" "${MY_SFTP_WORKINGDIR}" "pvc.yaml" "$VAR_SFTP_SERVER_NAMESPACE" "{.status.phase}" "Bound"
    unset VAR_PVC_NAME VAR_PVC_NAME VAR_PVC_STORAGE_CLASS

    # Create deployment including the resources generated
    create_oc_resource "Deployment" "${VAR_SFTP_SERVER_NAMESPACE}-sftp-server" "${MY_SFTP_SCRIPTDIR}resources/" "${MY_SFTP_WORKINGDIR}resources/" "sftp_dep.yaml" "$VAR_SFTP_SERVER_NAMESPACE"
  
    # Create the service to expose the SFTP server
    create_oc_resource "Service" "${VAR_SFTP_SERVER_NAMESPACE}-sftp-service" "${MY_SFTP_SCRIPTDIR}resources/" "${MY_SFTP_WORKINGDIR}resources/" "sftp_svc.yaml" "$VAR_SFTP_SERVER_NAMESPACE"

    # Create the route to expose the SFTP server
    create_oc_resource "Route" "${VAR_SFTP_SERVER_NAMESPACE}-sftp-route" "${MY_SFTP_SCRIPTDIR}resources/" "${MY_SFTP_WORKINGDIR}resources/" "sftp_route.yaml" "$VAR_SFTP_SERVER_NAMESPACE"
  fi

  trace_out $lf_tracelevel install_sftp

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of SFTP server (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# https://docs.openshift.com/gitops/1.16/installing_gitops/installing-openshift-gitops.html
# Install GitOps
function install_gitops() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Redhat Openshift GitOps (${FUNCNAME[0]}) [started : $lf_starting_date]." 0 

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_gitops

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_GITOPS; then
    check_directory_exist_create "${MY_GITOPS_WORKINGDIR}"

    create_project "$MY_GITOPS_NAMESPACE" "${MY_GITOPS_NAMESPACE} project" "For OpenShift Gitops" "${MY_RESOURCESDIR}" "${MY_GITOPS_WORKINGDIR}"

    create_oc_resource "OperatorGroup" "$MY_GITOPS_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_GITOPS_WORKINGDIR" "operator-group-gitops.yaml" "$MY_GITOPS_NAMESPACE"

    # Create a subscription object for Gitops operator
    create_operator_instance "${MY_GITOPS_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_GITOPS_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
  fi

  trace_out $lf_tracelevel install_gitops

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Redhat Openshift GitOps (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  
}

###############################################
# Install CP4I Cluster Logging : Loki log store
# use Openshift Logging
# https://docs.openshift.com/container-platform/4.16/observability/logging/cluster-logging-deploying.html#logging-loki-cli-install_cluster-logging-deploying
function install_logging_loki() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Cluster Logging : Loki log store (${FUNCNAME[0]}) [started : $lf_starting_date]." 0 

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_logging_loki

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Openshift Logging
  if $MY_LOGGING_LOKI; then
    check_directory_exist_create "${MY_LOKI_WORKINGDIR}"

    # Create a namespace object for Loki Operator
    create_project "${MY_LOKI_NAMESPACE}" "${MY_LOKI_NAMESPACE} project" "For Redhat Logging Loki" "${MY_RESOURCESDIR}" "${MY_LOKI_WORKINGDIR}"

    # Operator group for Loki in all namespaces
    create_oc_resource "OperatorGroup" "$MY_LOKI_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_LOKI_WORKINGDIR" "operator-group-all.yaml" "${MY_RH_COMMON_OPERATORS_NAMESPACE}"

    # Create a subscription object for Loki Operator (because there are two loki-operator : community and Redhat, so the command to get the chl is different) 
    create_operator_instance "${MY_LOKI_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_LOKI_WORKINGDIR}" "${MY_RH_COMMON_OPERATORS_NAMESPACE}"

    # Create an OperatorGroup object for Red Hat Openhsift Logging Operator
    create_oc_resource "OperatorGroup" "$MY_LOGGING_OPERATOR" "${MY_RESOURCESDIR}" "${MY_LOKI_WORKINGDIR}" "operator-group-single.yaml" "$MY_LOGGING_NAMESPACE"
    
    # Create a subscription object for Red Hat Openshift Logging Operator
    create_operator_instance "${MY_LOGGING_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_LOKI_WORKINGDIR}" "${MY_LOGGING_NAMESPACE}"

    # create an ObjectBucketClaim in openshift-logging namespace
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/installing-log-storage.html#logging-loki-storage-odf_installing-log-storage
    create_oc_resource "ObjectBucketClaim" "$MY_LOKI_BUCKET_INSTANCE_NAME" "${MY_RESOURCESDIR}" "${MY_LOKI_WORKINGDIR}" "objectbucketclaim.yaml" "$MY_LOGGING_NAMESPACE"

    # get the needed parameters to create the object storage secret
    export VAR_LOKI_ACCESS_KEY_ID=$($MY_CLUSTER_COMMAND -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.AccessKey}'| base64 --decode)
    export VAR_LOKI_ACCESS_KEY_SECRET=$($MY_CLUSTER_COMMAND -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.SecretKey}'| base64 --decode)
    export VAR_LOKI_ENDPOINT=$($MY_CLUSTER_COMMAND -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.Endpoint}'| base64 --decode)
    decho $lf_tracelevel "VAR_LOKI_ACCESS_KEY_ID=$VAR_LOKI_ACCESS_KEY_ID|VAR_LOKI_ACCESS_KEY_SECRET=$VAR_LOKI_ACCESS_KEY_SECRET|VAR_LOKI_ENDPOINT=$VAR_LOKI_ENDPOINT"

    create_oc_resource "Secret" "$MY_LOKI_SECRET" "${MY_RESOURCESDIR}" "${MY_LOKI_WORKINGDIR}" "loki-secret.yaml" "$MY_LOGGING_NAMESPACE"
    unset VAR_LOKI_ACCESS_KEY_ID VAR_LOKI_ACCESS_KEY_SECRET VAR_LOKI_ENDPOINT

    # Create a LokiStack instance
    create_operand_instance "LokiStack" "$MY_LOKI_INSTANCE_NAME" "${MY_OPERANDSDIR}" "${MY_LOKI_WORKINGDIR}" "Loki-Capability.yaml" "$MY_LOGGING_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    # SB]20241204 Configuring LokiStack log store
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/cluster-logging-loki.html

    # Create a new group for the cluster-admin user role and add user to the group
    $MY_CLUSTER_COMMAND adm groups new cluster-admin $MY_USER_EMAIL

    # add the cluster-admin user role to the cluster-admin group
    $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-group cluster-admin cluster-admin
    
    # Create a ClusterLogging CR object
    # https://github.com/openshift/cluster-logging-operator/blob/master/docs/administration/upgrade/v6.0_changes.adoc#the-main-change-highlights-are
    #Two 'logging' resources:
    #5.x
    #
    #apiVersion: logging.openshift.io/v1
    #kind: ClusterLogging
    #...
    #apiVersion: logging.openshift.io/v1
    #kind: ClusterLogForwarder
    #...
    #Replaced by a single custom 'observability' resource:
    #6.0
    #
    #apiVersion: observability.openshift.io/v1
    #kind: ClusterLogForwarder
    #...
    # Create a service account for the collector
    $MY_CLUSTER_COMMAND -n $MY_LOGGING_NAMESPACE create sa $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to write data to the LokiStack CR
    $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA 

    # Allow the collector’s service account to collect logs
    #$MY_CLUSTER_COMMAND project $MY_LOGGING_NAMESPACE

    $MY_CLUSTER_COMMAND -n $MY_LOGGING_NAMESPACE adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    $MY_CLUSTER_COMMAND -n $MY_LOGGING_NAMESPACE adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA
    $MY_CLUSTER_COMMAND -n $MY_LOGGING_NAMESPACE adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA

    create_operand_instance "ClusterLogForwarder" "$MY_RHOL_INSTANCE_NAME" "${MY_OPERANDSDIR}" "${MY_LOKI_WORKINGDIR}" "Rhol-Loki-Capability.yaml" "$MY_LOGGING_NAMESPACE" "{.status.conditions[?(@.type==\"Ready\")].status}" "True"
    
    # Create a UIPlugin CR to enable the Log section in the Observe tab
    create_oc_resource "UIPlugin" "logging" "${MY_RESOURCESDIR}" "${MY_LOKI_WORKINGDIR}" "uiplugin.yaml" "$MY_LOGGING_NAMESPACE"

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
  fi
  
  trace_out $lf_tracelevel install_logging_loki

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Cluster Logging : Loki log store (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

###############################################
# Install Redhat Cluster Observability Operator
# # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview
# SB]20250116 TODO : Revoir la configuration de l'observabilité du cluster à la lumière de la documentation ci-dessus.
function install_cluster_observability() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Cluster Observability (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_cluster_observability

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Openshift Observability
  if $MY_COO; then
    check_directory_exist_create "${MY_COO_WORKINGDIR}"

    if $MY_APPLY_FLAG; then 
      # Create a service account for the collector
      create_oc_resource "ServiceAccount" "$MY_LOGGING_COLLECTOR_SA" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "serviceaccount.yaml" "$MY_LOGGING_NAMESPACE"

      # Create a ClusterRole for the collector
      create_oc_resource "ClusterRole" "logging-collector-logs-writer" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "collector_ClusterRole.yaml" "$MY_LOGGING_NAMESPACE"

      # Bind the ClusterRole to the service account
      $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA
    fi

    # SB]20241203 https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/logging/logging-6-0#cluster-role-binding-for-your-service-account
    # Create a ClusterRoleBinding for the service account
    create_oc_resource "ClusterRoleBinding" "manager-rolebinding" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "role_binding.yaml" "$MY_LOGGING_NAMESPACE"

    # Install the Cluster Observability Operator
    # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview

    # Create a subscription object for Cluster Observability Operator
    # Create a subscription object for Loki Operator (because there are two loki-operator : community and Redhat, so the command to get the chl is different) 
    create_operator_instance "${MY_COO_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_COO_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
  fi
    
  trace_out $lf_tracelevel install_cluster_observability
    
  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Cluster Observability (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

###############################################
# Install Logging OpenTelemetry
# https://docs.openshift.com/container-platform/4.16/observability/logging/logging-6.1/log6x-about-6.1.html
# Pre requisite : Install the Red Hat OpenShift Logging Operator, Loki Operator, and Cluster Observability Operator (COO)
function install_logging_otel() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel install_logging_otel

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Openshift Observability
  if $MY_COO; then

    check_directory_exist_create "${MY_COO_WORKINGDIR}"

    # Create a service account for the collector
    $MY_CLUSTER_COMMAND -n $MY_LOGGING_NAMESPACE create sa $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to write data to the LokiStack CR
    $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to collect logs
    $MY_CLUSTER_COMMAND project $MY_LOGGING_NAMESPACE

    $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA
    $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA

    # Create a UIPlugin CR to enable the Log section in the Observe tab
    create_oc_resource "UIPlugin" "logging" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "uiplugin.yaml" "$MY_LOGGING_NAMESPACE"

    # Create a ClusterLogForwarder CR to configure log forwarding
    create_oc_resource "ClusterLogForwarder" "${MY_LOGGING_COLLECTOR_SA}" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "clusterlogforwarder-otel.yaml" "$MY_LOGGING_NAMESPACE"

    # Bind the ClusterRole to the service account
    $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

  fi

  trace_out $lf_tracelevel install_logging_otel
}


###############################################
# Install/Configure Redhat Cluster Monitoring
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/index
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/common-monitoring-configuration-scenarios#configuring-core-platform-monitoring-postinstallation-steps_common-monitoring-configuration-scenarios
# 
function install_cluster_monitoring() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Redhat Cluster Monitoring (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_cluster_monitoring

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Openshift cluster monitoring
  if $MY_CLUSTER_MONITORING; then
    check_directory_exist_create "${MY_OPENSHIFT_MONITORING_WORKINGDIR}"

    create_project "${MY_OPENSHIFT_MONITORING_NAMESPACE}" "${MY_OPENSHIFT_MONITORING_NAMESPACE} project" "For Openshift monitoring" "${MY_RESOURCESDIR}" "${MY_OPENSHIFT_MONITORING_WORKINGDIR}"

    create_oc_resource "ConfigMap" "${MY_MONITORING_CM_NAME}" "${MY_RESOURCESDIR}" "${MY_OPENSHIFT_MONITORING_WORKINGDIR}" "openshift-monitoring-cm.yaml" "${MY_OPENSHIFT_MONITORING_NAMESPACE}"

    # Granting users permissions for core platform monitoring
  fi

  trace_out $lf_tracelevel install_cluster_monitoring

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Redhat Cluster Monitoring (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

##################################################
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/backup_and_restore/oadp-application-backup-and-restore#installing-and-configuring-oadp
# Install OADP (OpenShift API for Data Protection)
function install_oadp() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Redhat Openshift OADP (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_oadp

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_OADP; then
    check_directory_exist_create "${MY_OADP_WORKINGDIR}"

    create_project "$MY_OADP_NAMESPACE" "${MY_OADP_NAMESPACE} project" "For OpenShift API for Data Protection" "${MY_RESOURCESDIR}" "${MY_OADP_WORKINGDIR}"

    create_oc_resource "OperatorGroup" "$MY_OADP_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_OADP_WORKINGDIR" "operator-group-single.yaml" "$MY_OADP_NAMESPACE"

    # Create a subscription object for OADP Operator
    create_operator_instance "${MY_OADP_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_OADP_WORKINGDIR}" "${MY_OADP_NAMESPACE}"
  fi

  trace_out $lf_tracelevel install_oadp

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Redhat Openshift OADP (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install redhat Pipelines (tekton)
# https://docs.openshift.com/pipelines/1.14/install_config/installing-pipelines.html
# https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.18/html/installing_and_configuring/installing-pipelines
function install_pipelines() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Redhat Openshift Pipelines (tekton) (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_pipelines

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_TEKTON; then
    check_directory_exist_create "${MY_PIPELINES_WORKINGDIR}"

    # Create a subscription object for pipelines Operator
    create_operator_instance "${MY_PIPELINES_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_PIPELINES_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
  fi
  
  trace_out $lf_tracelevel install_pipelines

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Redhat Openshift Pipelines (tekton) (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Add mailhog app to openshift
# Port is hard coded to 8025 and is defined by mailhog (default port)
function install_mail() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Mailhog (server and client) (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_mail

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_MAILHOG; then
    check_directory_exist_create "${MY_MAIL_WORKINGDIR}"

    create_project "${VAR_MAIL_NAMESPACE}" "${VAR_MAIL_NAMESPACE} project" "For Mailhog fake SMTP server" "${MY_RESOURCESDIR}" "${MY_MAIL_WORKINGDIR}"

    create_oc_resource "Deployment" "${MY_MAIL_DEPLOYMENT}" "${MY_YAMLDIR}mail/" "${MY_MAIL_WORKINGDIR}" "mail_deployment.yaml" "$VAR_MAIL_NAMESPACE"

    create_oc_resource "Service" "${VAR_MAIL_SERVICE}" "${MY_YAMLDIR}mail/" "${MY_MAIL_WORKINGDIR}" "mail_svc.yaml" "${VAR_MAIL_NAMESPACE}"

    create_oc_resource "Route" "${VAR_MAIL_ROUTE}" "${MY_YAMLDIR}mail/" "${MY_MAIL_WORKINGDIR}" "mail_route.yaml" "${VAR_MAIL_NAMESPACE}"

    # expose service externaly and get host and port
    #$MY_CLUSTER_COMMAND -n ${VAR_MAIL_NAMESPACE} get service ${VAR_MAIL_SERVICE} -o json | \
    #   jq '.spec.ports |= map(if .name == "1025-tcp" then . + { "nodePort": 31025 } else . end)' | \
    #   jq '.spec.ports |= map(if .name == "8025-tcp" then . + { "nodePort": 38025 } else . end)' >${MY_MAIL_WORKINGDIR}mail-service.json
    export VAR_MAIL_HOSTNAME=$($MY_CLUSTER_COMMAND -n ${VAR_MAIL_NAMESPACE} get route ${VAR_MAIL_ROUTE} -o jsonpath='{.spec.host}')
  fi

  trace_out $lf_tracelevel install_mail

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Mailhog (server and client) (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Add OpenLdap app to openshift
function install_openldap() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing OpenLdap (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_openldap

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_LDAP; then
    check_directory_exist_create "${MY_LDAP_WORKINGDIR}"

    create_project "${VAR_LDAP_NAMESPACE}" "${VAR_LDAP_NAMESPACE} project" "For OpenLDAP" "${MY_RESOURCESDIR}" "${MY_LDAP_WORKINGDIR}"

    provision_persistence_openldap

    create_oc_resource "ServiceAccount" "$MY_LDAP_SERVICEACCOUNT" "${MY_RESOURCESDIR}" "${MY_LDAP_WORKINGDIR}" "serviceaccount.yaml" "$VAR_LDAP_NAMESPACE"
    #SB# $MY_CLUSTER_COMMAND adm policy add-scc-to-user privileged system:serviceaccount:${VAR_LDAP_NAMESPACE}:${MY_LDAP_SERVICEACCOUNT}
    #SB# $MY_CLUSTER_COMMAND adm policy add-scc-to-user anyuid system:serviceaccount:${VAR_LDAP_NAMESPACE}:${MY_LDAP_SERVICEACCOUNT}
    #$MY_CLUSTER_COMMAND adm policy add-scc-to-group anyuid system:serviceaccounts:${VAR_LDAP_NAMESPACE}

    #create_oc_resource "Deployment" "${MY_LDAP_DEPLOYMENT}" "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_deployment.yaml" "$VAR_LDAP_NAMESPACE"
    create_oc_resource "Deployment" "${MY_LDAP_DEPLOYMENT}" "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_deployment_k8s.yaml" "$VAR_LDAP_NAMESPACE"

    read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
    adapt_file "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_config.json" 
    $MY_CLUSTER_COMMAND -n ${VAR_LDAP_NAMESPACE} patch deployment.apps/${MY_LDAP_DEPLOYMENT} --patch-file "${MY_LDAP_WORKINGDIR}ldap_config.json"

    # Create the service to expose the openldap server
    create_oc_resource "Service" "${VAR_LDAP_SERVICE}" "${MY_YAMLDIR}ldap/" "${MY_LDAP_WORKINGDIR}" "ldap_svc.yaml" "${VAR_LDAP_NAMESPACE}"
    
    case $MY_CLUSTER_COMMAND in
    kubectl)  create_openldap_route_k8s;;
    oc) create_openldap_route ;;
    esac

  fi

  trace_out $lf_tracelevel install_openldap

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of OpenLdap (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0

}

################################################
# Install Cert Manager
# 20250505 https://cert-manager.io/docs/installation/kubectl/
# 20250110 https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.1.1?topic=operators-installing-by-using-cli#before-you-begin__title__1
# The API management, Event Manager, and Event Processing instances require you to install an appropriate certificate manager.
# Follow the instructions in : 
# https://docs.openshift.com/container-platform/4.16/security/cert_manager_operator/cert-manager-operator-install.html
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift#cert-manager-install-cli_cert-manager-operator-install
# to fulfill this requirement.
function install_cert_manager() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Cert Manager (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_cert_manager

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_CERTMANAGER; then
    check_directory_exist_create "${MY_CERTMANAGER_WORKINGDIR}"
    
    create_project "$MY_CERTMANAGER_OPERATOR_NAMESPACE" "${MY_CERTMANAGER_OPERATOR_NAMESPACE} project" "For Cert Manager" "${MY_RESOURCESDIR}" "${MY_CERTMANAGER_WORKINGDIR}"
    
    # Create a subscription object for cert manager Operator
    $MY_CLUSTER_COMMAND apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
  fi

  trace_out $lf_tracelevel install_cert_manager

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Cert Manager (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install Licensing Server
# 2025010 https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-license-openshift-container-platform
#
function install_lic_svc() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing IBM License Server (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_lic_svc

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm-license-server
  if $MY_LIC_SRV; then
    check_directory_exist_create "${MY_LICENSE_SERVICE_WORKINGDIR}"

    create_project "$MY_LICENSE_SERVICE_NAMESPACE"  "${MY_LICENSE_SERVICE_NAMESPACE} project" "For License Service" "${MY_RESOURCESDIR}" "${MY_LICENSE_SERVICE_WORKINGDIR}"

    check_add_cs_ibm_pak $MY_LICENSE_SERVICE_CASE $MY_LICENSE_SERVICE_OPERATOR $MY_LICENSE_SERVICE_CATALOGSOURCE_LABEL amd64 $MY_LICENSE_SERVICE_VERSION
    if [[ -z $MY_LICENSE_SERVICE_VERSION ]]; then
      export MY_LICENSE_SERVICE_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    create_oc_resource "OperatorGroup" "$MY_LICENSE_SERVICE_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_LICENSE_SERVICE_WORKINGDIR" "operator-group-single.yaml" "$MY_LICENSE_SERVICE_NAMESPACE"

    # Create a subscription object for license service Operator
    # The only case where for a Subscription we have to use "externally" the function wait_for_resource because the IBMLicensing instance name is not known before the subscription is created
    # and it uses a fixed name : instance.
    create_operator_instance "${MY_LICENSE_SERVICE_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_LICENSE_SERVICE_WORKINGDIR}" "${MY_LICENSE_SERVICE_NAMESPACE}"
    wait_for_resource "IBMLicensing" "$MY_LICENSE_SERVICE_INSTANCE_NAME" "$MY_LICENSE_SERVICE_NAMESPACE"
    
    # accept license
    accept_license_fs IBMLicensing $MY_LICENSE_SERVICE_INSTANCE_NAME $MY_LICENSE_SERVICE_NAMESPACE

    mylog info "Check if Installing network policies for license Service is needed" 1>&2
    #mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license"
    search_networkpolicies
    local lf_res=$?
    decho $lf_tracelevel "lf_res=$lf_res"
    if [[ $lf_res -eq 1 ]]; then
      mylog info "Please import and install network policies for License Service."
      mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license#installing-network-policies"
      mylog info "Download the two files and put them in $MY_RESOURCESDIR, then modify the namespace to use IBM License Service namespace"
      install_networkpolicies "lic_svc"
     else
      mylog info "Network policies for License Service not needed."
    fi
  fi

  trace_out $lf_tracelevel install_lic_svc

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of IBM License Server (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0

}

################################################
# Install Licensing Service Reporter
# 2025010 https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=repository-installing-license-service-reporter-cli
#
function install_lic_reporter_svc() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing IBM License Service Reporter (${FUNCNAME[0]}) [started : $lf_starting_date]." 0
  
  local lf_tracelevel=2
  trace_in $lf_tracelevel install_lic_reporter_svc

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm-license-server
  if $MY_LIC_SRV_REPORTER; then
    check_directory_exist_create "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}"

    create_project "$MY_LICENSE_SERVICE_REPORTER_NAMESPACE" "${MY_LICENSE_SERVICE_REPORTER_NAMESPACE} project" "For License Service Reporter" "${MY_RESOURCESDIR}" "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}"

    check_add_cs_ibm_pak $MY_LICENSE_SERVICE_REPORTER_CASE $MY_LICENSE_SERVICE_REPORTER_OPERATOR $MY_LICENSE_SERVICE_REPORTER_CATALOGSOURCE_LABEL amd64
    if [[ -z $MY_LICENSE_SERVICE_REPORTER_VERSION ]]; then
      export MY_LICENSE_SERVICE_REPORTER_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # check if the license service and license service reporter are in the same namespace, then only one operator group is needed
    if [[ $MY_LICENSE_SERVICE_NAMESPACE != $MY_LICENSE_SERVICE_REPORTER_NAMESPACE ]]; then
      mylog info "License Service and License Service Reporter are in different namespaces. Please check the documentation."
      mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=repository-installing-license-service-reporter-cli"
      create_oc_resource "OperatorGroup" "$MY_LICENSE_SERVICE_REPORTER_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_LICENSE_SERVICE_REPORTER_WORKINGDIR" "operator-group-single.yaml" "$MY_LICENSE_SERVICE_REPORTER_NAMESPACE"
    fi

    # Create a subscription object for license service reporter Operator
    create_operator_instance "${MY_LICENSE_SERVICE_REPORTER_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}" "${MY_LICENSE_SERVICE_REPORTER_NAMESPACE}"
      
    export MY_LICENSE_SERVICE_REPORTER_VERSION=$($MY_CLUSTER_COMMAND -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $MY_LICENSE_SERVICE_REPORTER_OPERATOR -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSVDesc.version')
    create_operand_instance "IBMLicenseServiceReporter" "$MY_LICENSE_SERVICE_REPORTER_INSTANCE_NAME" "${MY_OPERANDSDIR}" "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}" "LIC-Reporter-Capability.yaml" "$MY_LICENSE_SERVICE_REPORTER_NAMESPACE" "{.status.LicenseServiceReporterPods[-1].phase}" "Running"

    # Add license service to the reporter
    # $MY_CLUSTER_COMMAND get routes -n ibm-licensing | grep ibm-license-service-reporter | awk '{print $2}'
    mylog info "Add license service to the reporter" 1>&2
    decho $lf_tracelevel "$MY_CLUSTER_COMMAND -n ${MY_LICENSE_SERVICE_REPORTER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name==ibm-license-service-reporter)].spec.host}'"
    lf_licensing_service_reporter_url=$($MY_CLUSTER_COMMAND -n ${MY_LICENSE_SERVICE_REPORTER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-license-service-reporter")].spec.host}')
    decho $lf_tracelevel "License Service Reporter URL: $lf_licensing_service_reporter_url"
    $MY_CLUSTER_COMMAND -n $MY_LICENSE_SERVICE_NAMESPACE patch IBMLicensing ${MY_LICENSE_SERVICE_INSTANCE_NAME} --type merge --patch "{\"spec\":{\"sender\":{\"reporterSecretToken\":\"ibm-license-service-reporter-token\",\"reporterURL\":\"https://$lf_licensing_service_reporter_url/\",\"clusterID\":\"MyClusterTest1\",\"clusterName\":\"MyClusterTest1\"}}}"

    mylog info "Check if Installing network policies for license Service is needed" 1>&2
    #mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license"
    search_networkpolicies
    local lf_res=$?
    decho $lf_tracelevel "lf_res=$lf_res"
    if [[ $lf_res -eq 1 ]]; then
      mylog info "Please import and install network policies for License Service."
      mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license#installing-network-policies"
      mylog info "Download the two files and put them in $MY_RESOURCESDIR, then modify the namespace to use IBM License Service namespace"
      install_networkpolicies "lic_reporter"
    else
      mylog info "Network policies for License Service not needed."
    fi
  fi

  trace_out $lf_tracelevel install_lic_reporter_svc

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of IBM License Service Reporter (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

############################################################################################################################################
#SB]20231214 Installing Foundational services v4.3
# Referring to https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=whats-new-in-cloud-pak-integration-202341
# "The IBM Cloud Pak foundational services operator is no longer installed automatically.
#  Install this operator manually if you need to create an instance that uses identity and access management.
#  Also, make sure you have a certificate manager; otherwise, the IBM Cloud Pak foundational services operator installation will not complete."
# SB]20250109
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.1.1?topic=planning-structuring-your-deployment
# The IBM Cloud Pak foundational services in Cloud Pak for Integration enable functions such as Keycloak and EDB.
# 20250110 https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.1.1?topic=operators-installing-by-using-cli#before-you-begin__title__1
# It's stated clearly that : CP4I uses only the Keycloak installation that is installed by Cloud Pak foundational services.
############################################################################################################################################
function install_fs() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing IBM Common Services (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_fs

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_COMMONSERVICES; then
    check_directory_exist_create "${MY_COMMONSERVICES_WORKINGDIR}"

    create_project "$MY_COMMONSERVICES_NAMESPACE" "$MY_COMMONSERVICES_NAMESPACE project" "For the common services" "${MY_RESOURCESDIR}" "${MY_COMMONSERVICES_WORKINGDIR}"

    # ibm-cp-common-services
    check_add_cs_ibm_pak $MY_COMMONSERVICES_CASE $MY_COMMONSERVICES_OPERATOR $MY_COMMONSERVICES_CATALOGSOURCE_LABEL amd64 $MY_COMMONSERVICES_VERSION
    if [[ -z $MY_COMMONSERVICES_VERSION ]]; then
      export MY_COMMONSERVICES_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Create a subscription object for common services Operator
    create_operator_instance "${MY_COMMONSERVICES_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_COMMONSERVICES_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    ## Setting hardware  Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
    accept_license_fs CommonService $MY_COMMONSERVICES_INSTANCE_NAME $MY_OPERATORS_NAMESPACE

    # Configuring foundational services by using the CommonService custom resource.
    create_oc_resource "CommonService" "$MY_COMMONSERVICES_INSTANCE_NAME" "${MY_RESOURCESDIR}" "${MY_COMMONSERVICES_WORKINGDIR}" "foundational-services-cr.yaml" "$MY_OPERATORS_NAMESPACE"
  fi
    
  trace_out $lf_tracelevel install_fs

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of IBM Common Services (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}
 
################################################
# Install Open Liberty
function install_openliberty() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing OPEN Liberty (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_openliberty

  decho $lf_tracelevel "Parameters: |no parameters|"

  # backend J2EE applications
  if $MY_OPENLIBERTY; then
    check_directory_exist_create "${MY_OPENLIBERTY_WORKINGDIR}"

    create_project "$VAR_OPENLIBERTY_NAMESPACE" "$VAR_OPENLIBERTY_NAMESPACE project" "For Open Liberty" "${MY_RESOURCESDIR}" "${MY_OPENLIBERTY_WORKINGDIR}"

    # TODO other approach is to use the catalog which already inludes the Open Liberty operator and use a subscription
    # Case exists 1.3.1, and IBM/RedHat Catalog

    export OPEN_LIBERTY_OPERATOR_NAMESPACE=$VAR_OPENLIBERTY_NAMESPACE
    export OPEN_LIBERTY_OPERATOR_WATCH_NAMESPACE=$VAR_OPENLIBERTY_NAMESPACE

    # TODO Check that is this value
    export WATCH_NAMESPACE='""'
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}resources/ ${MY_OPENLIBERTY_WORKINGDIR}resources/ openliberty-app-rbac-watch-all.yaml
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}resources/ ${MY_OPENLIBERTY_WORKINGDIR}resources/ openliberty-app-crd.yaml
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}resources/ ${MY_OPENLIBERTY_WORKINGDIR}resources/ openliberty-app-operator.yaml

    # Creating Open Liberty operator subscription (Check arbitrarely one resource, the deployment of the operator)
    local lf_octype='deployment'
    local lf_name='olo-controller-manager'

    # check if deployment of the operator already performed
    mylog check "Checking ${lf_name}/${lf_octype} in ${VAR_OPENLIBERTY_NAMESPACE}"
    if ! $MY_CLUSTER_COMMAND -n ${VAR_OPENLIBERTY_NAMESPACE} get ${lf_octype} ${lf_name} >/dev/null 2>&1; then
      if $MY_APPLY_FLAG; then     
        $MY_CLUSTER_COMMAND apply --server-side -f ${MY_OPENLIBERTY_WORKINGDIR}resources/openliberty-app-crd.yaml
        $MY_CLUSTER_COMMAND apply -f ${MY_OPENLIBERTY_WORKINGDIR}resources/openliberty-app-rbac-watch-all.yaml
        $MY_CLUSTER_COMMAND -n ${VAR_OPENLIBERTY_NAMESPACE} apply -f ${MY_OPENLIBERTY_WORKINGDIR}resources/openliberty-app-operator.yaml
      fi
    fi
  fi

  trace_out $lf_tracelevel install_openliberty

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of OPEN Liberty (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install WebSphere Liberty
function install_wasliberty() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing WAS Liberty (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_wasliberty
  
  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_WASLIBERTY; then
    #check_directory_exist_create "${MY_WASLIBERTY_WORKINGDIR}"
    check_directory_exist_create "${MY_WASLIBERTY_WORKINGDIR}"

    create_project "$VAR_WASLIBERTY_NAMESPACE" "$VAR_WASLIBERTY_NAMESPACE project" "For WebSphere Liberty Application Server" "${MY_RESOURCESDIR}" "${MY_WASLIBERTY_WORKINGDIR}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_WASLIBERTY_CASE $MY_WASLIBERTY_OPERATOR $MY_WASLIBERTY_CATALOGSOURCE_LABEL amd64
    if [[ -z $MY_WASLIBERTY_VERSION ]]; then
      export MY_WASLIBERTY_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Operator group for WAS Liberty in single namespace
    create_oc_resource "OperatorGroup" "$MY_WASLIBERTY_OPERATORGROUP" "${MY_RESOURCESDIR}" "${MY_WASLIBERTY_WORKINGDIR}" "operator-group-single.yaml" "$VAR_WASLIBERTY_NAMESPACE"

    # Creating WebSphere Liberty operator subscription
    create_operator_instance "${MY_WASLIBERTY_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_WASLIBERTY_WORKINGDIR}" "${VAR_WASLIBERTY_NAMESPACE}"
  fi

  trace_out $lf_tracelevel install_wasliberty

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of WAS Liberty (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install Navigator (depending on two boolean)
function install_navigator() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I Navigator (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_navigator

  decho $lf_tracelevel "Parameters: |no parameters|"

  ## ibm-integration-platform-navigator
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  # Creating Navigator operator subscription
  if $MY_NAVIGATOR; then
    check_directory_exist_create "${MY_NAVIGATOR_WORKINGDIR}"

    create_project "$VAR_NAVIGATOR_NAMESPACE" "$VAR_NAVIGATOR_NAMESPACE project" "For CP4I Navigator (Platform UI)" "${MY_RESOURCESDIR}" "${MY_NAVIGATOR_WORKINGDIR}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_NAVIGATOR_CASE $MY_NAVIGATOR_OPERATOR $MY_NAVIGATOR_CATALOGSOURCE_LABEL amd64
    if [[ -z $MY_NAVIGATOR_VERSION ]]; then
      export MY_NAVIGATOR_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating Navigator operator subscription
    create_operator_instance "${MY_NAVIGATOR_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_NAVIGATOR_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"    
  fi

  if $MY_NAVIGATOR_INSTANCE; then
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [[ -z $MY_NAVIGATOR_VERSION ]]; then
      export MY_NAVIGATOR_VERSION=$($MY_CLUSTER_COMMAND ibm-pak list -o json | jq  --arg case "$MY_NAVIGATOR_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
      decho $lf_tracelevel "MY_NAVIGATOR_VERSION=$MY_NAVIGATOR_VERSION"
    fi

    # Creating Navigator instance
    create_operand_instance "PlatformNavigator" "${VAR_NAVIGATOR_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_NAVIGATOR_WORKINGDIR}" "Navigator-Capability.yaml" "$VAR_NAVIGATOR_NAMESPACE" "{.status.conditions[0].type}" "Ready"
  fi

  trace_out $lf_tracelevel install_navigator

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I Navigator (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install Asset Repository
function install_assetrepo() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I Asset Repository (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_assetrepo

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_ASSETREPO; then
    check_directory_exist_create "${MY_ASSETREPO_WORKINGDIR}"

    create_project "$VAR_ASSETREPO_NAMESPACE" "$VAR_ASSETREPO_NAMESPACE project" "For CP4I Asset Repository" "${MY_RESOURCESDIR}" "${MY_ASSETREPO_WORKINGDIR}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ASSETREPO_CASE $MY_ASSETREPO_OPERATOR $MY_ASSETREPO_CATALOGSOURCE_LABEL amd64
    if [[ -z $MY_ASSETREPO_VERSION ]]; then
      export MY_ASSETREPO_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating Asset Repository operator subscription
    create_operator_instance "${MY_ASSETREPO_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_ASSETREPO_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    if $MY_ASSETREPO_INSTANCE; then
      #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
      if [[ -z $MY_ASSETREPO_VERSION ]]; then
        export MY_ASSETREPO_VERSION=$($MY_CLUSTER_COMMAND ibm-pak list -o json | jq  --arg case "$MY_ASSETREPO_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
        decho $lf_tracelevel "MY_ASSETREPO_VERSION=$MY_ASSETREPO_VERSION"
      fi

      # Creating Asset Repository instance
      create_operand_instance "AssetRepository" "${VAR_ASSETREPO_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_ASSETREPO_WORKINGDIR}" "AR-Capability.yaml" "$VAR_ASSETREPO_NAMESPACE" "{.status.phase}" "Ready"
    fi
  fi

  trace_out $lf_tracelevel install_assetrepo

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I Asset Repository (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install Integration Assembly
function install_intassembly() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I Integration Assembly (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_intassembly

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Creating Integration Assembly instance
  if $MY_INTASSEMBLY; then
    check_directory_exist_create "${MY_INTASSEMBLY_WORKINGDIR}"

    create_operand_instance "IntegrationAssembly" "${VAR_INTASSEMBLY_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_INTASSEMBLY_WORKINGDIR}" "IntegrationAssembly-Capability.yaml" "$VAR_INTASSEMBLY_NAMESPACE" "{.status.phase}" "Ready"
  fi

  trace_out $lf_tracelevel install_intassembly

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I Integration Assembly (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install ACE
function install_ace() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I ACE (${FUNCNAME[0]}) [started : $lf_starting_date]." 0
  
  local lf_tracelevel=2
  trace_in $lf_tracelevel install_ace

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm-appconnect
  if $MY_ACE; then
    check_directory_exist_create "${MY_ACE_WORKINGDIR}"
  
    create_project "${VAR_ACE_NAMESPACE}" "${VAR_ACE_NAMESPACE} project" "For App Connect" "${MY_RESOURCESDIR}" "${MY_ACE_WORKINGDIR}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ACE_CASE $MY_ACE_OPERATOR $MY_ACE_CATALOGSOURCE_LABEL amd64
    if [[ -z $MY_ACE_VERSION ]]; then
      export MY_ACE_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE


    # Creating ACE operator subscription
    create_operator_instance "${MY_ACE_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_ACE_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
    
    create_operand_instance "SwitchServer" "${VAR_ACE_SWITCHSERVER_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_ACE_WORKINGDIR}" "ACE-SwitchServer-Capability.yaml" "$VAR_ACE_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    create_operand_instance "Dashboard" "${VAR_ACE_DASHBOARD_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_ACE_WORKINGDIR}" "ACE-Dashboard-Capability.yaml" "$VAR_ACE_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    create_operand_instance "DesignerAuthoring" "${VAR_ACE_DESIGNER_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_ACE_WORKINGDIR}" "ACE-Designer-Capability.yaml" "$VAR_ACE_NAMESPACE" "{.status.phase}" "Ready"
  fi

  trace_out $lf_tracelevel install_ace

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I ACE (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install APIC
function install_apic() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I APIC (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_apic

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm-apiconnect
  if $MY_APIC; then

    check_directory_exist_create "${MY_APIC_WORKINGDIR}"

    create_project "${VAR_APIC_NAMESPACE}" "${VAR_APIC_NAMESPACE} project" "For API ConnectC" "${MY_RESOURCESDIR}" "${MY_APIC_WORKINGDIR}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_APIC_CASE $MY_APIC_OPERATOR $MY_APIC_CATALOGSOURCE_LABEL amd64
    if [[ -z $MY_APIC_VERSION ]]; then
      export MY_APIC_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating APIC operator subscription
    create_operator_instance "${MY_APIC_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_APIC_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    if $MY_APIC_BY_COMPONENT; then
      mylog info "HOLD PLACE"
    else
      create_operand_instance "APIConnectCluster" "${VAR_APIC_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_APIC_WORKINGDIR}" "APIC-Capability.yaml" "$VAR_APIC_NAMESPACE" "{.status.phase}" "Ready"
    fi

    local lf_ingress=$($MY_CLUSTER_COMMAND get ingresses.config/cluster -o jsonpath='{.spec.domain}')
    export VAR_NAMESPACE="${VAR_APIC_NAMESPACE}"
    export VAR_APIC_GW_ROUTE_HOST="${VAR_APIC_GW_ROUTE_NAME}.${lf_ingress}"

    create_oc_resource "Route" "${VAR_APIC_GW_ROUTE_NAME}" "${MY_RESOURCESDIR}" "${MY_APIC_WORKINGDIR}" "route.yaml" "$VAR_APIC_NAMESPACE"
    unset VAR_NAMESPACE VAR_APIC_GW_ROUTE_HOST

    save_certificate ${VAR_APIC_INSTANCE_NAME}-ingress-ca ca.crt ${MY_APIC_WORKINGDIR} ${VAR_APIC_NAMESPACE}
    save_certificate ${VAR_APIC_INSTANCE_NAME}-gw-gateway ca.crt ${MY_APIC_WORKINGDIR} ${VAR_APIC_NAMESPACE}

  fi

  trace_out $lf_tracelevel install_apic

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I APIC (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install APIC Graphql (Ex Stepzen)
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=installing-maintaining-api-connect-graphql
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=graphql-installing-api-connect
function install_apic_graphql() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I APIC Graphql (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_apic_graphql

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm apic graphql
  if $MY_APIC_GRAPHQL; then

    local lf_postgresql_host lf_dsn lf_type lf_cr_name
    local lf_tgz_file lf_deploy_dir
    local lf_path lf_state lf_cr_name lf_url

    check_directory_exist_create "${MY_APIC_GRAPHQL_WORKINGDIR}"
  
    create_project "$VAR_APIC_GRAPHQL_NAMESPACE" "$VAR_APIC_GRAPHQL_NAMESPACE project" "For APIC Graphql" "${MY_RESOURCESDIR}" "${MY_APIC_GRAPHQL_WORKINGDIR}"
    add_ibm_entitlement $VAR_APIC_GRAPHQL_NAMESPACE

    # create a PostgreSQL database for the APIC Graphql
    create_edb_postgres_db "${VAR_POSTGRES_CLUSTER}" "${VAR_POSTGRES_DATABASE}" "${VAR_POSTGRES_USER}" "${MY_POSTGRES_PASSWORD}" "${MY_POSTGRES_DSN_SECRET}" "Postgres DB for APIC Graphql"

    #local lf_postgresql_password=$($MY_CLUSTER_COMMAND -n $VAR_POSTGRES_NAMESPACE get secret "${VAR_POSTGRES_CLUSTER}-superuser" -o jsonpath='{.data.paswword}' | base64 -d)
    # create a generic secret for the PostgreSQL server
    # there are three postgresql services : 
    # - ${VAR_POSTGRES_CLUSTER}-r"  : for read-only workloads across all nodes
    # - ${VAR_POSTGRES_CLUSTER}-ro" : for read-only workloads on replicas only
    # - ${VAR_POSTGRES_CLUSTER}-rw" : for read-write workloads on the primary node

    #lf_postgresql_host="${VAR_POSTGRES_CLUSTER}-rw.${VAR_POSTGRES_NAMESPACE}.svc.cluster.local"
    #lf_dsn="postgresql://${VAR_POSTGRES_USER}:${lf_postgresql_password}@${lf_postgresql_host}/${VAR_POSTGRES_DATABASE}"

    #$MY_CLUSTER_COMMAND -n $VAR_POSTGRES_NAMESPACE get Secret "${VAR_POSTGRES_CLUSTER}-superuser" -o jsonpath='{.data.uri}'
    #export VAR_DSN=$($MY_CLUSTER_COMMAND -n $VAR_POSTGRES_NAMESPACE get secret "${VAR_POSTGRES_CLUSTER}-superuser" -o jsonpath='{.data.uri}' | base64 -d)
    export VAR_DSN="postgresql://${VAR_POSTGRES_USER}:$($MY_CLUSTER_COMMAND get secret ${VAR_POSTGRES_SECRET} -n ${VAR_POSTGRES_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)@${VAR_POSTGRES_CLUSTER}-rw.${VAR_POSTGRES_NAMESPACE}.svc:5432/${VAR_POSTGRES_DATABASE}?sslmode=disable"
    echo "VAR_DSN=$VAR_DSN"
    create_oc_resource "Secret" "${MY_APIC_GRAPHQL_DSN_SECRET}" "${MY_APIC_GRAPHQL_DIR}" "${MY_APIC_GRAPHQL_WORKINGDIR}" "stepzen_secret.yaml" "$VAR_APIC_GRAPHQL_NAMESPACE"
    #$MY_CLUSTER_COMMAND create secret generic ${MY_APIC_GRAPHQL_DSN_SECRET} \
  #--from-literal=dsn="postgresql://${VAR_POSTGRES_USER}:$($MY_CLUSTER_COMMAND get secret ${VAR_POSTGRES_SECRET} -n ${VAR_POSTGRES_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)@${VAR_POSTGRES_CLUSTER}-rw.${VAR_POSTGRES_NAMESPACE}.svc:5432/${VAR_POSTGRES_DATABASE}?sslmode=disable" \
  #--namespace ${VAR_APIC_GRAPHQL_NAMESPACE}
    unset VAR_NAMESPACE VAR_SECRET_NAME VAR_DSN
    #$MY_CLUSTER_COMMAND -n ${VAR_APIC_GRAPHQL_NAMESPACE} create secret generic $MY_POSTGRES_DSN_SECRET --from-literal=DSN="${lf_dsn}"

    # Download and extract the CASE bundle.
    lf_case_version=$($MY_CLUSTER_COMMAND ibm-pak list -o json | jq -r --arg case "$MY_APIC_GRAPHQL_CASE" '.[] | select (.name == $case ) | .latestVersion')
    $MY_CLUSTER_COMMAND ibm-pak get ${MY_APIC_GRAPHQL_CASE} --version ${lf_case_version} 1>&2

    lf_tgz_file=${MY_IBMPAK_CASESDIR}${MY_APIC_GRAPHQL_CASE}/${lf_case_version}/${MY_APIC_GRAPHQL_CASE}-${lf_case_version}.tgz
    if [[ -e $lf_tgz_file ]]; then
      tar xvzf ${lf_tgz_file} -C ${MY_APIC_GRAPHQL_WORKINGDIR} >/dev/null 2>&1
    fi    
    
    # Apply the operator manifest files to the cluster
    if $MY_APPLY_FLAG; then 
      lf_deploy_dir="${MY_APIC_GRAPHQL_WORKINGDIR}${MY_APIC_GRAPHQL_CASE}/inventory/stepzenGraphOperator/files/deploy/"
      decho $lf_tracelevel "Applying the operator manifest files to the cluster : crd.yaml." 1>&2
      $MY_CLUSTER_COMMAND -n ${VAR_APIC_GRAPHQL_NAMESPACE} apply -f ${lf_deploy_dir}crd.yaml
  
      decho $lf_tracelevel "Applying the operator manifest files to the cluster : operator.yaml." 1>&2
      $MY_CLUSTER_COMMAND -n ${VAR_APIC_GRAPHQL_NAMESPACE} apply -f ${lf_deploy_dir}operator.yaml
      sleep 10
    fi

    # Configuring APIC Graphql
    create_operand_instance "StepZenGraphServer" "${VAR_APIC_GRAPHQL_INSTANCE_NAME}" "${MY_APIC_GRAPHQL_DIR}" "${MY_APIC_GRAPHQL_WORKINGDIR}" "APIC-Stepzen-Capability.yaml" "$VAR_APIC_GRAPHQL_NAMESPACE" "{.status.conditions[-1].type}" "Ready"

    # Add the certificate csr for routes (following chatgpt advice)
    export VAR_ISSUER="${VAR_APIC_GRAPHQL_INSTANCE_NAME}-issuer"
    # Create apic graphql certificates
    lf_certs_pairs=("graphql-to-graph-server-cert" "graphql_2_graph_server_cert.yaml" "graphql-to-graph-server-subscriptions-cert" "graphql_2_graph_server_subscription_cert.yaml" "introspection-cert" "introspection_cert.yaml" "stepzen-to-graph-server-cert" "stepzen_2_graph_server_cert.yaml")
    create_oc_objects "Certificate" "${MY_APIC_GRAPHQL_DIR}" "${MY_APIC_GRAPHQL_WORKINGDIR}" "${VAR_APIC_GRAPHQL_NAMESPACE}" lf_certs_pairs
  
    # Then Install OpenShift Route Support for cert-manager (openshift-routes).
    # ATTENTION REVOIR le namespace : c'est cert-manager et non pas cert-manager-namespace (https://github.com/cert-manager/openshift-routes?tab=readme-ov-file)
    # https://github.com/cert-manager/openshift-routes
    helm -n cert-manager install openshift-routes oci://ghcr.io/cert-manager/charts/openshift-routes
    #$MY_CLUSTER_COMMAND -n cert-manager apply -f <(helm template openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes --set omitHelmLabels=true)

    # Set up a stepzen-graph-server route for the stepzen account. This is the "root" account of the API Connect Graphql service, 
    # which is used to host endpoints that modify the metadata database but does not serve application requests. 
    # The stepzen-graph-server route is required for the API Connect Graphql CLI to function.
    create_oc_resource "Route" "stepzen-to-graph-server" "${MY_APIC_GRAPHQL_DIR}" "${MY_APIC_GRAPHQL_WORKINGDIR}" "stepzen-route.yaml" "$VAR_APIC_GRAPHQL_NAMESPACE"

    # Set up stepzen-graph-server and stepzen-graph-server-subscriptions routes for the graphql account.
    # This is the default account for serving application requests.
    adapt_file ${MY_RESOURCESDIR} ${MY_APIC_GRAPHQL_WORKINGDIR} graphql-route.yaml
    if ! $MY_CLUSTER_COMMAND apply -f "${MY_APIC_GRAPHQL_WORKINGDIR}graphql-route.yaml" ; then
      unset VAR_CLUSTER_DOMAIN
      trace_out $lf_tracelevel install_apic_graphql
      exit 1
    fi

    # Install Introspection service
    adapt_file ${MY_APIC_GRAPHQL_DIR} ${MY_APIC_GRAPHQL_WORKINGDIR} introspection.yaml
    if ! $MY_CLUSTER_COMMAND apply -f "${MY_APIC_GRAPHQL_WORKINGDIR}introspection.yaml" ; then
      trace_out $lf_tracelevel install_apic_graphql
      exit 1
    fi
  fi
  unset VAR_ISSUER 

  trace_out $lf_tracelevel install_apic_graphql

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I APIC Graphql (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install IBM Event streams
# https://ibm.github.io/event-automation/es/installing/installing-on-kubernetes/
function install_es() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I Eventstreams Operator (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_es

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm-eventstreams
  if $MY_ES; then
    check_directory_exist_create "${MY_ES_WORKINGDIR}"

    create_project "$VAR_ES_NAMESPACE" "$VAR_ES_NAMESPACE project" "For Eventstreams" "${MY_RESOURCESDIR}" "${MY_ES_WORKINGDIR}"
    mylog info "Creating entitlement, need to check if it is needed or works"
    add_ibm_entitlement "$VAR_ES_NAMESPACE"

    # add catalog sources
    #SB# $MY_CLUSTER_COMMAND apply --filename https://raw.githubusercontent.com/IBM/cloud-pak/master/repo/case/ibm-eventstreams/3.6.1/OLM/catalog-sources.yaml
    #SB# local lf_catalog_source_name="ibm-eventstreams"
    
    # Creating EventStreams operator subscription
    #SB# create_operator_instance "${MY_ES_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_ES_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

     # install the operator
     helm install "${MY_ES_OPERATOR}" ibm-helm/ibm-eventstreams-operator -n "$VAR_ES_NAMESPACE" --set watchAnyNamespace=true

     wait_for_state "Deployment" "eventstreams-cluster-operator" "{.status.conditions[?(@.type=='Available')].status}" "True" "${VAR_ES_NAMESPACE}"
  fi

  trace_out $lf_tracelevel install_es

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I Eventstreams Operator (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install EEM
# https://ibm.github.io/event-automation/eem/installing/installing-on-kubernetes/
function install_eem() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Event Endpoint Management (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_eem

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_EEM; then
    local lf_varb64

    check_directory_exist_create "${MY_EEM_WORKINGDIR}"

    create_project "${VAR_EEM_NAMESPACE}" "${VAR_EEM_NAMESPACE} project" "For Event Endpoint Management" "${MY_RESOURCESDIR}" "${MY_EEM_WORKINGDIR}"

    mylog info "Creating entitlement, need to check if it is needed or works"
    add_ibm_entitlement "$VAR_EEM_NAMESPACE"

    # add catalog sources
    #SB# $MY_CLUSTER_COMMAND apply --filename https://raw.githubusercontent.com/IBM/cloud-pak/master/repo/case/ibm-eventstreams/3.6.1/OLM/catalog-sources.yaml
    #SB# local lf_catalog_source_name="ibm-eventstreams"
    
    # Creating EventStreams operator subscription
    # install the operator
    # Note: If you are installing any subsequent operators in the same cluster, ensure you run the helm install command with the --set createGlobalResources=false option (as these resources have already been installed).
    helm install "${MY_EEM_OPERATOR}-crd" ibm-helm/ibm-eem-operator-crd -n "$VAR_EEM_NAMESPACE"

    helm install "${MY_EEM_OPERATOR}" ibm-helm/ibm-eem-operator -n "$VAR_EEM_NAMESPACE" --set watchAnyNamespace=true --set createGlobalResources=false

    wait_for_state "Deployment" "ibm-eem-operator" "{.status.conditions[?(@.type=='Available')].status}" "True" "${VAR_EEM_NAMESPACE}"

    # Creating EventEndpointManager instance (Event Processing)
    if $MY_KEYCLOAK_INTEGRATION; then
      export MY_EEM_AUTH_TYPE=INTEGRATION_KEYCLOAK
    else
      export MY_EEM_AUTH_TYPE=LOCAL
    fi

    create_operand_instance "EventEndpointManagement" "${VAR_EEM_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_EEM_WORKINGDIR}" "EEM-Capability.yaml" "$VAR_EEM_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    ## Creating EEM users and roles
    if $MY_KEYCLOAK_INTEGRATION; then
      # generate properties files
      adapt_file ${MY_EEM_SIMPLE_DEMODIR}resources/ ${MY_EEM_WORKINGDIR}resources/ keycloak-user-roles
      # keycloak user roles
      local lf_varb64=$(cat "${MY_EEM_WORKINGDIR}resources/keycloak-user-roles.yaml" | base64 -w0)
      $MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE patch secret "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]"
    else
      # generate properties files
      adapt_file ${MY_EEM_SIMPLE_DEMODIR}resources/ ${MY_EEM_WORKINGDIR}resources/ local-user-credentials.yaml
      adapt_file ${MY_EEM_SIMPLE_DEMODIR}resources/ ${MY_EEM_WORKINGDIR}resources/ local-user-roles.yaml
      # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
      # local user credentials
      wait_for_resource "Secret" "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" "$VAR_EEM_NAMESPACE"
      local lf_varb64=$(cat "${MY_EEM_WORKINGDIR}resources/local-user-credentials.yaml" | base64 -w0)
      $MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE patch secret "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$lf_varb64\"}]"
      
      # local user roles
      wait_for_resource "Secret" "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-roles" "$VAR_EEM_NAMESPACE"
      local lf_varb64=$(cat "${MY_EEM_WORKINGDIR}resources/local-user-roles.yaml" | base64 -w0)
      $MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE patch secret "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]"
    fi
  fi
  
  trace_out $lf_tracelevel install_eem

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Event Endpoint Management (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install EGW
function install_egw() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I Event Endpoint Gateway (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_egw

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW; then
    check_directory_exist_create "${MY_EGW_WORKINGDIR}"

    create_project "${VAR_EGW_NAMESPACE}" "${VAR_EGW_NAMESPACE} project" "For Event Endpoint Gateway" "${MY_RESOURCESDIR}" "${MY_EGW_WORKINGDIR}"

    # Wait for this URL which will used by the EventGateway
    local lf_timeout=$MY_MAX_TIMEOUT
    local lf_interval=$MY_DELAY_SECONDS
    while [[ $lf_timeout -gt 0 ]]; do
      lf_eem_manager_gateway_route=$($MY_CLUSTER_COMMAND -n $VAR_EEM_NAMESPACE get eem ${VAR_EEM_INSTANCE_NAME} -o jsonpath='{.status.endpoints}' | jq -r '.[] | select (.name=="gateway").uri')      
      if [[ -n "$lf_eem_manager_gateway_route" ]]; then
        decho $lf_tracelevel "EEM Manager Gateway route\"$lf_eem_manager_gateway_route\" for instance \"$instance\""
        break
      fi
      sleep $lf_interval
      lf_timeout=$((lf_timeout - lf_interval))
    done
    
    if [[ $lf_timeout -le 0 ]]; then
      mylog error "Timeout waiting EEM Manager Gateway route:\"$lf_eem_manager_gateway_route\" for instance \"$instance\""
      exit 1
    fi

    export VAR_EEM_MANAGER_GATEWAY_ROUTE=$lf_eem_manager_gateway_route
    create_operand_instance "EventGateway" "${VAR_EGW_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_EGW_WORKINGDIR}" "EG-Capability.yaml" "${VAR_EGW_NAMESPACE}" "{.status.phase}" "Running"
  fi

  trace_out $lf_tracelevel install_egw

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I Event Endpoint Gateway (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install EP
# https://ibm.github.io/event-automation/ep/installing/installing-on-kubernetes/
#
function install_ep() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Event Processing (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_ep

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_EP; then
    local lf_varb64

    #check_directory_exist_create "${MY_EP_WORKINGDIR}"
    check_directory_exist_create "${MY_EP_WORKINGDIR}"

    create_project "${VAR_EP_NAMESPACE}" "${VAR_EP_NAMESPACE} project" "For Event Processing" "${MY_RESOURCESDIR}" "${MY_EP_WORKINGDIR}"

    mylog info "Creating entitlement, need to check if it is needed or works"
    add_ibm_entitlement "$VAR_EP_NAMESPACE"

    # install the operator
    # Note: If you are installing any subsequent operators in the same cluster, ensure you run the helm install command with the --set createGlobalResources=false option (as these resources have already been installed).
    helm install "${MY_EP_OPERATOR}-crd" ibm-helm/ibm-ep-operator-crd -n "$VAR_EP_NAMESPACE"

    helm install "${MY_EP_OPERATOR}" ibm-helm/ibm-ep-operator -n "$VAR_EP_NAMESPACE" --set watchAnyNamespace=true --set createGlobalResources=false
    wait_for_state "Deployment" "ibm-ep-operator" "{.status.conditions[?(@.type=='Available')].status}" "True" "${VAR_EP_NAMESPACE}"

    # Use LOCAL or OIDC
    # https://ibm.github.io/event-automation/ep/security/managing-access/
    if $MY_KEYCLOAK_INTEGRATION; then
      export MY_EP_AUTH_TYPE=OIDC
      local lf_yaml_file="EP-Capability-oidc.yaml"
      
      #SB# ATTENTION
      # revoir le nommage des variables parceque MY_EP_KEYCLOAK_CLIENTID doit etre remplace par ${VAR_EP_INSTANCE_NAME}-integration-keycloak-client
      #export MY_EP_KEYCLOAK_CLIENTID=$(echo -n "$MY_EP_KEYCLOAK_CLIENTID")

      create_keycloak_client $MY_KEYCLOAK_CP4I_REALM ${VAR_EP_INSTANCE_NAME}-integration-keycloak-client $MY_KEYCLOAK_USERNAME
      get_keycloak_secret $MY_KEYCLOAK_CP4I_REALM ${VAR_EP_INSTANCE_NAME}-integration-keycloak-client $MY_KEYCLOAK_USERNAME

      decho $lf_tracelevel "VAR_KEYCLOAK_SECRET=$VAR_KEYCLOAK_SECRET"

      adapt_file "$MY_EP_DIR" "$MY_EP_WORKINGDIR" "ep-secret.yaml"
      if $MY_APPLY_FLAG; then
        $MY_CLUSTER_COMMAND apply -f ${MY_EP_WORKINGDIR}ep-secret.yaml
      fi

      create_operand_instance "EventProcessing" "${VAR_EP_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_EP_WORKINGDIR}" "EP-Capability-oidc.yaml" "$VAR_EP_NAMESPACE" "{.status.phase}" "Running"

      # wait for eventprocessing secrets to be ready (they are created by the instance)
      wait_for_resource "Secret" "${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles" "$VAR_EP_NAMESPACE"

      # generate properties files
      adapt_file ${MY_EP_SCRIPTDIR}resources/ ${MY_EP_WORKINGDIR}resources/ user-roles.yaml
  
      # user roles
      lf_varb64=$(cat "${MY_EP_WORKINGDIR}resources/user-roles.yaml" | base64 -w0)
      if $MY_APPLY_FLAG; then
        $MY_CLUSTER_COMMAND -n $VAR_EP_NAMESPACE patch secret ${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles --type=merge -p "{\"data\":{\"user-mapping.json\":\"$lf_varb64\"}}"
  
        local lf_path="{.status.phase}"
        local lf_state="Running"

        if $MY_CLUSTER_COMMAND -n $VAR_EP_NAMESPACE get $lf_type $lf_cr_name >/dev/null 2>&1; then
          wait_for_state "$lf_type" "$lf_cr_name" "$lf_path" "$lf_state" "$VAR_EP_NAMESPACE"
        else
          mylog error "$lf_cr_name of type $lf_type in $VAR_EP_NAMESPACE namespace does not exist, will not wait for state"
        fi
  
        # patch the keycloak client to add redirectUris
        patch_keycloak_client EventProcessing $lf_cr_name $MY_KEYCLOAK_CP4I_REALM ${VAR_EP_INSTANCE_NAME}-integration-keycloak-client $MY_KEYCLOAK_USERNAME $VAR_EP_NAMESPACE
      fi

    else
      export MY_EP_AUTH_TYPE=LOCAL
      create_operand_instance "EventProcessing" "${VAR_EP_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_EP_WORKINGDIR}" "EP-Capability.yaml" "$VAR_EP_NAMESPACE" "{.status.phase}" "Running"
  
      # wait for eventprocessing secrets to be ready (they are created by the instance)
      wait_for_resource "Secret" "${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles" "$VAR_EP_NAMESPACE"
      wait_for_resource "Secret" "${VAR_EP_INSTANCE_NAME}-ibm-ep-user-credentials" "$VAR_EP_NAMESPACE"

      # generate properties files
      adapt_file ${MY_EP_SIMPLE_DEMODIR}resources/ ${MY_EP_WORKINGDIR}resources/ user-credentials.yaml
      adapt_file ${MY_EP_SIMPLE_DEMODIR}resources/ ${MY_EP_WORKINGDIR}resources/ user-roles.yaml
  
      # user credentials
      local lf_varb64=$(cat "${MY_EP_WORKINGDIR}resources/user-credentials.yaml" | base64 -w0)
      if $MY_APPLY_FLAG; then
        $MY_CLUSTER_COMMAND -n $VAR_EP_NAMESPACE patch secret ${VAR_EP_INSTANCE_NAME}-ibm-ep-user-credentials --type=merge -p "{\"data\":{\"user-credentials.json\":\"$lf_varb64\"}}"
      fi
  
      # user roles
      lf_varb64=$(cat "${MY_EP_WORKINGDIR}resources/user-roles.yaml" | base64 -w0)
      if $MY_APPLY_FLAG; then
        $MY_CLUSTER_COMMAND -n $VAR_EP_NAMESPACE patch secret ${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles --type=merge -p "{\"data\":{\"user-mapping.json\":\"$lf_varb64\"}}"
      fi
    fi

  fi

  trace_out $lf_tracelevel install_ep

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Event Processing (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install Flink
# https://ibm.github.io/event-automation/ep/installing/installing-on-kubernetes/
#
function install_flink() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Flink (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_flink

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_FLINK; then
    check_directory_exist_create "${MY_FLINK_WORKINGDIR}"

    create_project "${VAR_FLINK_NAMESPACE}" "${VAR_FLINK_NAMESPACE} project" "For Flink" "${MY_RESOURCESDIR}" "${MY_FLINK_WORKINGDIR}"

    mylog info "Creating entitlement, need to check if it is needed or works"
    add_ibm_entitlement "$VAR_FLINK_NAMESPACE"

    # install the operator
    # Note: If you are installing any subsequent operators in the same cluster, ensure you run the helm install command with the --set createGlobalResources=false option (as these resources have already been installed).
    helm install "${MY_FLINK_OPERATOR}-crd" ibm-helm/ibm-eventautomation-flink-operator-crd -n "$VAR_FLINK_NAMESPACE"

    helm install "${MY_FLINK_OPERATOR}" ibm-helm/ibm-eventautomation-flink-operator -n "$VAR_FLINK_NAMESPACE" --set watchAnyNamespace=true --set createGlobalResources=false
    wait_for_state "Deployment" "flink-kubernetes-operator" "{.status.conditions[?(@.type=='Available')].status}" "True" "${VAR_FLINK_NAMESPACE}"

    ## Creation of Event automation Flink PVC and instance
    # Even if it's a pvc we use the same generic function
    create_operand_instance "PersistentVolumeClaim" "ibm-flink-pvc" "${MY_OPERANDSDIR}" "${MY_FLINK_WORKINGDIR}" "EA-Flink-PVC.yaml" "$VAR_FLINK_NAMESPACE" "{.status.phase}" "Bound"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [[ -z $MY_FLINK_VERSION ]]; then
      export MY_FLINK_VERSION=$($MY_CLUSTER_COMMAND ibm-pak list -o json | jq  --arg case "$MY_FLINK_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    ## SB]20231023 to check the status of created Flink instance : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The status field displays the current state of the FlinkDeployment custom resource.
    ## When the Flink instance is ready, the custom resource displays status.lifecycleState: STABLE and status.jobManagerDeploymentStatus: READY.
    ## STANLE and READY (uppercase!!!)
    create_operand_instance "FlinkDeployment" "${VAR_FLINK_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_FLINK_WORKINGDIR}" "EA-Flink-Capability.yaml" "$VAR_FLINK_NAMESPACE" "{.status.lifecycleState}-{.status.jobManagerDeploymentStatus}" "STABLE-READY"
  fi

  trace_out $lf_tracelevel install_flink

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of flink (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install both flink and Event processing in this order
function install_flink_ep() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel install_flink_ep

  install_flink

  install_ep

  trace_out $lf_tracelevel install_flink_ep
}

################################################
# Install Aspera HSTS
function install_hsts() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I HSTS (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_hsts

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm aspera hsts
  if $MY_HSTS; then
    check_directory_exist_create "${MY_HSTS_WORKINGDIR}"

    # Asperac License
    export MY_ASPERA_LICENSE_FILE="${MY_PRIVATEDIR}aspera-license"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_HSTS_CASE $MY_HSTS_OPERATOR $MY_HSTS_CATALOGSOURCE_LABEL amd64
    if [[ -z $MY_HSTS_VERSION ]]; then
      export MY_HSTS_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating Aspera HSTS operator subscription
    create_operator_instance "${MY_HSTS_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_HSTS_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    create_operand_instance "IbmAsperaHsts" "${VAR_HSTS_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_HSTS_WORKINGDIR}" "AsperaHSTS-Capability.yaml" "$VAR_HSTS_NAMESPACE" "{.status.conditions[0].type}" "Ready"
    
  fi

  trace_out $lf_tracelevel install_hsts

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of CP4I HSTS (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install MQ
# https://www.ibm.com/docs/en/ibm-mq/9.4.x?topic=kubernetes-example-configuring-simple-queue-manager-in
function install_mq() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing CP4I MQ operator (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel install_mq

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm-mq
  if $MY_MQ; then
    check_directory_exist_create "${MY_MQ_WORKINGDIR}"

    create_project "$VAR_MQ_NAMESPACE" "$VAR_MQ_NAMESPACE project" "For MQ" "${MY_YAMLDIR}mq/" "${MY_MQ_WORKINGDIR}"
    mylog info "Creating entitlement, need to check if it is needed or works"
    add_ibm_entitlement "$VAR_MQ_NAMESPACE"

    # create a mq service 
    check_create_oc_yaml "Service" "${VAR_QMGR}-ibm-mq" "${MY_YAMLDIR}mq/" "${MY_MQ_WORKINGDIR}" "service.yaml" "${VAR_MQ_NAMESPACE}"

    # Create a service account for the MQ
    check_create_oc_yaml "ServiceAccount" "${VAR_QMGR}-ibm-mq" "${MY_YAMLDIR}mq/" "${MY_MQ_WORKINGDIR}" "serviceaccount.yaml" "$VAR_MQ_NAMESPACE"

    # Creating MQ Pod managed by a StatefulSet
    check_create_oc_yaml "StatefulSet" "${VAR_QMGR}-ibm-mq" "${MY_YAMLDIR}mq/" "${MY_MQ_WORKINGDIR}" "statefulset.yaml" "$VAR_MQ_NAMESPACE"

    # wait for pods to be ready
    check_pod_status "app.kubernetes.io/instance=${VAR_QMGR}" "$VAR_MQ_NAMESPACE"
  fi

  trace_out $lf_tracelevel install_mq

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of MQ (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Install Instana
# Voir ceci dans CP4I 16.1.1 : With the release of Cloud Pak for Integration 16.1.1 , Instana agents are now included in the Cloud Pak for Integration package. 
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.1.1?topic=planning-licensing#instana__title__1
function install_instana() {
  SECONDS=0
  local lf_starting_date=$(date)
  mylog info "==== Installing Instana (${FUNCNAME[0]}) [started : $lf_starting_date]." 0
    
  local lf_tracelevel=2
  trace_in $lf_tracelevel install_instana

  decho $lf_tracelevel "Parameters: |no parameters|"

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA; then
    check_directory_exist_create "${MY_INSTANA_WORKINGDIR}"

    # SB]20240629 Instana Agent key
    export MY_INSTANA_AGENT_KEY=$(cat "${MY_PRIVATEDIR}instana_agent_key.txt")
    export MY_INSTANA_EP_HOST=ingress-orange-saas.instana.io
    export MY_INSTANA_ZONE_NAME="${MY_USER_EMAIL%@*}"

    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    create_project "$MY_INSTANA_AGENT_NAMESPACE" "$MY_INSTANA_AGENT_NAMESPACE project" "For Instana" "${MY_RESOURCESDIR}" "${MY_INSTANA_WORKINGDIR}"

    $MY_CLUSTER_COMMAND -n $MY_INSTANA_AGENT_NAMESPACE adm policy add-scc-to-user privileged -z instana-agent

    # Create a subscription object for instana Operator
    create_operator_instance "${MY_INSTANA_OPERATOR}" "${MY_CERTIFIED_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_INSTANA_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    # Creating Instana agent
    create_operand_instance "daemonset" "${MY_INSTANA_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_INSTANA_WORKINGDIR}" "Instana-Agent-CloudIBM-Capability.yaml" "$MY_INSTANA_AGENT_NAMESPACE" "{.status.numberReady}" "${MY_CLUSTER_WORKERS}"
    
  fi

  trace_out $lf_tracelevel install_instana

  local lf_duration=$SECONDS
  local lf_ending_date=$(date)
  mylog info "==== Installation of Instana (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise ldap adding users and groups
function customise_openldap() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise ldap (ldap.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_openldap

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_LDAP_CUSTOM; then
    read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
    check_file_exist ${MY_YAMLDIR}ldap/ldap_config.json

    # launch custom script
    ${MY_LDAP_SIMPLE_DEMODIR}scripts/ldap.config.sh --all
  fi

  trace_out $lf_tracelevel customise_openldap

  local lf_ending_date=$(date)
  mylog info "==== Customisation of ldap (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise Open Liberty
function customise_openliberty() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise Open Liberty (olp.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_openliberty

  decho $lf_tracelevel "Parameters: |no parameters|"

  # backend J2EE applications
  if $MY_OPENLIBERTY_CUSTOM; then
    ${MY_OPENLIBERTY_SCRIPTDIR}scripts/olp.config.sh --call olp_run_all
  fi

  trace_out $lf_tracelevel customise_openliberty

  local lf_ending_date=$(date)    
  mylog info "==== Customisation of Open Liberty (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise WebSphere Liberty
function customise_wasliberty() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise WAS Liberty (was.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_wasliberty

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_WASLIBERTY_CUSTOM; then
    ${MY_WASLIBERTY_DEMODIR}scripts/was.config.sh --call was_run_all
  fi

  trace_out $lf_tracelevel customise_wasliberty

  local lf_ending_date=$(date)    
  mylog info "==== Customisation of WAS Liberty (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise ACE
function customise_ace() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise ACE (ace.config.sh)." 0
  
  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_ace

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_ACE_CUSTOM; then
    ${MY_ACE_SIMPLE_DEMODIR}scripts/ace.config.sh --call ace_run_all
  fi

  trace_out $lf_tracelevel customise_ace

  local lf_ending_date=$(date)
  mylog info "==== Customisation of ace (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise APIC
function customise_apic() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise APIC (apic.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_apic

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_APIC_CUSTOM; then
    mylog info "==== Customise APIC (apic.config.sh)." 0
    ${MY_APIC_SIMPLE_DEMODIR}scripts/apic.config.sh --call apic_run_all
  fi

  trace_out $lf_tracelevel customise_apic

  local lf_ending_date=$(date)
  mylog info "==== Customisation of apic (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise IBM Event streams
function customise_es() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise ES (es.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_es

  decho $lf_tracelevel "Parameters: |no parameters|"

  # start customization
  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config

  # SB]20231026 Creating :
  # - operands properties file,
  # - topics, ...
  if $MY_ES_CUSTOM; then
    check_directory_exist_create "${MY_ES_WORKINGDIR}"

    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    check_directory_exist_create "${MY_ES_WORKINGDIR}scripts"
    check_directory_exist_create "${MY_ES_WORKINGDIR}config"
    generate_files $MY_ES_SIMPLE_DEMODIR $MY_ES_WORKINGDIR true

    ${MY_ES_SIMPLE_DEMODIR}scripts/es.config.sh --call es_run_all
    #${MY_ES_MM2_DEMODIR}scripts/es.config.sh --call es_run_all
  fi

  trace_out $lf_tracelevel customise_es

  local lf_ending_date=$(date)
  mylog info "==== Customisation of es (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise EEM
function customise_eem() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise EEM (eem.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_eem

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_EEM_CUSTOM; then
    # launch custom script
    ${MY_EEM_SIMPLE_DEMODIR}scripts/eem.config.sh --call eem_run_all
  fi

  trace_out $lf_tracelevel customise_eem

  local lf_ending_date=$(date)
  mylog info "==== Customisation of eem (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise EGW
function customise_egw() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise EGW (egw.config.sh)." 0
  
  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_egw

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_EGW_CUSTOM; then
    mylog info "==== Place Holder."
  fi

  trace_out $lf_tracelevel customise_egw

  local lf_ending_date=$(date)
  mylog info "==== Customisation of egw (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise both flink and Event processing in this order
function customise_flink_ep() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_flink_ep

  customise_flink

  customise_ep

  trace_out $lf_tracelevel customise_flink_ep
}

################################################
# Customise EP
function customise_ep() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise EP (ep.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_ep

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  ## Creating Event Processing users and roles
  if $MY_EP_CUSTOM; then
    mylog info "==== Place Holder."
  fi

  trace_out $lf_tracelevel customise_ep

  local lf_ending_date=$(date)
  mylog info "==== Customisation of ep (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0  
}

################################################
# Customise Flink
function customise_flink() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise FLINK (flink.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_flink

  decho $lf_tracelevel "Parameters: |no parameters|"

  if $MY_FLINK_CUSTOM; then
    mylog info "==== Place Holder."
  fi

  trace_out $lf_tracelevel customise_flink

  local lf_ending_date=$(date)
  mylog info "==== Customisation of flink (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise Aspera HSTS
function customise_hsts() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise HSTS (flink.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_hsts

  decho $lf_tracelevel "Parameters: |no parameters|"

  # ibm aspera hsts
  if $MY_HSTS_CUSTOM; then
    mylog info "==== Place Holder."
  fi

  trace_out $lf_tracelevel customise_hsts

  local lf_ending_date=$(date)
  mylog info "==== Customisation of hsts (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise MQ
function customise_mq() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise MQ (mq.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_mq

  decho $lf_tracelevel "Parameters: |no parameters|"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_MQ_CUSTOM; then
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [[ -z $MY_MQ_VERSION ]]; then
      export MY_MQ_VERSION=$($MY_CLUSTER_COMMAND ibm-pak list -o json | jq  --arg case "$MY_MQ_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # launch custom script
    ${MY_MQ_SIMPLE_DEMODIR}scripts/mq.config.sh --call mq_run_all
  fi

  trace_out $lf_tracelevel customise_mq

  local lf_ending_date=$(date)
  mylog info "==== Customisation of mq (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Customise Instana
function customise_instana() {
  SECONDS=0
  local lf_starting_date=$(date);
  mylog info "==== Customise INSTANA (instana.config.sh)." 0

  local lf_tracelevel=2
  trace_in $lf_tracelevel customise_instana

  decho $lf_tracelevel "Parameters: |no parameters|"

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA_CUSTOM; then
    mylog info "==== Place Holder."
  fi

  trace_out $lf_tracelevel customise_instana

  local lf_ending_date=$(date)
  mylog info "==== Customisation of instana (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
}

################################################
# Create a PostGreSQL DB
# @param 1: postgresql cluster name
# @param 2: postgresql database name
# @param 3: postgresql database username
# @param 4: postgresql database password
# @param 5: postgresql secret name
# @param 6: postgresql database description
# @param 7: namespace
# @param 8: working directory
# 
function create_edb_postgres_db() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel create_edb_postgres_db

  local lf_in_cluster_name="$1"
  local lf_in_db_name="$2"
  local lf_in_db_username="$3"
  local lf_in_db_password="$4"
  local lf_in_secret_name="$5"
  local lf_in_db_description="$6"
  decho $lf_tracelevel "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|\"$6\"|"
  
  check_directory_exist_create "${MY_EDB_POSTGRES_WORKINGDIR}"

  create_project "$VAR_POSTGRES_NAMESPACE" "EDB PostGreSQL project" "For EDB PostGreSQL" "${MY_RESOURCESDIR}" "${MY_EDB_POSTGRES_WORKINGDIR}"

  # Create a PostGreSQL DB secret
  export VAR_NAMESPACE=$VAR_POSTGRES_NAMESPACE
  export VAR_SECRET_NAME=$lf_in_secret_name
  export VAR_USERNAME=$lf_in_db_username
  export VAR_PASSWORD=$lf_in_db_password
  create_oc_resource "Secret" "${lf_in_secret_name}" "${MY_RESOURCESDIR}" "${MY_EDB_POSTGRES_WORKINGDIR}" "secret.yaml" "$VAR_POSTGRES_NAMESPACE"
  unset VAR_NAMESPACE VAR_SECRET_NAME VAR_USERNAME VAR_PASSWORD

  # PostGreSQL DB
  export VAR_POSTGRES_CLUSTER="${lf_in_cluster_name}"
  export VAR_POSTGRES_DATABASE="${lf_in_db_name}"
  export VAR_POSTGRES_USER="${lf_in_db_username}"
  export VAR_POSTGRES_SECRET="${lf_in_secret_name}"
  export VAR_POSTGRES_DATABASE_DESCRIPTION="${lf_in_db_description}"

  # the following command to be used with ibm postgres
  # export VAR_POSTGRES_IMAGE_NAME=$($MY_CLUSTER_COMMAND get packagemanifests -n $MY_CATALOGSOURCES_NAMESPACE --selector=$MY_POSTGRES_CATALOGSOURCE_NAME -o json | jq --arg channel "$MY_POSTGRES_CHL" '.items[].status.channels[] | select(.name == $channel)' | jq -r '.currentCSVDesc.relatedImages[]   | select(startswith("icr.io/cpopen/edb/postgresql:"))' | sort -V | tail -n 1)

  # and this with EDB Postgres
  export VAR_POSTGRES_IMAGE_NAME=$($MY_CLUSTER_COMMAND get packagemanifests -n $MY_CATALOGSOURCES_NAMESPACE --selector=$MY_POSTGRES_CATALOGSOURCE_NAME -o json | jq --arg channel "$MY_POSTGRES_CHL" '.items[].status.channels[] | select(.name == $channel)' | jq -r '.currentCSVDesc.relatedImages[]')
  create_operand_instance "${MY_POSTGRES_CRD_CLUSTER}" "${lf_in_cluster_name}" "${MY_POSTGRES_DIR}" "${MY_EDB_POSTGRES_WORKINGDIR}" "edb-postgres-cluster.yaml" "$VAR_POSTGRES_NAMESPACE" "{.status.conditions[?(@.type==\"Ready\")].status}" "True"
  if $MY_CLUSTER_COMMAND -n $VAR_POSTGRES_NAMESPACE wait --for=condition=Ready pod -l k8s.enterprisedb.io/cluster=$lf_in_cluster_name --timeout=300s; then
    mylog info  "✅ All Pods are Ready!"
  else
    mylog info "❌ Timeout or error waiting for Pods to be Ready."
    exit 1
  fi
  #unset VAR_POSTGRES_CLUSTER VAR_POSTGRES_DATABASE VAR_POSTGRES_USER VAR_POSTGRES_SECRET VAR_POSTGRES_DATABASE_DESCRIPTION VAR_POSTGRES_IMAGE_NAME
  
  # Authorize superuser access
  $MY_CLUSTER_COMMAND -n $VAR_POSTGRES_NAMESPACE patch "${MY_POSTGRES_CRD_CLUSTER}" $lf_in_cluster_name --type=merge -p '{"spec":{"enableSuperuserAccess":true}}' | awk '{printf "%*s%s\n", NR * $SC_SPACES_COUNTER, "", $0}'

  # Here after how to check the status of the PostGreSQL DB and connect to it
  # $MY_CLUSTER_COMMAND run pg-check --image=postgres:15 --restart=Never -- sleep 3600
  # $MY_CLUSTER_COMMAND exec -it pg-check -- bash
  # psql -h <postgresql_svc> -U <postgres_user> -d <database_name> // password is asked
  # \q to quit

  trace_out $lf_tracelevel create_edb_postgres_db
}

######################################################################
# start the default podman machine
#
function start_podman_machine () {
  local lf_tracelevel=2
  trace_in $lf_tracelevel start_podman_machine

  # check if environment variable MINIKUBE_HOME is set
  # https://ioflood.com/blog/bash-check-if-environment-variable-is-set/
  if [ -z "${MINIKUBE_HOME}" ]; then
    mylog "error" "MINIKUBE_HOME is unset or set to the empty string"
    exit 1
  fi

  # check if default podman machine is started
  lf_result=$(podman machine list --format json | jq  '.[0].Running')
  if [ "$lf_result" == "false" ]; then
	  mylog "info" "Starting podman default machine"
    podman machine start
  fi

  trace_out $lf_tracelevel start_podman_machine
}

################################################
# function for the installtion of needed resources
# namespaces, operatorgroup, entitlement, ...
################################################
function provision_cluster_init() {
  local lf_tracelevel=2
  trace_in $lf_tracelevel provision_cluster_init

  decho $lf_tracelevel "Parameters: |no parameters|"

  # check the differents pre requisites
  check_exec_prereqs
  check_resource_exist storageclass $MY_BLOCK_STORAGE_CLASS
  check_resource_exist storageclass $MY_FILE_STORAGE_CLASS
  check_directory_exist_create "$MY_WORKINGDIR"

  # Start podman default machine
  start_podman_machine

  # Get all manifests
  #if [[ ! -e $MY_RAM_MANIFEST_FILE ]]; then
  #  mylog info "Generating the file containing all packagemanifests: $MY_RAM_MANIFEST_FILE" 0
  #  $MY_CLUSTER_COMMAND -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest -o json > $MY_RAM_MANIFEST_FILE
  #fi  

  # Create project namespace.
  # SB]20231213 erreur obtenue juste après la création du cluster openshift : Error from server (Forbidden): You may not request a new project via this API.
  # Solution : https://stackoverflow.com/questions/51657711/openshift-allow-serviceaccount-to-create-project
  #          : https://stackoverflow.com/questions/44349987/error-from-server-forbidden-error-when-creating-clusterroles-rbac-author
  #          : https://bugzilla.redhat.com/show_bug.cgi?id=1639197
  # extrait du lien ci-dessus:
  # You'll need to add the "self-provisioner" role to your service account as well. Although you've made it project admin, that only means its admin rights are scoped to that one project, which is not enough to allow it to request new projects.
  # $MY_CLUSTER_COMMAND adm policy add-cluster-role-to-user self-provisioner system:serviceaccount:<project>:<cx-jenkins
  # $MY_CLUSTER_COMMAND create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=IAM#saad.benachi@fr.ibm.com
  if ! ${TECHZONE};then
    $MY_CLUSTER_COMMAND create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=$MY_USER_ID > /dev/null 2>&1
    $MY_CLUSTER_COMMAND create clusterrolebinding myname-cluster-binding --clusterrole=admin --user=$MY_USER_ID > /dev/null 2>&1
    $MY_CLUSTER_COMMAND -n $MY_OC_PROJECT adm policy add-cluster-role-to-user self-provisioner $MY_USER_ID
  fi
  
  # https://www.ibm.com/docs/en/cloud-paks/cp-integration/2023.4?topic=operators-installing-by-using-cli
  # (Only if your preferred installation mode is a specific namespace on the cluster) Create an OperatorGroup
  check_directory_exist_create "${MY_CP4I_WORKINGDIR}"

  create_project "$MY_OC_PROJECT" "$MY_OC_PROJECT project" "For Cloud Pak for Integration" "${MY_RESOURCESDIR}" "${MY_CP4I_WORKINGDIR}"
  create_project "$MY_OPERATORS_NAMESPACE" "$MY_OPERATORS_NAMESPACE project" "For openshift-operators" "${MY_RESOURCESDIR}" "${MY_CP4I_WORKINGDIR}"
  create_project "openshift-image-registry" "openshift-image-registry project" "For openshift-operators" "${MY_RESOURCESDIR}" "${MY_CP4I_WORKINGDIR}"
  create_project "openshift-marketplace" "openshift-marketplace project" "For catalogsources" "${MY_RESOURCESDIR}" "${MY_CP4I_WORKINGDIR}"

  # Add ibm entitlement key to namespace
  # SB]20230209 Aspera hsts service cannot be created because a problem with the entitlement, it must be added in the openshift-operators namespace.
  mylog info "Creating entitlement, need to check if it is needed or works"
  add_ibm_entitlement $MY_OC_PROJECT
  add_ibm_entitlement $MY_OPERATORS_NAMESPACE

  # Create a namespace object for Red Hat Openshift Logging Operator 5 I put it here because it's used by loki and observability)
  create_project "${MY_LOGGING_NAMESPACE}" "${MY_LOGGING_NAMESPACE} project" "For Openshift Logging" "${MY_RESOURCESDIR}" "${MY_CP4I_WORKINGDIR}"

  # add the IBM Helm repository to your local repository list.
  # This will provide access to the Event Automation components Helm chart packages that will install the operators on your cluster.
  helm repo add ibm-helm https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm

  # The first method to get the cluster domain
  #lf_url=$($MY_CLUSTER_COMMAND get infrastructure cluster -o jsonpath='{.status.apiServerURL}')
  #export VAR_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1)
  #export VAR_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1 | cut -d'.' -f2-)

  # get the dns name which will be used for certficate generation and other usages
  case $MY_CLUSTER_COMMAND in
  kubectl)  case $MY_K8S_FLAVOR in
            microk8s) export VAR_MINIKUBE_IP=$(multipass list --format json | jq -r --arg master "$MY_MASTER" '.list[] | select(.name ==$master) | .ipv4[0]');;
            minikube) minikube profile $MY_CLUSTER_NAME
                      export VAR_MINIKUBE_IP=$(minikube ip);;
            esac
             
             export VAR_CLUSTER_DOMAIN="cluster.local"
             export VAR_SAN_DNS="*.${VAR_CLUSTER_DOMAIN}"
             export VAR_COMMON_NAME=$VAR_SAN_DNS;;
  oc) export VAR_CLUSTER_DOMAIN=$($MY_CLUSTER_COMMAND get dns cluster -o jsonpath='{.spec.baseDomain}')
      export VAR_SAN_DNS="*.${VAR_CLUSTER_DOMAIN}"
      export VAR_COMMON_NAME=$VAR_SAN_DNS
      ;;
  esac


  # create PVC for registry
  #echo ">>>MY_WORKINGDIR: ${MY_WORKINGDIR}"
  #create_operand_instance "PersistentVolumeClaim" "registry-storage" "${MY_RESOURCESDIR}" "${MY_WORKINGDIR}" "registry_pvc.yaml" "openshift-image-registry" "{.status.phase}" "Bound"
  
  case $MY_CLUSTER_COMMAND in
  #kubectl) minikube addons enable registry
  #         local lf_port=$($MY_CLUSTER_COMMAND get svc -n kube-system -o jsonpath="{.items[?(@.metadata.name=='registry')].spec.ports[?(@.targetPort==5000)].port}")
  #         $MY_CLUSTER_COMMAND port-forward --namespace kube-system service/registry 5000:$lf_port > "${MY_WORKINGDIR}registry-portforward.log" 2>&1 &
  #         export VAR_IMAGE_REGISTRY_HOST=localhost:5000
  #         ;;
  oc) $MY_CLUSTER_COMMAND patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"storage":{"pvc":{"claim":"registry-storage"}}}}'
      # Expose service using default route
      $MY_CLUSTER_COMMAND patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
      wait_for_resource Route default-route openshift-image-registry
    
      # Get the default registry route:
      export VAR_IMAGE_REGISTRY_HOST=$($MY_CLUSTER_COMMAND get route default-route -n openshift-image-registry --template='{{.spec.host }}')
      ;;
  esac
  
  trace_out $lf_tracelevel provision_cluster_init
}

################################################
# function to install/configure a microk8s cluster
################################################
function install_microk8s_cluster {
  local lf_tracelevel=2
  trace_in $lf_tracelevel install_microk8s_cluster

  decho $lf_tracelevel "Parameters: |no parameters|"
  
  mylog info "📦 Creating MicroK8s master node..."
  multipass launch --name $MY_MASTER --cpus $MY_CPU --memory $MY_RAM --disk $MY_DISK $MY_IMAGE
  multipass exec $MY_MASTER -- sudo snap install microk8s --classic
  multipass exec $MY_MASTER -- sudo usermod -a -G microk8s ubuntu
  multipass exec $MY_MASTER -- sudo apt update && sudo apt install -y nfs-common
  
  # Fetch the join command
  for lf_worker in "${MY_WORKERS[@]}"; do
    mylog info  "🔧 Creating and joining worker nodes..."
    multipass launch --name $lf_worker --cpus $MY_CPU --memory $MY_RAM --disk $MY_DISK $MY_IMAGE
    multipass exec $lf_worker -- sudo snap install microk8s --classic
    multipass exec $lf_worker -- sudo usermod -a -G microk8s ubuntu
    multipass exec $lf_worker -- sudo apt update && sudo apt install -y nfs-common
  
    mylog info  "🧪 Generating join command for $lf_worker..."
    lf_joind_cmd=$(multipass exec $MY_MASTER -- microk8s add-node | grep 'microk8s join' | head -n1)
  
    mylog info  "🔗 Joining $lf_worker to cluster..."
    multipass exec $lf_worker -- bash -c "sudo $lf_joind_cmd --worker"
  done
  
  mylog info  "⏳ Waiting for nodes to be ready..."
  sleep 30
  multipass exec $MY_MASTER -- microk8s kubectl get nodes
  
  multipass exec $MY_MASTER --  microk8s enable cert-manager dashboard community nfs ingress registry
  
  mylog info  "🔧 Creating the k8s config file in ~/.kube..."
  multipass exec $MY_MASTER -- microk8s config > microk8s-config
  cp microk8s-config ~/.kube/config  

  trace_out $lf_tracelevel install_microk8s_cluster
}
 
######################################################################
# Create minikube cluster if it does not exist
# and wait for availability of the cluster
function install_minikube_cluster {
  local lf_tracelevel=2
  trace_in $lf_tracelevel install_minikube_cluster

  decho $lf_tracelevel "Parameters: |no parameters|"
  
  # check if environment variable MINIKUBE_HOME is set
  # https://ioflood.com/blog/bash-check-if-environment-variable-is-set/
  if [ -z "${MINIKUBE_HOME}" ]; then
    mylog "error" "MINIKUBE_HOME is unset or set to the empty string"
    exit 1
  fi

  # check if minikube cluster profile exist
  lf_result=$(minikube profile list -o json | jq -r --arg Name "$MY_CLUSTER_NAME" '.valid[] | select (.Name == $Name)')
  if [ -z "$lf_result" ]; then
	  mylog "info" "Creating/Starting minikube cluster: $MY_CLUSTER_NAME"
    minikube start --nodes $MY_CLUSTER_WORKERS \
                   --memory $MY_WORKER_MEMORY \
                   --cpus $MY_WORKER_CPUS \
                   --container-runtime=$MY_CONTAINER_RUNTIME \
                   --driver=$MY_MINIKUBE_DRIVER -p $MY_CLUSTER_NAME
  else
    # check status of the cluster
    lf_result=$(minikube profile list -o json | jq -r --arg Status "$MY_CLUSTER_FINAL_STATUS" '.valid[] | select (.Status == $Status)')
    if [ -z "$lf_result" ]; then
      mylog "info" "Starting existing minikube cluster: $MY_CLUSTER_NAME"
      minikube start -p $MY_CLUSTER_NAME
    else
      mylog "info" "minikube cluster: $MY_CLUSTER_NAME already running"
    fi
  fi

  # Create OpenEBS Storageclass
  check_directory_exist_create "${MY_OPENEBS_WORKINGDIR}"
  create_project "${MY_OPENEBS_NAMESPACE}" "${MY_OPENEBS_NAMESPACE} project" "For OpenEBS Storage provider" "${MY_YAMLDIR}openebs/" "${MY_OPENEBS_WORKINGDIR}"
  $MY_CLUSTER_COMMAND apply -f https://openebs.github.io/charts/openebs-operator.yaml
  check_create_oc_yaml "StorageClass" "openebs-localpv-block" "${MY_YAMLDIR}openebs/" "${MY_OPENEBS_WORKINGDIR}" "openebs-block.yaml" "${MY_OPENEBS_WORKINGDIR}"
  $MY_CLUSTER_COMMAND patch storageclass openebs-localpv-block -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

  trace_out $lf_tracelevel install_minikube_cluster
}

################################################
# function for the installation part of the script
################################################
function install_part() {
  local lf_tracelevel=1
  trace_in $lf_tracelevel install_part

  # needed by other components
  install_cert_manager

  # Start by installing Redhat needed/useful features
  install_oadp
  install_gitops
  install_pipelines
  # Need to executed before install_logging_loki (important when using call function)
  install_cluster_observability
  install_logging_loki
  
  #SB]20241121 install other useful tools
  install_mail
  install_openldap
  install_sftp
  
  #SB]20231214 Installing pre requisite services
  install_lic_svc
  install_lic_reporter_svc
  install_fs
  
  # install_xxx: For each capability install : case, operator, operand
  
  # install_openliberty
  install_wasliberty
  
  # CP4I Components
  install_navigator
  install_assetrepo
  install_intassembly 
  install_ace
  install_apic
  install_es
  install_eem
  install_egw
  # https://ibm.github.io/event-automation/ep/installing/overview/, there is an installation order, flink then event processing
  # so we created a function to call them in the right order
  install_flink_ep
  install_mq
  install_hsts
  install_apic_graphql

  install_instana
  install_cluster_monitoring

  #test_keycloak

  trace_out $lf_tracelevel install_part
}

################################################
# function for the customization part of the script
################################################
function customise_part() {
  local lf_tracelevel=1
  trace_in $lf_tracelevel customise_part

  customise_openldap
  
  # customise_openliberty
  
  customise_wasliberty
  
  customise_ace
  customise_apic
  customise_es
  customise_eem
  customise_egw
  customise_flink_ep
  customise_hsts
  customise_mq
  
  customise_instana

  trace_out $lf_tracelevel customise_part
}

################################################
# function to run the whole script
function run_all() {
  local lf_tracelevel=1
  trace_in $lf_tracelevel run_all

  # Start installation capabilities
  install_part
  
  # Start customization capabilities
  # No need to customise navigator, intassembly, assetrepo
  #customise_part

  trace_out $lf_tracelevel run_all
}

################################################
# main function
# Main logic
function main() {
  local lf_starting_date=$(date)
  local lf_satrting_date_in_seconds=$(date +%s)
  mylog info "==== Installing CP4I Components (${FUNCNAME[0]}) [started : $lf_starting_date]." 0

  local lf_tracelevel=1
  trace_in $lf_tracelevel main

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    return 1
  fi

  # Main script logic
  local lf_calls=""  # Initialize calls variable
  local lf_key

  while [[ $# -gt 0 ]]; do
    lf_key="$1"
    case $lf_key in
      --all)
        provision_cluster_init      
        run_all
        shift
        ;;
      --call)
        provision_cluster_init
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          lf_calls+="$1 "  # Accumulate all arguments after --call
          shift
        done
        ;;
      *)
        mylog error "Invalid option '$1'. Use --all or --call function_name parameters, function_name parameters, ...."
        trace_out $lf_tracelevel main
        return 1
        ;;
      esac
  done

  #lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces
  lf_calls=$(echo "$lf_calls" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')

  # Call processing function if --call was used
  if [[ $lf_key == "--call" ]]; then
    if [[ -n $lf_calls ]]; then
      process_calls "$lf_calls"
    else
      mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
      trace_out $lf_tracelevel main
      return 1
    fi
  fi

  trace_out $lf_tracelevel main

  local lf_ending_date=$(date)
  local lf_ending_date_in_seconds=$(date +%s)
  local lf_duration=$((lf_ending_date_in_seconds - lf_satrting_date_in_seconds))
  mylog info "==== Installation of CP4I Components (${FUNCNAME[0]}) [ended : $lf_ending_date and took : $(($lf_duration / 60)) minutes and $(($lf_duration % 60)) seconds]." 0

  exit 0
}

###################  #############################################################################
# Start of the script main entry
################################################################################################
# other example: ./provision_cluster-v2.sh --call <function_name1>, <function_name2>, ...
# other example: ./provision_cluster-v2.sh --all
#
# allow this script to be run from other locations, despite the
# relative file paths used in it
if [[ $BASH_SOURCE = */* ]]; then
  cd -- "${BASH_SOURCE%/*}/" || exit
fi

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
# PROVISION_SCRIPTDIR=$(dirname "$0")/
PROVISION_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"

sc_provision_script_parameters_file="${PROVISION_SCRIPTDIR}script-parameters.properties"
sc_provision_constant_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-constants.properties"
sc_provision_variable_properties_file="${PROVISION_SCRIPTDIR}properties/cp4i-variables.properties"
sc_provision_preambule_file="${PROVISION_SCRIPTDIR}properties/preambule.properties"
sc_provision_user_file="${PROVISION_SCRIPTDIR}private/user.properties"
sc_provision_lib_file="${PROVISION_SCRIPTDIR}lib.sh"

set -a
. "${sc_provision_script_parameters_file}"

# load config files
. "${sc_provision_constant_properties_file}"

# load config files
. "${sc_provision_variable_properties_file}"

# Load shared variables
. "${sc_provision_preambule_file}"

# Load user variables
. "${sc_provision_user_file}"
set +a

# load helper functions
. "${sc_provision_lib_file}"

# install k8s cluster
case $MY_K8S_FLAVOR in
microk8s) install_microk8s_cluster;;
minikube) #install_minikube_cluster;;
          
esac

# trap 'display_access_info' EXIT

######################################################
# main entry
######################################################
main "$@"
