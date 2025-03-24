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
  trace_in 2 install_sftp

  if $MY_SFTP; then
    SECONDS=0
    local lf_starting_date=$(date)
  
    mylog info "==== Installing SFTP server [started : $lf_starting_date]." 0 
    check_directory_exist_create "${MY_SFTP_WORKINGDIR}"
  
    create_project "${VAR_SFTP_SERVER_NAMESPACE}" "${VAR_SFTP_SERVER_NAMESPACE} project" "For SFTP server" "${MY_RESOURCESDIR}" "${MY_SFTP_WORKINGDIR}"
  
    # Create secret with users
    mylog check "Checking Secret for credential ${VAR_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" 1>&2
    if ! oc -n ${VAR_SFTP_SERVER_NAMESPACE} get secret "${VAR_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" >/dev/null 2>&1; then
      generate_password 32
      adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ users.conf
      unset USER_PASSWORD_GEN
      oc -n $VAR_SFTP_SERVER_NAMESPACE create secret generic "${VAR_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/users.conf
    fi
  
    # Create configmap with SSH keys
    mylog check "Checking ConfigMap for ssh keys ${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm" 1>&2
    if ! oc -n ${VAR_SFTP_SERVER_NAMESPACE} get configmap "${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm" >/dev/null 2>&1; then
      ssh-keygen -t ed25519 -f ${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key < /dev/null
      ssh-keygen -t rsa -b 4096 -f ${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key < /dev/null
      adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ sshd_config
      local lf_apply_cmd="oc -n $VAR_SFTP_SERVER_NAMESPACE create configmap ${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key.pub \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key.pub \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/sshd_config"

      oc -n $VAR_SFTP_SERVER_NAMESPACE create configmap ${VAR_SFTP_SERVER_NAMESPACE}-ssh-conf-cm \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key.pub \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key.pub \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/sshd_config
    fi
  
    # Check security context constraint
    mylog check "Security Context Constraint anyuid" 1>&2
    if ! oc get SecurityContextConstraints anyuid >/dev/null 2>&1; then
      oc adm policy add-scc-to-user anyuid -z default
      wait 10
      
      oc patch scc anyuid --type=merge --patch '{"users": ["system:serviceaccount:sftp:default\n"]}'      
      oc patch scc anyuid --type=merge --patch '{"allowedCapabilities":["SYS_CHROOT\n"]}'
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
    create_oc_resource "Deployment" "${VAR_SFTP_SERVER_NAMESPACE}-sftp-server" "${MY_SFTP_SCRIPTDIR}config/" "${MY_SFTP_GEN_CUSTOMDIR}config/" "sftp_dep.yaml" "$VAR_SFTP_SERVER_NAMESPACE"
  
    # Create the service to expose the SFTP server
    create_oc_resource "Service" "${VAR_SFTP_SERVER_NAMESPACE}-sftp-service" "${MY_SFTP_SCRIPTDIR}config/" "${MY_SFTP_GEN_CUSTOMDIR}config/" "sftp_svc.yaml" "$VAR_SFTP_SERVER_NAMESPACE"

    # Create the route to expose the SFTP server
    create_oc_resource "Route" "${VAR_SFTP_SERVER_NAMESPACE}-sftp-route" "${MY_SFTP_SCRIPTDIR}config/" "${MY_SFTP_GEN_CUSTOMDIR}config/" "sftp_route.yaml" "$VAR_SFTP_SERVER_NAMESPACE"

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of SFTP server [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_sftp
}

################################################
# Install GitOps
function install_gitops() {
  trace_in 2 install_gitops

  # https://docs.openshift.com/gitops/1.12/installing_gitops/installing-openshift-gitops.html
  if $MY_GITOPS; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Redhat Openshift GitOps [started : $lf_starting_date]." 0 

    check_directory_exist_create "${MY_GITOPS_WORKINGDIR}"

    # Namespace openshift-gitops-operator does not exist and will be created.
    create_operator_instance "${MY_GITOPS_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_GITOPS_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Redhat Openshift GitOps [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi
  
  trace_out 2 install_gitops
}

###############################################
# Install CP4I Cluster Logging : Loki log store
# use Openshift Logging
# https://docs.openshift.com/container-platform/4.16/observability/logging/cluster-logging-deploying.html#logging-loki-cli-install_cluster-logging-deploying
function install_logging_loki() {
  trace_in 2 install_logging_loki

  # Openshift Logging
  if $MY_LOGGING_LOKI; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Cluster Logging : Loki log store [started : $lf_starting_date]." 0 

    check_directory_exist_create "${MY_LOKI_WORKINGDIR}"

    # Create a namespace object for Loki Operator
    create_project "${MY_LOKI_NAMESPACE}" "${MY_LOKI_NAMESPACE} project" "For Loki log store" "${MY_RESOURCESDIR}" "${MY_LOKI_WORKINGDIR}"

    oc patch namespace ${MY_LOKI_NAMESPACE} -p '{"metadata": {"annotations": {"openshift.io/node-selector": ""}}}'
    oc patch namespace ${MY_LOKI_NAMESPACE} -p '{"metadata": {"labels": {"openshift.io/cluster-monitoring": "true"}}}'

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
    export VAR_LOKI_ACCESS_KEY_ID=$(oc -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.AccessKey}'| base64 --decode)
    export VAR_LOKI_ACCESS_KEY_SECRET=$(oc -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.SecretKey}'| base64 --decode)
    export VAR_LOKI_ENDPOINT=$(oc -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.Endpoint}'| base64 --decode)
    decho 3 "VAR_LOKI_ACCESS_KEY_ID=$VAR_LOKI_ACCESS_KEY_ID|VAR_LOKI_ACCESS_KEY_SECRET=$VAR_LOKI_ACCESS_KEY_SECRET|VAR_LOKI_ENDPOINT=$VAR_LOKI_ENDPOINT"

    create_oc_resource "Secret" "$MY_LOKI_SECRET" "${MY_RESOURCESDIR}" "${MY_LOKI_WORKINGDIR}" "loki-secret.yaml" "$MY_LOGGING_NAMESPACE"
    unset VAR_LOKI_ACCESS_KEY_ID VAR_LOKI_ACCESS_KEY_SECRET VAR_LOKI_ENDPOINT

    # Create a LokiStack instance
    create_operand_instance "LokiStack" "$MY_LOKI_INSTANCE_NAME" "${MY_OPERANDSDIR}" "${MY_LOKI_WORKINGDIR}" "Loki-Capability.yaml" "$MY_LOGGING_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    # SB]20241204 Configuring LokiStack log store
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/cluster-logging-loki.html

    # Create a new group for the cluster-admin user role
    oc adm groups new cluster-admin

    # add the desired user to the cluster-admin group
    oc adm groups add-users cluster-admin $MY_USER_EMAIL

    # add the cluster-admin user role to the cluster-admin group
    oc adm policy add-cluster-role-to-group cluster-admin cluster-admin
    
    # Create a ClusterLogging CR object
    # https://github.com/openshift/cluster-logging-operator/blob/master/docs/administration/upgrade/v6.0_changes.adoc#the-main-change-highlights-are
    #Two 'logging' resources:
    #5.x
    #
    #apiVersion: logging.openshift.io/v1
    #kind: ClusterLogging
    #...
    #
    #apiVersion: logging.openshift.io/v1
    #kind: ClusterLogForwarder
    #...
    #
    #Replaced by a single custom 'observability' resource:
    #6.0
    #
    #apiVersion: observability.openshift.io/v1
    #kind: ClusterLogForwarder
    #...
    #---
    # Create a service account for the collector
    oc -n $MY_LOGGING_NAMESPACE create sa $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to write data to the LokiStack CR
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA 

    # Allow the collector’s service account to collect logs
    oc project $MY_LOGGING_NAMESPACE

    oc -n $MY_LOGGING_NAMESPACE adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    oc -n $MY_LOGGING_NAMESPACE adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA
    oc -n $MY_LOGGING_NAMESPACE adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA

    #export VAR_LOKI_HOST=$(oc -n $MY_LOGGING_NAMESPACE get route $MY_LOKI_INSTANCE_NAME -o jsonpath='{.spec.host}')
    create_operand_instance "ClusterLogForwarder" "$MY_RHOL_INSTANCE_NAME" "${MY_OPERANDSDIR}" "${MY_LOKI_WORKINGDIR}" "Rhol-Loki-Capability.yaml" "$MY_LOGGING_NAMESPACE" "{.status.conditions[?(@.type==\"Ready\")].status}" "True"
    #unset VAR_LOKI_HOST
    
    # Create a UIPlugin CR to enable the Log section in the Observe tab
    #decho 3 "install_openshift_monitoring create the UI plugin"
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

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Cluster Logging : Loki log store [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_logging_loki
}

###############################################
# Install Redhat Cluster Observability Operator
# # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview
# SB]20250116 TODO : Revoir la configuration de l'observabilité du cluster à la lumière de la documentation ci-dessus.
function install_cluster_observability() {
  trace_in 2 install_cluster_observability

  # Openshift Observability
  if $MY_COO; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Cluster Observability [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_COO_WORKINGDIR}"

    if $MY_APPLY_FLAG; then 
      # Create a service account for the collector
      create_oc_resource "ServiceAccount" "$MY_LOGGING_COLLECTOR_SA" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "serviceaccount.yaml" "$MY_LOGGING_NAMESPACE"

      # Create a ClusterRole for the collector
      create_oc_resource "ClusterRole" "logging-collector-logs-writer" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "collector_ClusterRole.yaml" "$MY_LOGGING_NAMESPACE"

      # Bind the ClusterRole to the service account
      oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA
    fi

    # SB]20241203 https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/logging/logging-6-0#cluster-role-binding-for-your-service-account
    # Create a ClusterRoleBinding for the service account
    create_oc_resource "ClusterRoleBinding" "manager-rolebinding" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "role_binding.yaml" "$MY_LOGGING_NAMESPACE"

    # Install the Cluster Observability Operator
    # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview

    # Create a subscription object for Cluster Observability Operator
    # Create a subscription object for Loki Operator (because there are two loki-operator : community and Redhat, so the command to get the chl is different) 
    create_operator_instance "${MY_COO_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_COO_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
    
    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Cluster Observability [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_cluster_observability
}

###############################################
# Install Logging OpenTelemetry
# https://docs.openshift.com/container-platform/4.16/observability/logging/logging-6.1/log6x-about-6.1.html
# Pre requisite : Install the Red Hat OpenShift Logging Operator, Loki Operator, and Cluster Observability Operator (COO)
function install_logging_otel() {
  trace_in 2 install_logging_otel

  # Openshift Observability
  if $MY_COO; then

    check_directory_exist_create "${MY_COO_WORKINGDIR}"

    # Create a service account for the collector
    oc -n $MY_LOGGING_NAMESPACE create sa $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to write data to the LokiStack CR
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to collect logs
    oc project $MY_LOGGING_NAMESPACE

    oc adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA

    # Create a UIPlugin CR to enable the Log section in the Observe tab
    create_oc_resource "UIPlugin" "logging" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "uiplugin.yaml" "$MY_LOGGING_NAMESPACE"

    # Create a ClusterLogForwarder CR to configure log forwarding
    create_oc_resource "ClusterLogForwarder" "${MY_LOGGING_COLLECTOR_SA}" "${MY_RESOURCESDIR}" "${MY_COO_WORKINGDIR}" "clusterlogforwarder-otel.yaml" "$MY_LOGGING_NAMESPACE"

    # Bind the ClusterRole to the service account
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

  fi

  trace_out 2 install_logging_otel
}


###############################################
# Install/Configure Redhat Cluster Monitoring
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/index
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/common-monitoring-configuration-scenarios#configuring-core-platform-monitoring-postinstallation-steps_common-monitoring-configuration-scenarios
# 
function install_cluster_monitoring() {
  trace_in 2 install_cluster_monitoring

  # Openshift cluster monitoring
  if $MY_CLUSTER_MONITORING; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Redhat Cluster Monitoring [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_OPENSHIFT_MONITORING_WORKINGDIR}"

    create_project "${MY_OPENSHIFT_MONITORING_NAMESPACE}" "${MY_OPENSHIFT_MONITORING_NAMESPACE} project" "For Openshift monitoring" "${MY_RESOURCESDIR}" "${MY_OPENSHIFT_MONITORING_WORKINGDIR}"

    create_oc_resource "ConfigMap" "${MY_MONITORING_CM_NAME}" "${MY_RESOURCESDIR}" "${MY_OPENSHIFT_MONITORING_WORKINGDIR}" "monitoring-cm.yaml" "${MY_OPENSHIFT_MONITORING_NAMESPACE}"

    # Enable monitoring for user-defines projects
    # If you enable monitoring for user-defined projects, the user-workload-monitoring-config ConfigMap object is created by default.
    # The enableUserWorkload parameter enables monitoring for user-defined projects in the OpenShift cluster. 
    # This action creates a prometheus-operated service in the openshift-user-workload-monitoring namespace.
    #export MY_MONITORING_CM_NAME="user-workload-monitoring-config"
    #export MY_OPENSHIFT_MONITORING_NAMESPACE="openshift-user-workload-monitoring"
    oc -n $MY_OPENSHIFT_MONITORING_NAMESPACE patch configmap ${MY_MONITORING_CM_NAME} --type=merge --patch '{"data":{"config.yaml":"enableUserWorkload: true\n"}}'

    # Granting users permissions for core platform monitoring

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Redhat Cluster Monitoring [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_cluster_monitoring
}

##################################################
# Install OADP (OpenShift API for Data Protection)
function install_oadp() {
  trace_in 2 install_oadp

  if $MY_OADP; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Redhat Openshift OADP [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_OADP_WORKINGDIR}"

    # OpenShift restricts creating namespaces with the openshift- prefix via oc create namespace. 
    # However, you can bypass this limitation using oc apply:
    create_project "$MY_OADP_NAMESPACE" "${MY_OADP_NAMESPACE} project" "For OADP deployment" "${MY_RESOURCESDIR}" "${MY_OADP_WORKINGDIR}"

    # Operator group for OADP in single namespace
    create_oc_resource "OperatorGroup" "$MY_OADP_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_OADP_WORKINGDIR" "operator-group-single.yaml" "$MY_OADP_NAMESPACE"

    # Create a subscription object for OADP Operator
    create_operator_instance "${MY_OADP_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_OADP_WORKINGDIR}" "${MY_OADP_NAMESPACE}"

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Redhat Openshift OADP [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi
  trace_out 2 install_oadp
}

################################################
# Install redhat Pipelines (tekton)
function install_pipelines() {
  trace_in 2 install_pipelines

  if $MY_TEKTON; then
    SECONDS=0
    local lf_starting_date=$(date)
  
    # https://docs.openshift.com/pipelines/1.14/install_config/installing-pipelines.html
    mylog info "==== Installing Redhat Openshift Pipelines (tekton) [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_PIPELINES_WORKINGDIR}"

    # Create a subscription object for pipelines Operator
    create_operator_instance "${MY_PIPELINES_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_PIPELINES_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
  
    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Redhat Openshift Pipelines (tekton) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_pipelines
}

################################################
# Add mailhog app to openshift
# Port is hard coded to 8025 and is defined by mailhog (default port)
function install_mailhog() {
  trace_in 2 install_mailhog

  if $MY_MAILHOG; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Mailhog (server and client) [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_MAIL_SERVER_WORKINGDIR}"

    local lf_type="deployment"
    local lf_name="mailhog"

    # create namespace if needed
    create_project "${VAR_MAIL_SERVER_NAMESPACE}" "${VAR_MAIL_SERVER_NAMESPACE} project" "For Mailhog fake SMTP server deployment" "${MY_RESOURCESDIR}" "${MY_MAIL_SERVER_WORKINGDIR}"

    deploy_mailhog ${lf_type} ${lf_name} ${VAR_MAIL_SERVER_NAMESPACE}

    expose_service_mailhog ${lf_name} '8025' ${VAR_MAIL_SERVER_NAMESPACE} 

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Mailhog (server and client) [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_mailhog
}

################################################
# Add OpenLdap app to openshift
function install_openldap() {
  trace_in 2 install_openldap

  if $MY_LDAP; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing OpenLdap [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_LDAP_WORKINGDIR}"

    # create namespace if needed
    create_project "${VAR_LDAP_NAMESPACE}" "${VAR_LDAP_NAMESPACE} project" "For OpenLDAP deployment" "${MY_RESOURCESDIR}" "${MY_LDAP_WORKINGDIR}"

    local lf_type="deployment"
    local lf_name="${MY_LDAP_DEPLOYMENT}"

    provision_persistence_openldap

    deploy_openldap ${lf_type} ${MY_LDAP_DEPLOYMENT} ${MY_LDAP_SERVICEACCOUNT} ${VAR_LDAP_NAMESPACE}

    create_expose_service_openldap "${MY_YAMLDIR}ldap/" ${MY_LDAP_WORKINGDIR} "ldap_svc.yaml"
    
    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of OpenLdap [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_openldap
}

################################################
# Install Cert Manager
# 20250110 https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.1.1?topic=operators-installing-by-using-cli#before-you-begin__title__1
# The API management, Event Manager, and Event Processing instances require you to install an appropriate certificate manager.
# Follow the instructions in : 
# https://docs.openshift.com/container-platform/4.16/security/cert_manager_operator/cert-manager-operator-install.html
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift#cert-manager-install-cli_cert-manager-operator-install
# to fulfill this requirement.
function install_cert_manager() {
  trace_in 2 install_cert_manager

  if $MY_CERT_MANAGER; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Redhat Cert Manager [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_CERTMANAGER_WORKINGDIR}"
    
    create_project "$MY_CERTMANAGER_OPERATOR_NAMESPACE" "${MY_CERTMANAGER_OPERATOR_NAMESPACE} project" "For cert manager" "${MY_RESOURCESDIR}" "${MY_CERTMANAGER_WORKINGDIR}"
    
    create_oc_resource "OperatorGroup" "$MY_CERTMANAGER_OPERATOR" "$MY_RESOURCESDIR" "$MY_CERTMANAGER_WORKINGDIR" "operator-group-cert-manager.yaml" "$MY_CERTMANAGER_OPERATOR_NAMESPACE"
  
    # Create a subscription object for cert manager Operator
    create_operator_instance "${MY_CERTMANAGER_OPERATOR}" "${MY_RH_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_CERTMANAGER_WORKINGDIR}" "${MY_CERTMANAGER_OPERATOR_NAMESPACE}"

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Redhat Cert Manager [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_cert_manager
}

################################################
# Install Licensing Server
# 2025010 https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-license-openshift-container-platform
#
function install_lic_svc() {
  trace_in 2 install_lic_svc

  # ibm-license-server
  if $MY_LIC_SRV; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing IBM License Server [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_LICENSE_SERVICE_WORKINGDIR}"

    create_project "$MY_LICENSE_SERVICE_NAMESPACE"  "${MY_LICENSE_SERVICE_NAMESPACE} project" "For License Server deployment" "${MY_RESOURCESDIR}" "${MY_LICENSE_SERVICE_WORKINGDIR}"

    check_add_cs_ibm_pak $MY_LICENSE_SERVICE_CASE $MY_LICENSE_SERVICE_OPERATOR amd64
    if [[ -z $MY_LICENSE_SERVICE_VERSION ]]; then
      export MY_LICENSE_SERVICE_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    create_oc_resource "OperatorGroup" "$MY_LICENSE_SERVICE_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_LICENSE_SERVICE_WORKINGDIR" "operator-group-single.yaml" "$MY_LICENSE_SERVICE_NAMESPACE"

    # Create a subscription object for license service Operator
    create_operator_instance "${MY_LICENSE_SERVICE_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_LICENSE_SERVICE_WORKINGDIR}" "${MY_LICENSE_SERVICE_NAMESPACE}"
    wait_for_resource IBMLicensing instance $MY_LICENSE_SERVICE_NAMESPACE
    
    local lf_cr_name=$(oc -n $MY_LICENSE_SERVICE_NAMESPACE get IBMLicensing -o jsonpath='{.items[0].metadata.name}')
    accept_license_fs IBMLicensing $lf_cr_name $MY_LICENSE_SERVICE_NAMESPACE

    mylog info "Check if Installing network policies for license Service is needed" 1>&2
    #mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license"
    search_networkpolicies
    local lf_res=$?
    decho 3 "lf_res=$lf_res"
    if [[ $lf_res -eq 1 ]]; then
      mylog info "Please import and install network policies for License Service."
      mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license#installing-network-policies"
      mylog info "Download the two files and put them in $MY_RESOURCESDIR, then modify the namespace to use IBM License Service namespace"
      install_networkpolicies
     else
      mylog info "Network policies for License Service not needed."
    fi

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of IBM License Server [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_lic_svc
}

################################################
# Install Licensing Service Reporter
# 2025010 https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=repository-installing-license-service-reporter-cli
#
function install_lic_reporter_svc() {
  trace_in 2 install_lic_reporter_svc

  # ibm-license-server
  if $MY_LIC_SRV_REPORTER; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing IBM License Service Reporter [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}"

    create_project "$MY_LICENSE_SERVICE_REPORTER_NAMESPACE" "${MY_LICENSE_SERVICE_REPORTER_NAMESPACE} project" "For License Service Reporter deployment" "${MY_RESOURCESDIR}" "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}"

    check_add_cs_ibm_pak $MY_LICENSE_SERVICE_REPORTER_CASE $MY_LICENSE_SERVICE_REPORTER_OPERATOR amd64
    if [[ -z $MY_LICENSE_SERVICE_REPORTER_VERSION ]]; then
      export MY_LICENSE_SERVICE_REPORTER_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Operator group for License Service Reporter in single namespace
    create_oc_resource "OperatorGroup" "$MY_LICENSE_SERVICE_REPORTER_OPERATORGROUP" "$MY_RESOURCESDIR" "$MY_LICENSE_SERVICE_REPORTER_WORKINGDIR" "operator-group-single.yaml" "$MY_LICENSE_SERVICE_REPORTER_NAMESPACE"

    # Create a subscription object for license service reporter Operator
    create_operator_instance "${MY_LICENSE_SERVICE_REPORTER_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}" "${MY_LICENSE_SERVICE_REPORTER_NAMESPACE}"
      
    mylog info "Creating the License Service Reporter instance" 1>&2
    export MY_LICENSE_SERVICE_REPORTER_VERSION=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $MY_LICENSE_SERVICE_REPORTER_OPERATOR -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSVDesc.version')
    create_operand_instance "IBMLicenseServiceReporter" "$MY_LICENSE_SERVICE_REPORTER_INSTANCE_NAME" "${MY_OPERANDSDIR}" "${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}" "LIC-Reporter-Capability.yaml" "$MY_LICENSE_SERVICE_REPORTER_NAMESPACE" "{.status.LicenseServiceReporterPods[-1].phase}" "Running"

    # Add license service to the reporter
    # oc get routes -n ibm-licensing | grep ibm-license-service-reporter | awk '{print $2}'
    mylog info "Add license service to the reporter" 1>&2
    decho 3 "oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name==ibm-license-service-reporter)].spec.host}'"
    lf_licensing_service_reporter_url=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-license-service-reporter")].spec.host}')
    decho 3 "License Service Reporter URL: $lf_licensing_service_reporter_url"
    oc -n $MY_LICENSE_SERVICE_NAMESPACE patch IBMLicensing instance --type merge --patch "{\"spec\":{\"sender\":{\"reporterSecretToken\":\"ibm-license-service-reporter-token\",\"reporterURL\":\"https://$lf_licensing_service_reporter_url/\",\"clusterID\":\"MyClusterTest1\",\"clusterName\":\"MyClusterTest1\"}}}"

    mylog info "Check if Installing network policies for license Service is needed" 1>&2
    #mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license"
    search_networkpolicies
    local lf_res=$?
    decho 3 "lf_res=$lf_res"
    if [[ $lf_res -eq 1 ]]; then
      mylog info "Please import and install network policies for License Service."
      mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license#installing-network-policies"
      mylog info "Download the two files and put them in $MY_RESOURCESDIR, then modify the namespace to use IBM License Service namespace"
      install_networkpolicies
    else
      mylog info "Network policies for License Service not needed."
    fi

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of IBM License Service Reporter [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_lic_reporter_svc
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
  trace_in 2 install_fs

  if $MY_COMMONSERVICES; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing IBM Common Services [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_COMMONSERVICES_WORKINGDIR}"

    create_project "$MY_COMMONSERVICES_NAMESPACE" "$MY_COMMONSERVICES_NAMESPACE project" "For the common services" "${MY_RESOURCESDIR}" "${MY_COMMONSERVICES_WORKINGDIR}"

    # ibm-cp-common-services
    check_add_cs_ibm_pak $MY_COMMONSERVICES_CASE $MY_COMMONSERVICES_OPERATOR amd64 $MY_COMMONSERVICES_VERSION
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
    #accept_license_fs $MY_OPERATORS_NAMESPACE
    accept_license_fs CommonService $MY_COMMONSERVICES_INSTANCE_NAME $MY_OPERATORS_NAMESPACE

    # Configuring foundational services by using the CommonService custom resource.
    create_oc_resource "CommonService" "$MY_COMMONSERVICES_INSTANCE_NAME" "${MY_RESOURCESDIR}" "${MY_COMMONSERVICES_WORKINGDIR}" "foundational-services-cr.yaml" "$MY_OPERATORS_NAMESPACE"
    
    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of IBM Common Services [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_fs
}
 
################################################
# Install Open Liberty
function install_openliberty() {
  trace_in 2 install_openliberty

  # backend J2EE applications
  if $MY_OPENLIBERTY; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing OPEN Liberty [started : $lf_starting_date]." 0
    check_directory_exist_create "${MY_OPENLIBERTY_WORKINGDIR}"

    create_project "$VAR_OPENLIBERTY_NAMESPACE" "$VAR_OPENLIBERTY_NAMESPACE project" "For Open Liberty instances and create custom API" "${MY_RESOURCESDIR}" "${MY_OPENLIBERTY_WORKINGDIR}"

    # TODO other approach is to use the catalog which already inludes the Open Liberty operator and use a subscription
    # Case exists 1.3.1, and IBM/RedHat Catalog

    export OPEN_LIBERTY_OPERATOR_NAMESPACE=$VAR_OPENLIBERTY_NAMESPACE
    export OPEN_LIBERTY_OPERATOR_WATCH_NAMESPACE=$VAR_OPENLIBERTY_NAMESPACE

    # TODO Check that is this value
    export WATCH_NAMESPACE='""'
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}config/ ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-rbac-watch-all.yaml
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}config/ ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-crd.yaml
    adapt_file ${MY_OPENLIBERTY_SCRIPTDIR}config/ ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/ openliberty-app-operator.yaml

    # Creating Open Liberty operator subscription (Check arbitrarely one resource, the deployment of the operator)
    local lf_octype='deployment'
    local lf_name='olo-controller-manager'

    # check if deployment of the operator already performed
    mylog check "Checking ${lf_name}/${lf_octype} in ${VAR_OPENLIBERTY_NAMESPACE}"
    if ! oc -n ${VAR_OPENLIBERTY_NAMESPACE} get ${lf_octype} ${lf_name} >/dev/null 2>&1; then
      if $MY_APPLY_FLAG; then     
        oc apply --server-side -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml
        oc apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml
        oc -n ${VAR_OPENLIBERTY_NAMESPACE} apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml
      fi
    fi

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of OPEN Liberty [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_openliberty
}

################################################
# Install WebSphere Liberty
function install_wasliberty() {
  trace_in 2 install_wasliberty
  
  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 3 arguments:  destination directory and namespace"
    trace_out 2 install_wasliberty
    exit  1
  fi


  if $MY_WASLIBERTY; then
    # export here all needed variables
    export VAR_WASLIBERTY_NAMESPACE=$lf_in_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing WAS Liberty [started : $lf_starting_date]." 0

    #check_directory_exist_create "${MY_WASLIBERTY_WORKINGDIR}"
    check_directory_exist_create "${lf_in_target_directory}"

    create_project "$VAR_WASLIBERTY_NAMESPACE" "$VAR_WASLIBERTY_NAMESPACE project" "For WebSphere Application Server (Liberty) instances and create custom API" "${MY_RESOURCESDIR}" "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_WASLIBERTY_CASE $MY_WASLIBERTY_OPERATOR amd64
    if [[ -z $MY_WASLIBERTY_VERSION ]]; then
      export MY_WASLIBERTY_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Operator group for WAS Liberty in single namespace
    #create_oc_resource "OperatorGroup" "$MY_WASLIBERTY_OPERATORGROUP" "${MY_RESOURCESDIR}" "${MY_WASLIBERTY_WORKINGDIR}" "operator-group-single.yaml" "$MY_WASLIBERTY_NAMESPACE"
    create_oc_resource "OperatorGroup" "$MY_WASLIBERTY_OPERATORGROUP" "${MY_RESOURCESDIR}" "${lf_in_target_directory}" "operator-group-single.yaml" "$VAR_WASLIBERTY_NAMESPACE"

    # Creating WebSphere Liberty operator subscription
    #create_operator_instance "${MY_WASLIBERTY_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_WASLIBERTY_WORKINGDIR}" "${MY_WASLIBERTY_NAMESPACE}"
    create_operator_instance "${MY_WASLIBERTY_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${VAR_WASLIBERTY_NAMESPACE}"

    # unset exported needed variables
    #unset VAR_WASLIBERTY_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of WAS Liberty [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_wasliberty
}

################################################
# Install Navigator (depending on two boolean)
function install_navigator() {
  trace_in 2 install_navigator

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_navigator
    exit  1
  fi

  ## ibm-integration-platform-navigator
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  # Creating Navigator operator subscription
  if $MY_NAVIGATOR; then
    # export here all needed variables
    export VAR_NAVIGATOR_NAMESPACE=$lf_in_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I Navigator [started : $lf_starting_date]." 0

    #check_directory_exist_create "${MY_NAVIGATOR_WORKINGDIR}"
    check_directory_exist_create "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_NAVIGATOR_CASE $MY_NAVIGATOR_OPERATOR amd64
    if [[ -z $MY_NAVIGATOR_VERSION ]]; then
      export MY_NAVIGATOR_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating Navigator operator subscription
    create_operator_instance "${MY_NAVIGATOR_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"    
  fi

  if $MY_NAVIGATOR_INSTANCE; then
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [[ -z $MY_NAVIGATOR_VERSION ]]; then
      export MY_NAVIGATOR_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_NAVIGATOR_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
      decho 3 "MY_NAVIGATOR_VERSION=$MY_NAVIGATOR_VERSION"
    fi

    # Creating Navigator instance
    create_operand_instance "PlatformNavigator" "${VAR_NAVIGATOR_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "Navigator-Capability.yaml" "$VAR_NAVIGATOR_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    # unset exported needed variables
    #unset VAR_NAVIGATOR_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I Navigator [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_navigator
}

################################################
# Install Asset Repository
function install_assetrepo() {
  trace_in 2 install_assetrepo

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_assetrepo
    exit  1
  fi


  if $MY_ASSETREPO; then
    # export here all needed variables
    export VAR_ASSETREPO_NAMESPACE=$lf_in_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I Asset Repository [started : $lf_starting_date]." 0

    check_directory_exist_create "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ASSETREPO_CASE $MY_ASSETREPO_OPERATOR amd64
    if [[ -z $MY_ASSETREPO_VERSION ]]; then
      export MY_ASSETREPO_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating Asset Repository operator subscription
    #create_operator_instance "${MY_ASSETREPO_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_ASSETREPO_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
    create_operator_instance "${MY_ASSETREPO_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"

    if $MY_ASSETREPO_INSTANCE; then
      #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
      if [[ -z $MY_ASSETREPO_VERSION ]]; then
        export MY_ASSETREPO_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ASSETREPO_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
        decho 3 "MY_ASSETREPO_VERSION=$MY_ASSETREPO_VERSION"
      fi

      # Creating Asset Repository instance
      #create_operand_instance "AssetRepository" "${MY_ASSETREPO_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_ASSETREPO_WORKINGDIR}" "AR-Capability.yaml" "$VAR_ASSETREPO_NAMESPACE" "{.status.phase}" "Ready"
      create_operand_instance "AssetRepository" "${VAR_ASSETREPO_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "AR-Capability.yaml" "$VAR_ASSETREPO_NAMESPACE" "{.status.phase}" "Ready"
    fi

    # unset exported needed variables
    #unset VAR_ASSETREPO_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I Asset Repository [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_assetrepo
}

################################################
# Install Integration Assembly
function install_intassembly() {
  trace_in 2 install_intassembly

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_intassembly
    exit  1
  fi

  # Creating Integration Assembly instance
  if $MY_INTASSEMBLY; then
    # export here all needed variables
    export VAR_INTASSEMBLY_NAMESPACE=$lf_in_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I Integration Assembly [started : $lf_starting_date]." 0

    check_directory_exist_create "${lf_in_target_directory}"

    create_operand_instance "IntegrationAssembly" "${VAR_INTASSEMBLY_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "IntegrationAssembly-Capability.yaml" "$VAR_INTASSEMBLY_NAMESPACE" "{.status.phase}" "Ready"

    # unset exported needed variables
    #unset VAR_INTASSEMBLY_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I Integration Assembly [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_intassembly
}

################################################
# Install ACE
function install_ace() {
  trace_in 2 install_ace

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_ace
    exit  1
  fi

  # ibm-appconnect
  if $MY_ACE; then
    SECONDS=0
    local lf_starting_date=$(date)

    # export here all needed variables
    export VAR_ACE_NAMESPACE=$lf_in_namespace

    mylog info "==== Installing CP4I ACE [started : $lf_starting_date]." 0

    check_directory_exist_create "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ACE_CASE $MY_ACE_OPERATOR amd64
    if [[ -z $MY_ACE_VERSION ]]; then
      export MY_ACE_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating ACE operator subscription
    create_operator_instance "${MY_ACE_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"
    
    # Creating ACE Switch Server instance (used for callable flows)
    create_operand_instance "SwitchServer" "${VAR_ACE_SWITCHSERVER_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "ACE-SwitchServer-Capability.yaml" "$VAR_ACE_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    # Creating ACE Dashboard instance
    create_operand_instance "Dashboard" "${VAR_ACE_NAMESPACE}-ace-db" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "ACE-Dashboard-Capability.yaml" "$VAR_ACE_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    # Creating ACE Designer instance
    create_operand_instance "DesignerAuthoring" "${VAR_ACE_DESIGNER_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "ACE-Designer-Capability.yaml" "$VAR_ACE_NAMESPACE" "{.status.phase}" "Ready"

    # unset exported needed variables
    #unset VAR_ACE_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I ACE [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_ace
}

################################################
# Install APIC
function install_apic() {
  trace_in 2 install_apic

  local lf_in_target_directory="$1"
  export  VAR_APIC_NAMESPACE="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_apic
    exit  1
  fi

  # ibm-apiconnect
  if $MY_APIC; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I APIC [started : $lf_starting_date]." 0

    check_directory_exist_create "${MY_APIC_WORKINGDIR}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_APIC_CASE $MY_APIC_OPERATOR amd64
    if [[ -z $MY_APIC_VERSION ]]; then
      export MY_APIC_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating APIC operator subscription
    #create_operator_instance "${MY_APIC_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_APIC_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
    create_operator_instance "${MY_APIC_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"

    if $MY_APIC_BY_COMPONENT; then
      mylog info "HOLD PLACE"
    else
      # Creating APIC instance
      #create_operand_instance "APIConnectCluster" "${MY_APIC_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_APIC_WORKINGDIR}" "APIC-Capability.yaml" "$MY_APIC_NAMESPACE" "{.status.phase}" "Ready"
      create_operand_instance "APIConnectCluster" "${VAR_APIC_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "APIC-Capability.yaml" "$VAR_APIC_NAMESPACE" "{.status.phase}" "Ready"
    fi

    #AD/SB]20240703 enable the Gateway Cluster webGui Management and add webgui-port to set it accessible
    mylog info "Enable web console of the API Connect Gateway"
    #oc -n "${MY_APIC_NAMESPACE}" patch GatewayCluster "${MY_APIC_INSTANCE_NAME}-gw" --type merge -p '{"spec": {"webGUIManagementEnabled": true}}'
    oc -n "${VAR_APIC_NAMESPACE}" patch GatewayCluster "${VAR_APIC_GW_ROUTE_INSTANCE}" --type merge -p '{"spec": {"webGUIManagementEnabled": true}}'

    local lf_ingress=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
    export VAR_NAMESPACE="${VAR_APIC_NAMESPACE}"
    export VAR_APIC_GW_ROUTE_HOST="${VAR_APIC_GW_ROUTE_NAME}.${lf_ingress}"

    #create_oc_resource "Route" "${MY_APIC_GW_ROUTE_NAME}" "${MY_RESOURCESDIR}" "${MY_APIC_WORKINGDIR}" "route.yaml" "$MY_APIC_NAMESPACE"
    create_oc_resource "Route" "${VAR_APIC_GW_ROUTE_NAME}" "${MY_RESOURCESDIR}" "${lf_in_target_directory}" "route.yaml" "$VAR_APIC_NAMESPACE"
    unset VAR_NAMESPACE VAR_APIC_GW_ROUTE_HOST

    #save_certificate ${MY_APIC_NAMESPACE} cp4i-apic-ingress-ca ca.crt ${MY_WORKINGDIR}
    #save_certificate ${MY_APIC_NAMESPACE} cp4i-apic-gw-gateway ca.crt ${MY_WORKINGDIR}
    save_certificate ${VAR_APIC_NAMESPACE} cp4i-apic-ingress-ca ca.crt ${lf_in_target_directory}
    save_certificate ${VAR_APIC_NAMESPACE} cp4i-apic-gw-gateway ca.crt ${lf_in_target_directory}

    # unset exported needed variables 
    # unset VAR_APIC_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I APIC [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_apic
}

################################################
# Install APIC Graphql (Ex Stepzen)
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=installing-maintaining-api-connect-graphql
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=graphql-installing-api-connect
function install_apic_graphql() {
  trace_in 2 install_apic_graphql

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_apic_graphql
    exit  1
  fi

  # export here all needed variables
  export VAR_APIC_GRAPHQL_NAMESPACE=$lf_in_namespace

  # ibm apic graphql
  if $MY_APIC_GRAPHQL; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I APIC Graphql [started : $lf_starting_date]." 0

    local lf_postgresql_host lf_dsn lf_type lf_cr_name
    local lf_tgz_file lf_deploy_dir
    local lf_path lf_state lf_cr_name lf_url

    # Create the apic_graphql working directory if it does not exist
    check_directory_exist_create "${lf_in_target_directory}"
  
    # Create namespace for IBM Stepzen.
    create_project "$VAR_APIC_GRAPHQL_NAMESPACE" "$VAR_APIC_GRAPHQL_NAMESPACE project" "For IBM Stepzen instances and create custom API" "${MY_RESOURCESDIR}" "${lf_in_target_directory}"
    add_ibm_entitlement $VAR_APIC_GRAPHQL_NAMESPACE

    # create a PostgreSQL database for the APIC Graphql
    create_edb_postgres_db "apic-graphql-cluster" "apic-graphql-db" "apic-graphql-pg-user" "apic-graphql-pg-password" "apic-graphql-pg-secret" "apic graphql pg database"

    # create a generic secret for the PostgreSQL server
    # there are three postgresql services : 
    # - ${VAR_POSTGRES_CLUSTER}-r"  : for read-only workloads across all nodes
    # - ${VAR_POSTGRES_CLUSTER}-ro" : for read-only workloads on replicas only
    # - ${VAR_POSTGRES_CLUSTER}-rw" : for read-write workloads on the primary node

    lf_postgresql_host="${VAR_POSTGRES_CLUSTER}-rw.${VAR_POSTGRES_NAMESPACE}.svc.cluster.local"
    lf_dsn="postgresql://${VAR_POSTGRES_USER}:${VAR_POSTGRES_PASSWORD}@${lf_postgresql_host}/${VAR_POSTGRES_DATABASE}"
    lf_type="Secret"
    lf_cr_name="${MY_POSTGRES_DSN_PASSWORD}"
    if oc -n ${VAR_APIC_GRAPHQL_NAMESPACE} get ${lf_type} ${lf_cr_name} >/dev/null 2>&1; then
      mylog info "Custom Resource $lf_type/$lf_cr_name already exists"
    else
      oc -n ${VAR_APIC_GRAPHQL_NAMESPACE} create secret generic $lf_cr_name --from-literal=DSN="${lf_dsn}"
    fi

    # Download and extract the CASE bundle.
    lf_case_version=$(oc ibm-pak list -o json | jq -r --arg case "$MY_APIC_GRAPHQL_CASE" '.[] | select (.name == $case ) | .latestVersion')
    oc ibm-pak get ${MY_APIC_GRAPHQL_CASE} --version ${lf_case_version} 1>&2

    lf_tgz_file=${MY_IBMPAK_CASESDIR}${MY_APIC_GRAPHQL_CASE}/${lf_case_version}/${MY_APIC_GRAPHQL_CASE}-${lf_case_version}.tgz
    if [[ -e $lf_tgz_file ]]; then
      tar xvzf ${lf_tgz_file} -C ${lf_in_target_directory} >/dev/null 2>&1
    fi    
    
    # Apply the operator manifest files to the cluster
    if $MY_APPLY_FLAG; then 
      lf_deploy_dir="${lf_in_target_directory}${MY_APIC_GRAPHQL_CASE}/inventory/stepzenGraphOperator/files/deploy/"
      decho 3 "Applying the operator manifest files to the cluster : crd.yaml." 1>&2
      oc -n ${VAR_APIC_GRAPHQL_NAMESPACE} apply -f ${lf_deploy_dir}crd.yaml
  
      decho 3 "Applying the operator manifest files to the cluster : operator.yaml." 1>&2
      oc -n ${VAR_APIC_GRAPHQL_NAMESPACE} apply -f ${lf_deploy_dir}operator.yaml
      sleep 10
    fi

    # Configuring APIC Graphql
    create_operand_instance "StepZenGraphServer" "${VAR_APIC_GRAPHQL_INSTANCE_NAME}" "${MY_APIC_GRAPHQL_DIR}" "${lf_in_target_directory}" "APIC-Stepzen-Capability.yaml" "$VAR_APIC_GRAPHQL_NAMESPACE" "{.status.conditions[-1].type}" "Ready"

    # Creating APIC Graphql route
    # first create a cluster issuer (this creates a simple self-signed issuer for the root certificate)
    create_oc_resource "Issuer" "${MY_ISSUER}" "${MY_RESOURCESDIR}" "${lf_in_target_directory}" "self-signed-issuer.yaml" "$VAR_APIC_GRAPHQL_NAMESPACE"

    # Add the certificate csr for routes (following chatgpt advice)
    adapt_file ${MY_APIC_GRAPHQL_DIR} ${MY_WORKINGDIR} stepzen-graphql-csr.yaml
    if $MY_APPLY_FLAG; then 
      if ! oc apply -f "${MY_WORKINGDIR}stepzen-graphql-csr.yaml" ; then
        unset VAR_CLUSTER_DOMAIN
        trace_out 2 install_apic_graphql
        exit 1
      fi
  
      # Then Install OpenShift Route Support for cert-manager (openshift-routes).
      # ATTENTION REVOIR le namespace : c'est cert-manager et non pas cert-manager-namespace (https://github.com/cert-manager/openshift-routes?tab=readme-ov-file)
      # https://github.com/cert-manager/openshift-routes
      helm -n cert-manager install openshift-routes oci://ghcr.io/cert-manager/charts/openshift-routes
      #oc -n cert-manager apply -f <(helm template openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes --set omitHelmLabels=true)
    fi

    # Set up a stepzen-graph-server route for the stepzen account. This is the "root" account of the API Connect Graphql service, 
    # which is used to host endpoints that modify the metadata database but does not serve application requests. 
    # The stepzen-graph-server route is required for the API Connect Graphql CLI to function.
    create_oc_resource "Route" "stepzen-to-graph-server" "${MY_APIC_GRAPHQL_DIR}" "${lf_in_target_directory}" "stepzen-route.yaml" "$VAR_APIC_GRAPHQL_NAMESPACE"

    # Set up stepzen-graph-server and stepzen-graph-server-subscriptions routes for the graphql account.
    # This is the default account for serving application requests.
    adapt_file ${MY_RESOURCESDIR} ${lf_in_target_directory} graphql-route.yaml
    if ! oc apply -f "${lf_in_target_directory}graphql-route.yaml" ; then
      unset VAR_CLUSTER_DOMAIN
      trace_out 2 install_apic_graphql
      exit 1
    fi

    # Install Introspection service
    adapt_file ${MY_RESOURCESDIR} ${lf_in_target_directory} introspection.yaml
    if ! oc apply -f "${lf_in_target_directory}introspection.yaml" ; then
      trace_out 2 install_apic_graphql
      exit 1
    fi

    # unset exported needed variables
    #unset VAR_APIC_GRAPHQL_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I APIC Graphql [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_apic_graphql
}


################################################
# Install IBM Event streams
function install_es() {
  trace_in 2 install_es

  local lf_in_target_directory="$1"
  decho 3 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide one argument:  namespace"
    trace_out 2 install_es
    exit  1
  fi

  # ibm-eventstreams
  if $MY_ES; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I Eventstreams Operator [started : $lf_starting_date]." 0

    check_directory_exist_create "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    # SB]20250221 : problem with IBM Eventstreams, the command oc ibm-pak list does not return the "latest" version of the pak
    # this command used in lib.sh to return the latest version of the pak: lf_app_version=$(oc ibm-pak list --case-name $lf_in_case_name -o json | jq --arg v "$lf_in_case_version" '.versions[$v].appVersion')
    # when used with "latest" returns null, so we need to set the version of the pak in the variable MY_ES_VERSION
    check_add_cs_ibm_pak $MY_ES_CASE $MY_ES_OPERATOR amd64
    if [[ -z $MY_ES_VERSION ]]; then
      export MY_ES_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating EventStreams operator subscription
    create_operator_instance "${MY_ES_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I Eventstreams Operator [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_es
}

################################################
# Install EEM
function install_eem() {
  trace_in 2 install_eem

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_eem
    exit  1
  fi

  if $MY_EEM; then
    # export here all needed variables
    export VAR_EEM_NAMESPACE=$lf_in_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    local lf_varb64
    mylog info "==== Installing CP4I Event Endpoint Management [started : $lf_starting_date]." 0

    #check_directory_exist_create "${MY_EEM_WORKINGDIR}"
    check_directory_exist_create "${lf_in_target_directory}"

    ## event endpoint management
    ## to get the name of the pak to use : oc ibm-pak list
    ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
    check_add_cs_ibm_pak $MY_EEM_OPERATOR $MY_EEM_OPERATOR amd64
    if [[ -z $MY_EEM_VERSION ]]; then
      export MY_EEM_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating Event Endpoint Management operator subscription
    #create_operator_instance "${MY_EEM_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${MY_EEM_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"
    create_operator_instance "${MY_EEM_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"

    # Creating EventEndpointManager instance (Event Processing)
    if $MY_KEYCLOAK_INTEGRATION; then
      export MY_EEM_AUTH_TYPE=INTEGRATION_KEYCLOAK
    else
      export MY_EEM_AUTH_TYPE=LOCAL
    fi

    create_operand_instance "EventEndpointManagement" "${VAR_EEM_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "EEM-Capability.yaml" "$VAR_EEM_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    ## Creating EEM users and roles
    if $MY_KEYCLOAK_INTEGRATION; then
      # generate properties files
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ keycloak-user-roles
      # keycloak user roles
      local lf_varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/keycloak-user-roles.yaml" | base64 -w0)
      oc -n $VAR_EEM_NAMESPACE patch secret "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]"
    else
      # generate properties files
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ local-user-credentials.yaml
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ local-user-roles.yaml
      # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
      # local user credentials
      local lf_varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/local-user-credentials.yaml" | base64 -w0)
      oc -n $VAR_EEM_NAMESPACE patch secret "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$lf_varb64\"}]"
      
      # local user roles
      local lf_varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/local-user-roles.yaml" | base64 -w0)
      oc -n $VAR_EEM_NAMESPACE patch secret "${VAR_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]"
    fi
    
    # unset exported needed variables
    #unset VAR_EEM_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I Event Endpoint Management [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi
  
  trace_out 2 install_eem
}

################################################
# Install EGW
function install_egw() {
  trace_in 2 install_egw

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  local lf_in_eem_namespace="$3"

  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|"

  if [[ $# -ne 3 ]]; then
    mylog error "You have to provide 3 arguments:  destination directory, namespace and EEM namespace"
    trace_out 2 install_egw
    exit  1
  fi

  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW; then
    # export here all needed variables
    export VAR_EGW_NAMESPACE=$lf_in_namespace
    export VAR_EEM_NAMESPACE=$lf_in_eem_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I Event Endpoint Gateway [started : $lf_starting_date]." 0

    #check_directory_exist_create "${MY_EGW_WORKINGDIR}"
    check_directory_exist_create "${lf_in_target_directory}"

    export VAR_EEM_MANAGER_GATEWAY_ROUTE=$(oc -n $VAR_EEM_NAMESPACE get eem ${VAR_EEM_INSTANCE_NAME} -o jsonpath='{.status.endpoints[1].uri}')
    create_operand_instance "EventGateway" "${VAR_EGW_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "EG-Capability.yaml" "$VAR_EGW_NAMESPACE" "{.status.conditions[0].type}" "Ready"

    # unset exported needed variables
    #unset VAR_EGW_NAMESPACE VAR_EEM_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I Event Endpoint Gateway [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_egw
}

################################################
# Install EP
function install_ep() {
  trace_in 2 install_ep

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_ep
    exit  1
  fi

  if $MY_EP; then
    # export here all needed variables
    export VAR_EP_NAMESPACE=$lf_in_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    local lf_varb64
    mylog info "==== Installing CP4I Event Processing [started : $lf_starting_date]." 0

    #check_directory_exist_create "${MY_EP_WORKINGDIR}"
    check_directory_exist_create "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_EP_CASE $MY_EP_OPERATOR amd64
    # We have to wait for the packagemanifest to be ready before creating the subscription even if the wait_for_resource returns a value !!!
    #sleep 5
    if [[ -z $MY_EP_VERSION ]]; then
      export MY_EP_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    decho 3 "MY_EP_VERSION=$MY_EP_VERSION"

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    ## Creating Event processing operator subscription
    create_operator_instance "${MY_EP_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"
    
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
      #create_keycloak_client $MY_KEYCLOAK_MASTER_REALM $MY_EP_KEYCLOAK_CLIENTID $MY_KEYCLOAK_USERNAME
      #get_keycloak_secret $MY_KEYCLOAK_MASTER_REALM $MY_EP_KEYCLOAK_CLIENTID $MY_KEYCLOAK_USERNAME

      decho 3 "VAR_KEYCLOAK_SECRET=$VAR_KEYCLOAK_SECRET"
      #export VAR_CLIENTID=$(echo ${VAR_EP_INSTANCE_NAME}-integration-keycloak-client | base64 -w0)
      export VAR_CLIENTID=$(echo ${VAR_EP_INSTANCE_NAME}-integration-keycloak-client | base64 -w0)
      export VAR_EP_KEYCLOAK_SECRETKEY=$(echo $VAR_KEYCLOAK_SECRET | base64 -w0)
      
      #adapt_file $MY_EP_DIR $MY_EP_WORKINGDIR ep-secret.yaml
      adapt_file $MY_EP_DIR $lf_in_target_directory ep-secret.yaml
      if $MY_APPLY_FLAG; then
        #oc apply -f ${MY_EP_WORKINGDIR}ep-secret.yaml
        oc apply -f ${lf_in_target_directory}ep-secret.yaml
      fi

      create_operand_instance "EventProcessing" "${VAR_EP_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "EP-Capability-oidc.yaml" "$VAR_EP_NAMESPACE" "{.status.phase}" "Running"

      # wait for eventprocessing secrets to be ready (they are created by the instance)
      wait_for_resource "Secret" "${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles" $VAR_EP_NAMESPACE

      # generate properties files
      #adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-credentials.yaml
      adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-roles.yaml
  
      # user roles
      lf_varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-roles.yaml" | base64 -w0)
      if $MY_APPLY_FLAG; then
        oc -n $VAR_EP_NAMESPACE patch secret ${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles --type=merge -p "{\"data\":{\"user-mapping.json\":\"$lf_varb64\"}}"
  
        local lf_path="{.status.phase}"
        local lf_state="Running"

        if oc -n $VAR_EP_NAMESPACE get $lf_type $lf_cr_name >/dev/null 2>&1; then
          wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $VAR_EP_NAMESPACE get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
        else
          mylog error "$lf_cr_name of type $lf_type in $VAR_EP_NAMESPACE namespace does not exist, will not wait for state"
        fi
  
        # patch the keycloak client to add redirectUris
        patch_keycloak_client EventProcessing $lf_cr_name $MY_KEYCLOAK_CP4I_REALM ${VAR_EP_INSTANCE_NAME}-integration-keycloak-client $MY_KEYCLOAK_USERNAME $VAR_EP_NAMESPACE
      fi

    else
      export MY_EP_AUTH_TYPE=LOCAL
      create_operand_instance "EventProcessing" "${VAR_EP_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "EP-Capability.yaml" "$VAR_EP_NAMESPACE" "{.status.phase}" "Running"
  
      # wait for eventprocessing secrets to be ready (they are created by the instance)
      wait_for_resource "Secret" "${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles" $VAR_EP_NAMESPACE
      wait_for_resource "Secret" "${VAR_EP_INSTANCE_NAME}-ibm-ep-user-credentials" $VAR_EP_NAMESPACE

      # generate properties files
      adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-credentials.yaml
      adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-roles.yaml
  
      # user credentials
      local lf_varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-credentials.yaml" | base64 -w0)
      if $MY_APPLY_FLAG; then
        oc -n $VAR_EP_NAMESPACE patch secret ${VAR_EP_INSTANCE_NAME}-ibm-ep-user-credentials --type=merge -p "{\"data\":{\"user-mapping.json\":\"$lf_varb64\"}}"
      fi
  
      # user roles
      lf_varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-roles.yaml" | base64 -w0)
      if $MY_APPLY_FLAG; then
        oc -n $VAR_EP_NAMESPACE patch secret ${VAR_EP_INSTANCE_NAME}-ibm-ep-user-roles --type=merge -p "{\"data\":{\"user-mapping.json\":\"$lf_varb64\"}}"
      fi
    fi

    # unset exported needed variables
    #unset VAR_EP_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I Event Processing [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_ep
}

################################################
# Install Flink
function install_flink() {
  trace_in 2 install_flink

  local lf_in_target_directory="$1"
  local lf_in_namespace="$2"
  decho 3 "Parameters:\"$1\"|\"$2\"|"

  if [[ $# -ne 2 ]]; then
    mylog error "You have to provide 2 arguments:  destination directory and namespace"
    trace_out 2 install_flink
    exit  1
  fi

  if $MY_FLINK; then
    # export here all needed variables
    export VAR_FLINK_NAMESPACE=$lf_in_namespace

    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I Flink [started : $lf_starting_date]." 0

    check_directory_exist_create "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    ## SB]20231020 For Flink and Event processing first you have to apply the catalog source to your cluster :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter Applying catalog sources to your cluster
    # event flink
    check_add_cs_ibm_pak $MY_FLINK_CASE $MY_FLINK_OPERATOR amd64
    # We have to wait for the packagemanifest to be ready before creating the subscription even if the wait_for_resource returns a value !!!
    #sleep 10
    if [[ -z $MY_FLINK_VERSION ]]; then
      export MY_FLINK_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    ## SB]20231020 For Flink and Event processing install the operator with the following command :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter : Install the operator by using the CLI (oc ibm-pak)
    ## event flink
    ## Creating Eventautomation Flink operator subscription
    ## Creating Event processing operator subscription
    create_operator_instance "${MY_FLINK_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"

    ## Creation of Event automation Flink PVC and instance
    # Even if it's a pvc we use the same generic function
    create_operand_instance "PersistentVolumeClaim" "ibm-flink-pvc" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "EA-Flink-PVC.yaml" "$VAR_FLINK_NAMESPACE" "{.status.phase}" "Bound"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [[ -z $MY_FLINK_VERSION ]]; then
      export MY_FLINK_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_FLINK_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    ## SB]20231023 to check the status of created Flink instance : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The status field displays the current state of the FlinkDeployment custom resource.
    ## When the Flink instance is ready, the custom resource displays status.lifecycleState: STABLE and status.jobManagerDeploymentStatus: READY.
    ## STANLE and READY (uppercase!!!)
    create_operand_instance "FlinkDeployment" "${VAR_FLINK_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${lf_in_target_directory}" "EA-Flink-Capability.yaml" "$VAR_FLINK_NAMESPACE" "{.status.lifecycleState}-{.status.jobManagerDeploymentStatus}" "STABLE-READY"

    # unset exported needed variables
    #unset VAR_FLINK_NAMESPACE

    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I flink [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_flink
}

################################################
# Install bboth flink and Event processing in this order
function install_flink_ep() {
  trace_in 2 install_flink_ep

  install_flink "${MY_FLINK_WORKINGDIR}" "$VAR_FLINK_NAMESPACE"

  install_ep "${MY_EP_WORKINGDIR}" "$VAR_EP_NAMESPACE"

  trace_out 2 install_flink_ep
}

################################################
# Install Aspera HSTS
function install_hsts() {
  trace_in 2 install_hsts

  # ibm aspera hsts
  if $MY_HSTS; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I HSTS [started : $lf_starting_date]." 0

    check_directory_exist_create "${VAR_HSTS_WORKINGDIR}"

    # Asperac License
    export MY_ASPERA_LICENSE_FILE="${MY_PRIVATEDIR}aspera-license"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_HSTS_CASE $MY_HSTS_OPERATOR amd64
    if [[ -z $MY_HSTS_VERSION ]]; then
      export MY_HSTS_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi


    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating Aspera HSTS operator subscription
    create_operator_instance "${MY_HSTS_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${VAR_HSTS_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    # Creating Aspera HSTS operand
    create_operand_instance "IbmAsperaHsts" "${VAR_HSTS_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_HSTS_WORKINGDIR}" "AsperaHSTS-Capability.yaml" "$VAR_HSTS_NAMESPACE" "{.status.conditions[0].type}" "Ready"
    
    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I HSTS [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_hsts
}

################################################
# Install MQ
function install_mq() {
  trace_in 2 install_mq

  local lf_in_target_directory="$1"
  decho 3 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide one argument:  destination directory"
    trace_out 2 install_mq
    exit  1
  fi

  # ibm-mq
  if $MY_MQ; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing CP4I MQ operator [started : $lf_starting_date]." 0

    check_directory_exist_create "${lf_in_target_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_MQ_CASE $MY_MQ_OPERATOR amd64
    if [[ -z $MY_MQ_VERSION ]]; then
      export MY_MQ_VERSION=$VAR_APP_VERSION
      unset VAR_APP_VERSION
    fi

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # Creating MQ operator subscription
    create_operator_instance "${MY_MQ_OPERATOR}" "${lf_catalog_source_name}" "${MY_OPERATORSDIR}" "${lf_in_target_directory}" "${MY_OPERATORS_NAMESPACE}"
    
    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of CP4I MQ operator [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_mq
}

################################################
# Install Instana
# Voir ceci dans CP4I 16.1.1 : With the release of Cloud Pak for Integration 16.1.1 , Instana agents are now included in the Cloud Pak for Integration package. 
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.1.1?topic=planning-licensing#instana__title__1
function install_instana() {
  trace_in 2 install_instana

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA; then
    SECONDS=0
    local lf_starting_date=$(date)

    mylog info "==== Installing Instana [started : $lf_starting_date]." 0
    
    # SB]20240629 Instana Agent key
    export MY_INSTANA_AGENT_KEY=$(cat "${MY_PRIVATEDIR}instana_agent_key.txt")
    export MY_INSTANA_EP_HOST=ingress-orange-saas.instana.io
    export MY_INSTANA_ZONE_NAME="${MY_USER_EMAIL%@*}"

    check_directory_exist_create "${MY_INSTANA_WORKINGDIR}"

    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    create_project "$MY_INSTANA_AGENT_NAMESPACE" "$MY_INSTANA_AGENT_NAMESPACE project" "For monitoring with Instana" "${MY_RESOURCESDIR}" "${MY_INSTANA_WORKINGDIR}"

    oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy add-scc-to-user privileged -z instana-agent

    # Create a subscription object for instana Operator
    create_operator_instance "${MY_INSTANA_OPERATOR}" "${MY_CERTIFIED_OPERATORS_CATALOG}" "${MY_OPERATORSDIR}" "${MY_INSTANA_WORKINGDIR}" "${MY_OPERATORS_NAMESPACE}"

    # Creating Instana agent
    create_operand_instance "daemonset" "${MY_INSTANA_INSTANCE_NAME}" "${MY_OPERANDSDIR}" "${MY_INSTANA_WORKINGDIR}" "Instana-Agent-CloudIBM-Capability.yaml" "$MY_INSTANA_AGENT_NAMESPACE" "{.status.numberReady}" "${MY_CLUSTER_WORKERS}"
    
    local lf_duration=$SECONDS
    local lf_ending_date=$(date)

    mylog info "==== Installation of Instana [ended : $lf_ending_date and took : $SECONDS seconds]." 0
  fi

  trace_out 2 install_instana
}

################################################
# Customise ldap adding users and groups
function customise_openldap() {
  trace_in 2 customise_openldap

  if $MY_LDAP_CUSTOM; then
    mylog info "==== Customise ldap ()." 0
    read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
    check_file_exist ${MY_YAMLDIR}ldap/ldap_config.json

    # launch custom script
    mylog info "Customise ldap (ldap.config.sh)."
    ${MY_LDAP_SCRIPTDIR}scripts/ldap.config.sh --call ldap_run_all
  fi

  trace_out 2 customise_openldap
}

################################################
# Customise Open Liberty
function customise_openliberty() {
  trace_in 2 customise_openliberty

  # backend J2EE applications
  if $MY_OPENLIBERTY_CUSTOM; then
    mylog info "==== Customise Open Liberty (olp.config.sh)." 0
    ${MY_OPENLIBERTY_SCRIPTDIR}scripts/olp.config.sh --call olp_run_all
  fi

  trace_out 2 customise_openliberty
}

################################################
# Customise WebSphere Liberty
function customise_wasliberty() {
  trace_in 2 customise_wasliberty

  if $MY_WASLIBERTY_CUSTOM; then
    mylog info "==== Customise WAS Liberty (was.config.sh)." 0
    ${MY_WASLIBERTY_SCRIPTDIR}scripts/was.config.sh --call was_run_all
  fi

  trace_out 2 customise_wasliberty
}

################################################
# Customise ACE
function customise_ace() {
  trace_in 2 customise_ace

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_ACE_CUSTOM; then
    mylog info "==== Customise ACE (ace.config.sh)." 0
    ${MY_ACE_SCRIPTDIR}scripts/ace.config.sh --call ace_run_all
  fi

  trace_out 2 customise_ace
}

################################################
# Customise APIC
function customise_apic() {
  trace_in 2 customise_apic

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_APIC_CUSTOM; then
    mylog info "==== Customise APIC (apic.config.sh)." 0
    ${MY_APIC_SCRIPTDIR}scripts/apic.config.sh --call apic_run_all
  fi

  trace_out 2 customise_apic
}

################################################
# Customise IBM Event streams
function customise_es() {
  trace_in 2 customise_es

  local lf_in_namespace="$1"
  decho 3 "Parameters:\"$1\"|"

  if [[ $# -ne 1 ]]; then
    mylog error "You have to provide one argument: namespace"
    trace_out 2 customise_es
    exit  1
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
  if $MY_ES_CUSTOM; then
    mylog info "==== Customise Event Streams (es.config.sh)." 0

    check_directory_exist_create "${MY_ES_WORKINGDIR}"

    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    check_directory_exist_create "${MY_ES_GEN_CUSTOMDIR}scripts"
    check_directory_exist_create "${MY_ES_GEN_CUSTOMDIR}config"
    generate_files $MY_ES_SCRIPTDIR $MY_ES_GEN_CUSTOMDIR false

    # SB]20231211 https://ibm.github.io/event-automation/es/installing/installing/
    # Question : Do we have to create this configmap before installing ES or even after ? Used for monitoring
    create_oc_resource "ConfigMap" "${MY_MONITORING_CM_NAME}" "${MY_RESOURCESDIR}" "${MY_ES_WORKINGDIR}" "openshift-monitoring-cm.yaml" "$MY_OPENSHIFT_MONITORING_NAMESPACE"

    ${MY_ES_SCRIPTDIR}scripts/es.config.sh --call es_run_all
  fi

  trace_out 2 customise_es
}

################################################
# Customise EEM
function customise_eem() {
  trace_in 2 customise_eem

  if $MY_EEM_CUSTOM; then
    mylog info "==== Customise Event Endpoint Management (eem.config.sh)." 0
    # launch custom script
    ${MY_EEM_SCRIPTDIR}scripts/eem.config.sh --call eem_run_all
  fi

  trace_out 2 customise_eem
}

################################################
# Customise EGW
function customise_egw() {
  trace_in 2 customise_egw

  if $MY_EGW_CUSTOM; then
    mylog info "==== Customise Event Endpoint Gateway ()." 0
  fi

  trace_out 2 customise_egw
}

################################################
# Customise EP
function customise_ep() {
  trace_in 2 customise_ep

  local lf_in_ns="$1"
  decho 3 "Parameters:\"$1"

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  ## Creating Event Processing users and roles
  if $MY_EP_CUSTOM; then
    mylog info "==== Customise Event Endpoint Processing ()." 0
    # launch custom script
  fi

  trace_out 2 customise_ep
}

################################################
# Customise Flink
function customise_flink() {
  trace_in 2 customise_flink

  local lf_in_ns="$1"
  decho 3 "Parameters:\"$1"

  if $MY_FLINK_CUSTOM; then
    mylog info "==== Customise Flink ()." 0
  fi

  trace_out 2 customise_flink
}

################################################
# Customise Aspera HSTS
function customise_hsts() {
  trace_in 2 customise_hsts

  # ibm aspera hsts
  if $MY_HSTS_CUSTOM; then
    mylog info "==== Customise HSTS ()." 0
  fi

  trace_out 2 customise_hsts
}

################################################
# Customise MQ
function customise_mq() {
  trace_in 2 customise_mq

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_MQ_CUSTOM; then
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [[ -z $MY_MQ_VERSION ]]; then
      export MY_MQ_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_MQ_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # launch custom script
    ${MY_MQ_SCRIPTDIR}scripts/mq.config.sh --call mq_run_all
  fi

  trace_out 2 customise_mq
}

################################################
# Customise Instana
function customise_instana() {
  trace_in 2 customise_instana

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA_CUSTOM; then
    mylog info "==== Customise Instana ()." 0
  fi

  trace_out 2 customise_instana
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
  trace_in 2 create_edb_postgres_db

  local lf_in_cluster_name="$1"
  local lf_in_db_name="$2"
  local lf_in_db_username="$3"
  local lf_in_db_password="$4"
  local lf_in_secret_name="$5"
  local lf_in_db_description="$6"
  decho 3 "Parameters:\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5\"|\"$6\"|"
  
  check_directory_exist_create "${VAR_EDB_POSTGRES_WORKINGDIR}"

  create_project "$VAR_POSTGRES_NAMESPACE" "EDB PostGreSQL" "EDB PostGreSQL DB namespace" "${MY_RESOURCESDIR}" "${VAR_EDB_POSTGRES_WORKINGDIR}"

  # Create a PostGreSQL DB secret
  export VAR_SECRET_NAME=$lf_in_secret_name
  export VAR_PROJECT=$VAR_POSTGRES_NAMESPACE
  export VAR_USERNAME=$lf_in_db_username
  export VAR_PASSWORD=$lf_in_db_password
  
  create_oc_resource "Secret" "${lf_in_secret_name}" "${MY_RESOURCESDIR}" "${VAR_EDB_POSTGRES_WORKINGDIR}" "secret.yaml" "$VAR_POSTGRES_NAMESPACE"
  unset VAR_SECRET_NAME VAR_PROJECT VAR_USERNAME VAR_PASSWORD

  # PostGreSQL DB
  export VAR_POSTGRES_CLUSTER="${lf_in_cluster_name}"
  export VAR_POSTGRES_DATABASE="${lf_in_db_name}"
  export VAR_POSTGRES_USER="${lf_in_db_username}"
  export VAR_POSTGRES_SECRET="${lf_in_secret_name}"
  export VAR_POSTGRES_DATABASE_DESCRIPTION="${lf_in_db_description}"

  # the following command to be used with ibm postgres
  # export VAR_POSTGRES_IMAGE_NAME=$(oc get packagemanifests -n $MY_CATALOGSOURCES_NAMESPACE --selector=$MY_POSTGRES_CATALOGSOURCE_NAME -o json | jq --arg channel "$MY_POSTGRES_CHL" '.items[].status.channels[] | select(.name == $channel)' | jq -r '.currentCSVDesc.relatedImages[]   | select(startswith("icr.io/cpopen/edb/postgresql:"))' | sort -V | tail -n 1)

  # and this with EDB Postgres
  export VAR_POSTGRES_IMAGE_NAME=$(oc get packagemanifests -n $MY_CATALOGSOURCES_NAMESPACE --selector=$MY_POSTGRES_CATALOGSOURCE_NAME -o json | jq --arg channel "$MY_POSTGRES_CHL" '.items[].status.channels[] | select(.name == $channel)' | jq -r '.currentCSVDesc.relatedImages[]')
  create_operand_instance "Cluster" "${lf_in_cluster_name}" "${MY_POSTGRES_DIR}" "${VAR_EDB_POSTGRES_WORKINGDIR}" "edb-postgres-cluster.yaml" "$VAR_POSTGRES_NAMESPACE" "{.status.conditions[?(@.type=="Ready")].status}" "True"
  unset VAR_POSTGRES_CLUSTER VAR_POSTGRES_DATABASE VAR_POSTGRES_USER VAR_POSTGRES_SECRET VAR_POSTGRES_DATABASE_DESCRIPTION VAR_POSTGRES_IMAGE_NAME
  
  # Authorize superuser access
  oc -n $VAR_POSTGRES_NAMESPACE patch $lf_type $lf_cr_name --type=merge -p '{"spec":{"enableSuperuserAccess":true}}' | awk '{printf "%*s%s\n", NR * $SC_SPACES_COUNTER, "", $0}'

  # Here after how to check the status of the PostGreSQL DB and connect to it
  # oc run pg-check --image=postgres:15 --restart=Never -- sleep 3600
  # oc exec -it pg-check -- bash
  # psql -h <postgresql_svc> -U <postgres_user> -d <database_name> // password is asked
  # \q to quit

  trace_out 2 create_edb_postgres_db
}

################################################
# Display information to access CP4I
function display_access_info() {
  # To start displaying access info from the start of the line
  SC_SPACES_COUNTER=0
  trace_in 2 display_access_info

  mylog info "==== Displaying Access Info to CP4I." 0

  # Initialisation of the bookmark
  echo ${BOOKMARK_PROLOGUE} > ${MY_WORKINGDIR}/bookmarks.html

  # Temporary access with Keycloack

  local lf_mailhog_hostname
  lf_mailhog_hostname=$(oc -n ${VAR_MAIL_SERVER_NAMESPACE} get route mailhog -o jsonpath='{.spec.host}')
  mylog info "MailHog accessible at http://${lf_mailhog_hostname}"
  echo "<DT><A HREF=http://${lf_mailhog_hostname}>MailHog</A>" >> ${MY_WORKINGDIR}/bookmarks.html

  lf_keycloak_admin_ui=$(oc -n $MY_COMMONSERVICES_NAMESPACE get route keycloak --template='{{ .spec.host }}')
  mylog info "Keycloak admin UI URL: " $lf_keycloak_admin_ui
  echo "<DT><A HREF=https://${lf_keycloak_admin_ui}>Keycloak Admin UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  lf_keycloak_admin_pwd=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret cs-keycloak-initial-admin -o jsonpath={.data.password} | base64 -d)
  mylog info "Keycloak admin password: " $lf_keycloak_admin_pwd
  
  local lf_temp_integration_admin_pwd cp4i_url
  if $MY_NAVIGATOR_INSTANCE; then
    lf_temp_integration_admin_pwd=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret integration-admin-initial-temporary-credentials -o jsonpath={.data.password} | base64 -d)
    mylog info "Integration admin password: ${lf_temp_integration_admin_pwd}"
    cp4i_url=$(oc -n $VAR_NAVIGATOR_NAMESPACE get platformnavigator cp4i-navigator -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
    mylog info "CP4I Platform UI URL: " $cp4i_url
    echo "<DT><A HREF=${cp4i_url}>CP4I Platform UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html 
  fi

  local lf_ace_ui_db_url lf_ace_ui_dg_url
  if $MY_ACE; then
    lf_ace_ui_db_url=$(oc -n $VAR_ACE_NAMESPACE get Dashboard -o=jsonpath='{.items[?(@.kind=="Dashboard")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Dahsboard UI endpoint: " $lf_ace_ui_db_url
    echo "<DT><A HREF=${lf_ace_ui_db_url}>ACE Dashboard UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_ace_ui_dg_url=$(oc -n $VAR_ACE_NAMESPACE get DesignerAuthoring -o=jsonpath='{.items[?(@.kind=="DesignerAuthoring")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Designer UI endpoint: " $lf_ace_ui_dg_url
    echo "<DT><A HREF=${lf_ace_ui_dg_url}>ACE Designer UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  fi

  local lf_gtw_url lf_apic_gtw_admin_pwd_secret_name lf_cm_admin_pwd lf_cm_url lf_cm_admin_pwd_secret_name lf_cm_admin_pwd lf_mgr_url lf_ptl_url lf_jwks_url
  if $MY_APIC; then
    lf_gtw_url=$(oc -n $VAR_APIC_NAMESPACE get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "APIC Gateway endpoint: ${lf_gtw_url}"
    lf_gtw_webconsole_url=$(oc -n $VAR_APIC_NAMESPACE get Route ${VAR_APIC_GW_ROUTE_NAME} -o=jsonpath='{.spec.host}')
    mylog info "APIC Gateway web console endpoint: https://${lf_gtw_webconsole_url}"
    echo "<DT><A HREF=https://${lf_gtw_webconsole_url}>APIC Gateway Web Console</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_apic_gtw_admin_pwd_secret_name=$(oc -n $VAR_APIC_NAMESPACE get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].spec.adminUser.secretName}')
    lf_cm_admin_pwd=$(oc -n $VAR_APIC_NAMESPACE get secret ${lf_apic_gtw_admin_pwd_secret_name} -o jsonpath={.data.password} | base64 -d)
    mylog info "APIC Gateway admin password: ${lf_cm_admin_pwd}"
    lf_cm_url=$(oc -n $VAR_APIC_NAMESPACE get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "APIC Cloud Manager endpoint: ${lf_cm_url}"
    echo "<DT><A HREF=${lf_cm_url}>APIC Cloud Manager UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_cm_admin_pwd_secret_name=$(oc -n $VAR_APIC_NAMESPACE get ManagementCluster -o=jsonpath='{.items[?(@.kind=="ManagementCluster")].spec.adminUser.secretName}')
    lf_cm_admin_pwd=$(oc -n $VAR_APIC_NAMESPACE get secret ${lf_cm_admin_pwd_secret_name} -o jsonpath='{.data.password}' | base64 -d)
    mylog info "APIC Cloud Manager admin password: ${lf_cm_admin_pwd}"
    lf_mgr_url=$(oc -n $VAR_APIC_NAMESPACE get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="ui")].uri}')
    echo "<DT><A HREF=${lf_mgr_url}>APIC API Manager UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    mylog info "APIC API Manager endpoint: ${lf_mgr_url}"
    lf_ptl_url=$(oc -n $VAR_APIC_NAMESPACE get PortalCluster -o=jsonpath='{.items[?(@.kind=="PortalCluster")].status.endpoints[?(@.name=="portalWeb")].uri}')
    mylog info "APIC Web Portal root endpoint: ${lf_ptl_url}"
    lf_jwks_url=$(oc -n $VAR_APIC_NAMESPACE get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="jwksUrl")].uri}')
    mylog info "APIC jwksUrl endpoint for EEM: ${lf_jwks_url}"
  fi

  local lf_es_ui_url lf_es_admin_url lf_es_apicurioregistry_url lf_es_restproducer_url lf_es_bootstrap_urls lf_es_admin_pwd
  if $MY_ES; then
    lf_es_ui_url=$(oc -n $VAR_ES_NAMESPACE get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Streams Management UI endpoint: ${lf_es_ui_url}"
    echo  "<DT><A HREF=${lf_es_ui_url}>Event Streams Management UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_es_admin_url=$(oc -n $VAR_ES_NAMESPACE get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "Event Streams Management admin endpoint: ${lf_es_admin_url}"
    lf_es_apicurioregistry_url=$(oc -n $VAR_ES_NAMESPACE get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="apicurioregistry")].uri}')
    mylog info "Event Streams Management apicurio registry endpoint: ${lf_es_apicurioregistry_url}"
    lf_es_restproducer_url=$(oc -n $VAR_ES_NAMESPACE get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.endpoints[?(@.name=="restproducer")].uri}')
    mylog info "Event Streams Management REST Producer endpoint: ${lf_es_restproducer_url}"
    lf_es_bootstrap_urls=$(oc -n $VAR_ES_NAMESPACE get EventStreams -o=jsonpath='{.items[?(@.kind=="EventStreams")].status.kafkaListeners[*].bootstrapServers}')
    mylog info "Event Streams Bootstraps servers endpoints: ${lf_es_bootstrap_urls}"
    lf_es_admin_pwd=$(oc -n $VAR_ES_NAMESPACE get secret es-admin -o jsonpath={.data.password} | base64 -d)
    mylog info "Event Streams UI Credentials: es-admin/${lf_es_admin_pwd}"
  fi

  local lf_eem_ui_url lf_eem_lf_gtw_url
  if $MY_EEM; then
    lf_eem_ui_url=$(oc -n $VAR_EEM_NAMESPACE get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Endpoint Management UI endpoint: ${lf_eem_ui_url}"
    echo  "<DT><A HREF=${lf_eem_ui_url}>Event Endpoint Management UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_eem_lf_gtw_url=$(oc -n $VAR_EEM_NAMESPACE get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "Event Endpoint Management Gateway endpoint: ${lf_eem_lf_gtw_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi

  local lf_ep_ui_url
  if $MY_EP; then
    lf_ep_ui_url=$(oc -n $VAR_EP_NAMESPACE get EventProcessing -o=jsonpath='{.items[?(@.kind=="EventProcessing")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Processing UI endpoint: ${lf_ep_ui_url}"
    echo "<DT><A HREF=${lf_ep_ui_url}>Event Processing UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi
  
  local lf_ldap_hostname lf_ldap_port
  if $MY_LDAP; then
    read_config_file "${MY_YAMLDIR}ldap/ldap_dit.properties"
    lf_ldap_hostname=$(oc -n ${VAR_LDAP_NAMESPACE} get route ${VAR_LDAP_NAMESPACE}-route -o jsonpath='{.spec.host}')
    lf_ldap_port=$(oc -n ${VAR_LDAP_NAMESPACE} get route ${VAR_LDAP_NAMESPACE}-route -o jsonpath='{.spec.port.targetPort}')
    mylog info "LDAP hostname:port: ${lf_ldap_hostname}:${lf_ldap_port}"
    echo  "<DT><A HREF=ldap://${lf_ldap_hostname}:${lf_ldap_port}>LDAP</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    mylog info "LDAP admin dn/password: ${MY_LDAP_ADMIN_DN}/${MY_LDAP_ADMIN_PASSWORD}"
  fi

  local lf_ar_ui_url
  if $MY_ASSETREPO; then
    lf_ar_ui_url=$(oc -n $VAR_ASSETREPO_NAMESPACE get AssetRepository -o=jsonpath='{.items[?(@.kind=="AssetRepository")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Asset Repository UI endpoint: ${lf_ar_ui_url}"
    echo  "<DT><A HREF=${lf_ar_ui_url}>Asset Repository UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  fi

  if $MY_DPGW; then
    mylog info "Datapower Gateway UI endpoint/admin password are the same as : APIC Gateway endpoint/APIC Gateway admin password"
  fi

  local lf_mq_admin_url
  if $MY_MQ; then
    if $MY_MESSAGINGSERVER; then
      lf_mq_qm_url=$(oc -n $VAR_MQ_NAMESPACE get MessagingServer ${VAR_MSGSRV_INSTANCE_NAME} -o jsonpath='{.status.adminUiUrl}')
    fi
    lf_mq_admin_url=$(oc -n $VAR_MQ_NAMESPACE get QueueManager $VAR_MQ_INSTANCE_NAME -o jsonpath='{.status.adminUiUrl}')
    mylog info "MQ Management Console : ${lf_mq_admin_url}"
    echo  "<DT><A HREF=${lf_mq_admin_url}>MQ Management Console</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    local lf_mq_authentication_method=$(oc -n $VAR_MQ_NAMESPACE get qmgr $VAR_MQ_INSTANCE_NAME -o jsonpath='{.spec.web.console.authentication.provider}')
    if [[ $lf_mq_authentication_method == "manual" ]]; then
      #TOTO# : we suppose here that the user is mqadmin !!!!
      lf_mq_admin_password=$(oc -n $VAR_MQ_NAMESPACE get cm $VAR_WEBCONFIG_CM -o jsonpath='{.data.mqwebuser\.xml}' | yq -p=xml -o=json | jq -r '.server.basicRegistry.user[] | select(.["+@name"]=="mqadmin") | .["+@password"]')
      #echo "oc -n $VAR_MQ_NAMESPACE get cm $VAR_WEBCONFIG_CM -o jsonpath='{.data.mqwebuser\.xml}' | yq -p=xml -o=json" #| jq -r '.server.basicRegistry.user[] | select(.["+@name"]=="mqadmin") | .["+@password"]'
      mylog info "MQ Management Console authentication method: $lf_mq_authentication_method|user=mqadmin|password=$lf_mq_admin_password"
      mylog info "MQ admin/password: mqadmin/${lf_mq_admin_password}"
    else
      mylog info "MQ Management Console authentication method: $lf_mq_authentication_method"
    fi
  fi

  local lf_was_liberty_app_demo_url
  if $MY_WASLIBERTY_CUSTOM; then
    lf_was_liberty_app_demo_url=$(oc -n $VAR_WASLIBERTY_NAMESPACE get route demo -o jsonpath='{.status.ingress[0].host}')
    mylog info "WAS Liberty $MY_WASLIBERTY_APP_NAME application URL : https://${lf_was_liberty_app_demo_url}/$MY_WASLIBERTY_APP_NAME"
    echo "<DT><A HREF=https://${lf_was_liberty_app_demo_url}/$MY_WASLIBERTY_APP_NAME>WAS Liberty $MY_WASLIBERTY_APP_NAME application</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  fi

  local lf_licensing_service_url lf_licensing_secret_token lf_licensing_service_reporter_url lf_licensing_reporter_password
  if $MY_LIC_SRV; then
    lf_licensing_service_url=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-licensing-service-instance")].spec.host}')
    mylog info "Licensing service endpoint: https://${lf_licensing_service_url}"
    echo "<DT><A HREF=https://${lf_licensing_service_url}>Licensing Service</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_licensing_secret_token=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get secret ibm-licensing-token -o jsonpath='{.data.token}' | base64 -d)
    mylog info "Licensing service token: ${lf_licensing_secret_token}"
    lf_licensing_service_reporter_url=$(oc -n ${MY_LICENSE_SERVICE_REPORTER_NAMESPACE} get Route ibm-lsr-console -o=jsonpath='{.status.ingress[0].host}')
    mylog info "Licensing service reporter console endpoint: https://${lf_licensing_service_reporter_url}/license-service-reporter/"
    echo "<DT><A HREF=https://${lf_licensing_service_reporter_url}/license-service-reporter/>Licensing Service Reporter</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_licensing_reporter_password=$(oc -n ${MY_LICENSE_SERVICE_REPORTER_NAMESPACE} get secret ibm-license-service-reporter-credentials -o jsonpath='{.data.password}' | base64 -d)
    mylog info "Licensing service reporter credential: license-administrator/${lf_licensing_reporter_password}"
  fi

  echo ${BOOKMARK_EPILOGUE} >> ${MY_WORKINGDIR}/bookmarks.html

  trace_out 2 display_access_info
}

################################################
# function for the installtion of needed resources
# namespaces, operatorgroup, entitlement, ...
################################################
function install_needed_resources_part() {
  trace_in 2 install_needed_resources_part

  # check the differents pre requisites
  check_exec_prereqs
  check_resource_exist storageclass $MY_BLOCK_STORAGE_CLASS
  check_resource_exist storageclass $MY_FILE_STORAGE_CLASS
  check_directory_exist_create "$MY_WORKINGDIR"

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
  check_directory_exist_create "${MY_CP4I_WORKINGDIR}"

  create_project "$MY_OC_PROJECT" "$MY_OC_PROJECT project" "For the Cloud Pak for Integration" "${MY_RESOURCESDIR}" "${MY_CP4I_WORKINGDIR}"

  # Add ibm entitlement key to namespace
  # SB]20230209 Aspera hsts service cannot be created because a problem with the entitlement, it must be added in the openshift-operators namespace.
  mylog info "Creating entitlement, need to check if it is needed or works"
  add_ibm_entitlement $MY_OC_PROJECT
  add_ibm_entitlement $MY_OPERATORS_NAMESPACE

  # Create a namespace object for Red Hat Openshift Logging Operator 5 I put it here because it's used by loki and observability)
  create_project "${MY_LOGGING_NAMESPACE}" "${MY_LOGGING_NAMESPACE} project" "For Red Hat Openshift Logging Operator" "${MY_RESOURCESDIR}" "${MY_CP4I_WORKINGDIR}"
  oc patch namespace ${MY_LOGGING_NAMESPACE} -p '{"metadata": {"annotations": {"openshift.io/node-selector": ""}}}'
  oc patch namespace ${MY_LOGGING_NAMESPACE} -p '{"metadata": {"labels": {"openshift.io/cluster-logging": "true"}}}'
  oc patch namespace ${MY_LOGGING_NAMESPACE} -p '{"metadata": {"labels": {"openshift.io/cluster-monitoring": "true"}}}'

  # The first method to get the cluster domain
  #lf_url=$(oc get infrastructure cluster -o jsonpath='{.status.apiServerURL}')
  #export VAR_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1)
  #export VAR_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1 | cut -d'.' -f2-)

  # get the dns name which will be used for certficate generation and other usages
  export VAR_CLUSTER_DOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
  export VAR_SAN_DNS="*.${VAR_CLUSTER_DOMAIN}"
  export VAR_COMMON_NAME=$VAR_SAN_DNS
  
  trace_out 2 install_needed_resources_part
}

################################################
# function for the installtion part of the script
################################################
function install_part() {
  trace_in 1 install_part

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
  install_mailhog
  install_openldap
  install_sftp
  
  #SB]20231214 Installing pre requisite services
  install_lic_svc
  install_lic_reporter_svc
  install_fs
  
  # install_xxx: For each capability install : case, operator, operand
  
  # install_openliberty
  install_wasliberty "${MY_WASLIBERTY_WORKINGDIR}" "$VAR_WASLIBERTY_NAMESPACE"
  
  # CP4I Components
  install_navigator "${MY_NAVIGATOR_WORKINGDIR}" "$VAR_NAVIGATOR_NAMESPACE"
  install_assetrepo "${MY_ASSETREPO_WORKINGDIR}" "$VAR_ASSETREPO_NAMESPACE"
  install_intassembly "${MY_INTASSEMBLY_WORKINGDIR}" "$VAR_INTASSEMBLY_NAMESPACE"
  install_ace "${MY_ACE_WORKINGDIR}" "$VAR_ACE_NAMESPACE"
  install_apic "${MY_APIC_WORKINGDIR}" "$VAR_APIC_NAMESPACE"
  install_es "${MY_ES_WORKINGDIR}"
  install_eem "${MY_EEM_WORKINGDIR}" "$VAR_EEM_NAMESPACE"
  install_egw "${MY_EGW_WORKINGDIR}" "$VAR_EGW_NAMESPACE" "$VAR_EEM_NAMESPACE"

  # https://ibm.github.io/event-automation/ep/installing/overview/, there is an installation order, flink then event processing
  # so we created a function to call them in the right order
  install_flink_ep
  install_hsts
  install_mq "${MY_MQ_WORKINGDIR}"
  install_instana
  install_apic_graphql "${MY_APIC_GRAPHQL_WORKINGDIR}" "$VAR_APIC_GRAPHQL_NAMESPACE"
  install_cluster_monitoring

  #test_keycloak

  trace_out 1 install_part
}

################################################
# function for the customization part of the script
################################################
function customise_part() {
  trace_in 1 customise_part

  customise_openldap
  
  # customise_openliberty
  
  customise_wasliberty
  
  customise_ace
  customise_apic
  customise_es $VAR_ES_NAMESPACE
  customise_eem
  customise_egw
  customise_ep
  customise_flink
  customise_hsts
  customise_mq
  
  customise_instana

  trace_out 1 customise_part
}

################################################
# function to run the whole script
function run_all() {
  trace_in 1 run_all

  # Start installation capabilities
  install_part
  
  # Start customization capabilities
  # No need to customise navigator, intassembly, assetrepo
  customise_part

  trace_out 1 run_all
}

################################################
# main function
# Main logic
function main() {
  trace_in 1 main

  if [[ $# -eq 0 ]]; then
    mylog error "No arguments provided. Use --all or --call function_name parameters, function_name parameters, ...."
    return 1
  fi

  local lf_starting_date=$(date)
  local lf_satrting_date_in_seconds=$(date +%s)
  mylog info "==== Installing CP4I Components [started : $lf_starting_date]." 0

  # Main script logic
  local lf_calls=""  # Initialize calls variable
  local lf_key

  while [[ $# -gt 0 ]]; do
    lf_key="$1"
    case $lf_key in
      --all)
        install_needed_resources_part      
        run_all
        shift
        ;;
      --call)
        install_needed_resources_part
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          lf_calls+="$1 "  # Accumulate all arguments after --call
          shift
        done
        ;;
      *)
        mylog error "Invalid option '$1'. Use --all or --call function_name parameters, function_name parameters, ...."
        trace_out 1 main
        return 1
        ;;
      esac
  done
  lf_calls=$(echo "$lf_calls" | xargs)  # Trim leading/trailing spaces

  # Call processing function if --call was used
  if [[ $lf_key == "--call" ]]; then
    if [[ -n $lf_calls ]]; then
      process_calls "$lf_calls"
    else
      mylog error "No function to call. Use --call function_name parameters, function_name parameters, ...."
      trace_out 1 main
      return 1
    fi
  fi

  local lf_ending_date=$(date)
  local lf_ending_date_in_seconds=$(date +%s)
  local lf_duration=$((lf_ending_date_in_seconds - lf_satrting_date_in_seconds))
  mylog info "==== Installation of CP4I Components. [ended : $lf_ending_date and took : $(($lf_duration / 60)) minutes and $(($lf_duration % 60)) seconds]." 0

  trace_out 1 main
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

export ADEBUG=1
export TECHZONE=false
export TRACELEVEL=2

# SB]20240404 Global Index sequence for incremental output for each function call
export SC_SPACES_COUNTER=0
export SC_SPACES_INCR=2
export SC_SPACES_INCR_INSIDE_FUNCTION=2

sc_parameters="./script-parameters.properties"
sc_provision_constant_properties_file="./properties/cp4i-constants.properties"
sc_provision_variable_properties_file="./properties/cp4i-variables.properties"
sc_user_file="./private/user.properties"
sc_provision_lib_file="./lib.sh"
sc_provision_preambule_file="./preambule.properties"

# load preambule file content
. ${sc_provision_preambule_file}

#trap 'display_access_info' EXIT
# load helper functions
. ${sc_provision_lib_file}

# Read user file properties
read_config_file "$sc_user_file"

# Read all the properties
read_config_file "$sc_parameters"

# Read all the properties
read_config_file "$sc_provision_constant_properties_file"
read_config_file "$sc_provision_variable_properties_file"

######################################################
# main entry
######################################################
main "$@"
