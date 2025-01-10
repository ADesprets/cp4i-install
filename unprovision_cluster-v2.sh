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
# Uninstall Keycloak
function uninstall_keycloak() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_keycloak"

  mylog info "==== Uninstalling Redhat Openshift Keycloak." 1>&2
  local lf_operator_name="$MY_KEYCLOAK_OPERATOR"
  local lf_operator_namespace=$MY_COMMONSERVICES_NAMESPACE
  local lf_operator_chl=$MY_KEYCLOAK_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_KEYCLOAK_OPERATOR
  decho 3 "delete_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho 3 "F:OUT:uninstall_keycloak"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Unnstall SFTP server
function uninstall_sftp() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_sftp"

  mylog info "==== Uninstalling an SFTP server." 1>&2
  mylog info "TODO" 1>&2

  decho 3 "F:OUT:uninstall_sftp"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))

}

################################################
# Uninstall GitOps
function uninstall_gitops() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_gitops"

  # https://docs.openshift.com/gitops/1.12/installing_gitops/installing-openshift-gitops.html

  mylog info "==== Uninstalling Redhat Openshift GitOps." 1>&2
  local lf_operator_name="$MY_GITOPS_OPERATORGROUP"
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_operator_chl=$MY_GITOPS_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_GITOPS_CASE
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  export MY_NAMESPACE=$MY_GITOPS_NAMESPACE
  envsubst <"${MY_RESOURCESDIR}namespace.yaml" | oc delete -f - #|| exit 1
  unset MY_NAMESPACE

  decho 3 "F:OUT:uninstall_gitops"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Uninstall CP4I Cluster Logging : Loki log store
#
function uninstall_logging_loki() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_logging_loki"

  # Openshift Logging
  if $MY_LOGGING_LOKI; then
    mylog info "==== Uninstalling Cluster Logging : Loki log store." 1>&2

    # SB]20241204 Configuring LokiStack log store
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/cluster-logging-loki.html

    # Remove the user from the cluster-admin group
    oc adm groups remove-users cluster-admin $MY_USER

    # Remove the cluster-admin role from the cluster-admin group
    oc adm policy remove-cluster-role-from-group cluster-admin cluster-admin

    # delete LokiStack instance
    local lf_file="${MY_OPERANDSDIR}Loki-Capability.yaml"
    local lf_ns=$MY_LOGGING_NAMESPACE
    local lf_path="{.status.conditions[0].type}"
    local lf_resource="$MY_LOKI_INSTANCE_NAME"
    local lf_state="Ready"
    local lf_type="LokiStack"
    local lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # delete the object storage secret
    local lf_operator_namespace="${MY_LOGGING_NAMESPACE}"
    local lf_type="Secret"
    local lf_cr_name=$MY_LOKI_SECRET
    local lf_yaml_file="${MY_RESOURCESDIR}loki-secret.yaml"
    decho 3 "check_delete_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

    # delete the ObjectBucketClaim in openshift-logging namespace
    local lf_operator_namespace=$MY_LOGGING_NAMESPACE
    local lf_type="ObjectBucketClaim"
    local lf_cr_name=$MY_LOKI_BUCKET_INSTANCE_NAME
    local lf_yaml_file="${MY_RESOURCESDIR}objectbucketclaim.yaml"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

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
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Delete OperatorGroup object for Red Hat Openhsift Logging Operator
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LOGGING_OPERATORGROUP}"
    local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    export MY_OPERATORGROUP=$lf_cr_name
    export MY_NAMESPACE=$lf_namespace  
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_NAMESPACE
    
    # Delete namespace object for Red Hat Openshift Logging Operator
    oc delete -f ${MY_RESOURCESDIR}rhel-logging-namespace.yaml

    # Delete subscription object for Loki Operator    
    local lf_operator_name=$MY_LOKI_OPERATOR
    local lf_operator_namespace="openshift-operators-redhat"
    local lf_operator_chl=$MY_LOKI_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="redhat-operators"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_LOKI_OPERATOR
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Delete Operator group for Loki in all namespaces
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LOKI_OPERATORGROUP}"
    local lf_yaml_file="${MY_RESOURCESDIR}operator-group-all.yaml"
    local lf_namespace="openshift-operators-redhat"
    export MY_OPERATORGROUP=$lf_cr_name
    export MY_NAMESPACE=$lf_namespace  
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_NAMESPACE

    # Delete namespace object for Loki Operator
    oc delete -f ${MY_RESOURCESDIR}loki-namespace.yaml

  fi

  decho 3 "F:OUT:uninstall_logging_loki"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Uninstall Redhat Cluster Observability Operator
# # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview
function uninstall_cluster_observability() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_cluster_observability"

  # Openshift Observability
  if $MY_COO; then
    # Create a subscription object for Cluster Observability Operator
    local lf_operator_name="$MY_COO_OPERATOR"
    local lf_operator_namespace="$MY_OPERATORS_NAMESPACE"
    local lf_operator_chl=$MY_COO_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="redhat-operators"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_COO_OPERATOR
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # SB]20241203 https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/logging/logging-6-0#cluster-role-binding-for-your-service-account
    envsubst <"${MY_RESOURCESDIR}role_binding.yaml" | oc delete -f - #|| exit 1

    # Remove ClusterRole from service account
    oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Delete a ClusterRole for the collector
    oc delete -f "${MY_RESOURCESDIR}collector-ClusterRole.yaml"

    # Delete a service account for the collector
    oc delete sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE
  fi

  decho 3 "F:OUT:uninstall_cluster_observability"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Uninstall Logging ViaQ (Create policies for access, will be replaced by OpenTelemetry)
#
function uninstall_logging_viaq() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_logging_viaq"

  # Openshift Observability
  if $MY_COO; then
    # Delete ClusterLogForwarder CR to configure log forwarding
    envsubst <"${MY_RESOURCESDIR}clusterlogforwarder-viaq.yaml" | oc delete -f - #|| exit 1

    # Delete UIPlugi CR
    envsubst <"${MY_RESOURCESDIR}uiplugin.yaml" | oc delete -f - #|| exit 1

    # Allow the collector’s service account to collect logs
    oc project $MY_LOGGING_NAMESPACE
    oc adm policy remove-cluster-role-from-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy remove-cluster-role-from-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy remove-cluster-role-from-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to write data to the LokiStack CR
    oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Create a service account for the collector
    oc delete sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE
  fi

  decho 3 "F:OUT:uninstall_logging_viaq"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Uninstall Logging OpenTelemetry
# 
function uninstall_logging_otel() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_logging_otel"

  # Openshift Observability
  if $MY_COO; then
    # Bind the ClusterRole to the service account
    oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Create a ClusterLogForwarder CR to configure log forwarding
    envsubst <"${MY_RESOURCESDIR}clusterlogforwarder-otel.yaml" | oc delete -f - #|| exit 1

    # Delete UIPlugin CR 
    decho 3 "install_openshift_monitoring create the UI plugin"
    envsubst <"${MY_RESOURCESDIR}uiplugin.yaml" | oc delete -f - #|| exit 1

    # Remove roles
    oc project $MY_LOGGING_NAMESPACE
    oc adm policy remove-cluster-role-from-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy remove-cluster-role-from-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA
    oc adm policy remove-cluster-role-from-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to write data to the LokiStack CR
    oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Delete a service account for the collector
    oc delete sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE
  fi

  decho 3 "F:OUT:uninstall_logging_otel"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

###############################################
# Uninstall/Configure Redhat Cluster Monitoring
# 
function uninstall_cluster_monitoring() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_cluster_monitoring"

  # Openshift cluster monitoring
  if $MY_CLUSTER_MONITORING; then
    # Create the cluster-monitoring-config cm
    export MY_MONITORING_CM_NAME="cluster-monitoring-config"
    export MY_MONITORING_NAMESPACE="openshift-monitoring"
    envsubst <"${MY_RESOURCESDIR}monitoring-cm.yaml" | oc delete -f - #|| exit 1
  fi

  decho 3 "F:OUT:uninstall_cluster_monitoring"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

##################################################
# Uninstall OADP (OpenShift API for Data Protection)
function uninstall_oadp() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_oadp"

  mylog info "==== Deleting Redhat Openshift OADP." 1>&2

  local lf_operator_name="redhat-oadp-operator"
  local lf_operator_namespace=$MY_OADP_NAMESPACE
  local lf_operator_chl=$MY_OADP_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_OADP_OPERATOR
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  # Operator group for OADP in single namespace
  local lf_type="OperatorGroup"
  local lf_cr_name="${MY_OADP_OPERATORGROUP}"
  local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
  local lf_namespace=$MY_OADP_NAMESPACE
  export MY_OPERATORGROUP=$lf_cr_name
  export MY_NAMESPACE=$lf_namespace  
  check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
  unset MY_OPERATORGROUP MY_NAMESPACE

  # delete namespace $MY_OADP_NAMESPACE
  export MY_NAMESPACE=$MY_OADP_NAMESPACE
  envsubst <"${MY_RESOURCESDIR}namespace.yaml" | oc delete -f - #|| exit 1
  unset MY_NAMESPACE



  decho 3 "F:OUT:uninstall_oadp"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall redhat Pipelines (tekton)
function uninstall_pipelines() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_pipelines"

  # https://docs.openshift.com/pipelines/1.14/install_config/installing-pipelines.html

  mylog info "==== Uninstalling Redhat Openshift Pipelines (tekton)." 1>&2
  local lf_operator_name="$MY_PIPELINES_OPERATORGROUP"
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_operator_chl="latest"
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_PIPELINES_CASE
  decho 3 "delete_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  decho 3 "F:OUT:install_pipelines"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Remove mailhog app from openshift
function uninstall_mailhog() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_mailhog"

  if $MY_MAILHOG; then
    mylog info "==== Uninstalling mailhog (server and client)." 1>&2
    local lf_type="deployment"
    local lf_name="mailhog"

    unexpose_service_mailhog ${lf_name} ${MY_MAIL_SERVER_NAMESPACE} '8025'
    undeploy_mailhog ${lf_type} ${lf_name} ${MY_MAIL_SERVER_NAMESPACE}

    # delete namespace
    delete_namespace ${MY_MAIL_SERVER_NAMESPACE}
  fi

  decho 3 "F:OUT:install_mailhog"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Delete OpenLdap app to openshift
function uninstall_openldap() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_openldap"

  if $MY_LDAP; then
    mylog info "==== Uninstalling OpenLdap." 1>&2
    local lf_type="deployment"
    local lf_name="openldap"

    read_config_file "${MY_YAMLDIR}ldap/ldap.properties"


    #SB]20231207 checks if used directories and files exists
    check_file_exist ${MY_YAMLDIR}ldap/ldap-pvc.main.yaml
    check_file_exist ${MY_YAMLDIR}ldap/ldap-pvc.config.yaml
    check_file_exist ${MY_YAMLDIR}ldap/ldap-config.json
    check_file_exist ${MY_YAMLDIR}ldap/ldap-users.ldif

    unexpose_service_openldap ${lf_name} ${MY_LDAP_NAMESPACE}
    undeploy_openldap ${lf_type} ${lf_name} ${MY_LDAP_NAMESPACE}
    unprovision_persistence_openldap ${MY_LDAP_NAMESPACE}

    # delete namespace
    delete_namespace ${MY_LDAP_NAMESPACE}
  fi

  decho 3 "F:OUT:uninstall_openldap"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Cert Manager
function uninstall_cert_manager() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_cert_manager"

  mylog info "==== Uninstalling Redhat Cert Manager catalog." 1>&2
  # 
  local lf_operator_name="openshift-cert-manager-operator"
  local lf_operator_namespace=$MY_CERTMANAGER_OPERATOR_NAMESPACE
  local lf_operator_chl=$MY_CERT_MANAGER_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="redhat-operators"
  local lf_wait_for_state=true
  local lf_csv_name=$MY_CERTMANAGER_CASE
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="redhat-operators"
  lf_catalogsource_dspname="Red Hat Operators"
  lf_catalogsource_image="registry.redhat.io/redhat/redhat-operator-index:v4.12"
  lf_catalogsource_publisher="Red Hat"
  lf_catalogsource_interval="10m"
  decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
  delete_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

  decho 3 "F:OUT:uninstall_cert_manager"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Licensing Server
function uninstall_lic_srv() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_lic_srv"

  # ibm-license-server
  if $MY_LIC_SRV; then
    mylog info "==== Uninstalling IBM License Server." 1>&2
    
    # Remove license service from the reporter
    mylog info "Remove license service instance" 1>&2
    lf_licensing_service_reporter_url=$(oc -n ${MY_LICENSE_SERVER_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-license-service-reporter")].spec.host}')
    oc -n $MY_LICENSE_SERVER_NAMESPACE delete IBMLicensing instance

    mylog info "Deleting the License Service Reporter instance" 1>&2
    lf_file="${MY_OPERANDSDIR}LIC-Reporter-Capability.yaml"
    lf_ns="${MY_LICENSE_SERVER_NAMESPACE}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_LICENSE_SERVER_REPORTER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IBMLicenseServiceReporter"
    lf_wait_for_state=false
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    mylog info "Uninstalling the License Service Reporter operator" 1>&2
    local lf_operator_name="ibm-license-service-reporter-operator"
    local lf_operator_namespace=$MY_LICENSE_SERVER_NAMESPACE
    local lf_operator_chl=$MY_LIC_SRV_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-license-service-reporter-operator-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_LICENSE_SERVER_REPORTER_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    local lf_operator_name="ibm-licensing-operator-app"
    local lf_operator_namespace=$MY_LICENSE_SERVER_NAMESPACE
    local lf_operator_chl=$MY_LIC_SRV_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-licensing-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_LICENSE_SERVER_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
    lf_catalogsource_name="ibm-license-service-reporter-operator-catalog"
    lf_catalogsource_dspname="IBM License Service Reporter Catalog"
    lf_catalogsource_image="icr.io/cpopen/ibm-license-service-reporter-operator-catalog"
    lf_catalogsource_publisher="IBM"
    lf_catalogsource_interval="45m"
    decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
    delete_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

    lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
    lf_catalogsource_name="ibm-licensing-catalog"
    lf_catalogsource_dspname="ibm-licensing"
    lf_catalogsource_image="icr.io/cpopen/ibm-licensing-catalog"
    lf_catalogsource_publisher="IBM"
    lf_catalogsource_interval="45m"
    decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
    delete_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

    # Operator group for License Service Reporter in single namespace
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LICENSE_SERVER_OPERATORGROUP}"
    local lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
    local lf_namespace=$MY_LICENSE_SERVER_NAMESPACE
    export MY_OPERATORGROUP=$lf_cr_name
    export MY_NAMESPACE=$lf_namespace  
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_NAMESPACE

    check_delete_cs_ibm_pak ibm-licensing amd64

  fi

  decho 3 "F:OUT:uninstall_lic_srv"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

############################################################################################################################################
# Uninstall fs
function uninstall_fs() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_fs"

  mylog info "==== Deleting IBM Common Services." 1>&2
  ## Setting hardware  Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
  #accept_license_fs $MY_OPERATORS_NAMESPACE
  # accept_license_fs $lf_operator_namespace

  # Configuring foundational services by using the CommonService custom resource.
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_type="CommonService"
  local lf_cr_name=$MY_COMMONSERVICES_INSTANCE_NAME
  local lf_yaml_file="${MY_RESOURCESDIR}foundational-services-cr.yaml"
  decho 3 "check_delete_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_operator_namespace}\""
  check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_operator_namespace}"

  local lf_operator_name="ibm-common-service-operator"
  local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
  local lf_operator_chl=$MY_FOUNDATIONALSERVICES_CHL
  local lf_strategy="Automatic"
  local lf_catalog_source_name="opencloud-operators"
  local lf_wait_for_state=true
  local lf_csv_name="ibm-common-service-operator"
  decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
  delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

  lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
  lf_catalogsource_name="opencloud-operators"
  lf_catalogsource_dspname="IBMCS Operators"
  lf_catalogsource_image="icr.io/cpopen/ibm-common-service-catalog:4.3"
  lf_catalogsource_publisher="IBM"
  lf_catalogsource_interval="45m"
  decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
  delete_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

  # ibm-cp-common-services
  check_delete_cs_ibm_pak $MY_COMMONSERVICES_CASE amd64 $MY_COMMONSERVICES_VERSION

  decho 3 "F:OUT:uninstall_fs"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Open Liberty
function uninstall_openliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_openliberty"

  # backend J2EE applications
  if $MY_OPENLIBERTY; then
    mylog info "==== Uninstalling OPEN Liberty." 1>&2

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
    if oc -n ${MY_BACKEND_NAMESPACE} delete ${lf_octype} ${lf_name} >/dev/null 2>&1; then
    else
      mylog info "Deployment ${lf_octype} ${lf_name} in ${MY_BACKEND_NAMESPACE} already deleted"
      oc delete --server-side -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml
      oc delete -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml
      oc -n ${MY_BACKEND_NAMESPACE} delete -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml
    fi

     delete_namespace $MY_BACKEND_NAMESPACE "$MY_BACKEND_NAMESPACE project" "For Open Liberty instances and create custom API"

  fi

  decho 3 "F:OUT:uninstall_openliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall WebSphere Liberty
function uninstall_wasliberty() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_wasliberty"

  if $MY_WASLIBERTY; then
    mylog info "==== Uninstalling WAS Liberty." 1>&2

    # Deleting WebSphere Liberty operator subscription
    local lf_operator_name="ibm-websphere-liberty"
    local lf_operator_namespace=$MY_BACKEND_NAMESPACE
    local lf_operator_chl=$MY_WL_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-operator-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_WL_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Operator group for WAS Liberty in single namespace
    lf_type="OperatorGroup"
    lf_cr_name="${MY_WAS_LIBERTY_OPERATORGROUP}"
    lf_yaml_file="${MY_RESOURCESDIR}operator-group-single.yaml"
    lf_namespace=$MY_BACKEND_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    export MY_OPERATORGROUP=$lf_cr_name
    export MY_NAMESPACE=$lf_namespace  
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_NAMESPACE

    # mylog info "==== Adding IBM Operator catalog source in ns : openshift-marketplace." 1>&2
    lf_catalogsource_namespace=$MY_CATALOGSOURCES_NAMESPACE
    lf_catalogsource_name="ibm-operator-catalog"
    lf_catalogsource_dspname="IBM Operator Catalog"
    lf_catalogsource_image="icr.io/cpopen/ibm-operator-catalog"
    lf_catalogsource_publisher="IBM"
    lf_catalogsource_interval="45m"
    decho 3 "create_catalogsource \"${lf_catalogsource_namespace}\" \"${lf_catalogsource_name}\" \"${lf_catalogsource_dspname}\" \"${lf_catalogsource_image}\" \"${lf_catalogsource_publisher}\" \"${lf_catalogsource_interval}\""
    delete_catalogsource "${lf_catalogsource_namespace}" "${lf_catalogsource_name}" "${lf_catalogsource_dspname}" "${lf_catalogsource_image}" "${lf_catalogsource_publisher}" "${lf_catalogsource_interval}"

    # Delete catalog sources using ibm_pak plugin
    check_delete_cs_ibm_pak $MY_WL_CASE amd64

    delete_namespace $MY_BACKEND_NAMESPACE "$MY_BACKEND_NAMESPACE project" "For WebSphere Application Server (Liberty) instances and create custom API"
  fi

  decho 3 "F:OUT:uninstall_wasliberty"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Navigator (depending on two boolean)
function uninstall_navigator() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_navigator"

  if $MY_NAVIGATOR_INSTANCE; then
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_NAVIGATOR_VERSION" ]; then
      export MY_NAVIGATOR_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_NAVIGATOR_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
      decho 3 "MY_NAVIGATOR_VERSION=$MY_NAVIGATOR_VERSION"
    fi

    # Deleting Navigator instance
    lf_file="${MY_OPERANDSDIR}Navigator-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_NAVIGATOR_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="PlatformNavigator"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  # Deleting Navigator operator subscription
  if $MY_NAVIGATOR; then
    mylog info "==== Uninstalling Navigator." 1>&2
    # Deleting Navigator operator subscription
    local lf_operator_name="$MY_NAVIGATOR_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_NAVIGATOR_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-integration-platform-navigator-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_NAVIGATOR_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # remove catalog sources
    check_delete_cs_ibm_pak $MY_NAVIGATOR_CASE amd64
  fi

  decho 3 "F:OUT:uninstall_navigator"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Asset Repository
function uninstall_assetrepo() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_assetrepo"

  if $MY_ASSETREPO; then
    mylog info "==== Uninstalling Asset Repository." 1>&2

    if $MY_ASSETREPO_INSTANCE; then
      #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
      if [ -z "$MY_ASSETREPO_VERSION" ]; then
        export MY_ASSETREPO_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ASSETREPO_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
        decho 3 "MY_ASSETREPO_VERSION=$MY_ASSETREPO_VERSION"
      fi

      # Deleting Asset Repository instance
      lf_file="${MY_OPERANDSDIR}AR-Capability.yaml"
      lf_ns="${MY_OC_PROJECT}"
      lf_path="{.status.phase}"
      lf_resource="$MY_ASSETREPO_INSTANCE_NAME"
      lf_state="Ready"
      lf_type="AssetRepository"
      lf_wait_for_state=true
      delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
    fi

    # Deleting Asset Repository operator subscription
    local lf_operator_name=$MY_ASSETREPO_CASE
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_ASSETREPO_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-integration-asset-repository-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_ASSETREPO_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # remove catalog sources
    check_delete_cs_ibm_pak $MY_ASSETREPO_CASE amd64

  fi

  decho 3 "F:OUT:uninstall_assetrepo"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Integration Assembly
function uninstall_intassembly() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_intassembly"

  # Deleting Integration Assembly instance
  if $MY_INTASSEMBLY; then
    mylog info "==== Uninstalling Integration Assembly." 1>&2
    lf_file="${MY_OPERANDSDIR}IntegrationAssembly-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_INTASSEMBLY_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IntegrationAssembly"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:uninstall_intassembly"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall ACE
function uninstall_ace() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_ace"

  # ibm-appconnect
  if $MY_ACE; then
    mylog info "==== Uninstalling ACE." 1>&2

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_ACE_VERSION" ]; then
      export MY_ACE_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ACE_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # Deleting ACE Designer instance
    lf_file="${MY_OPERANDSDIR}ACE-Designer-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DESIGNER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="DesignerAuthoring"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Deleting ACE Dashboard instance
    lf_file="${MY_OPERANDSDIR}ACE-Dashboard-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_DASHBOARD_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="Dashboard"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Deleting ACE Switch Server instance (used for callable flows)
    lf_file="${MY_OPERANDSDIR}ACE-SwitchServer-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_ACE_SWITCHSERVER_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="SwitchServer"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Deleting ACE operator subscription
    local lf_operator_name="$MY_ACE_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_ACE_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="appconnect-operator-catalogsource"
    local lf_csv_name=$MY_ACE_CASE
    local lf_wait_for_state=true
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # delete catalog sources using ibm_pak plugin
    check_delete_cs_ibm_pak $MY_ACE_CASE amd64

  fi

  decho 3 "F:OUT:uninstall_ace"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall APIC
function uninstall_apic() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_apic"

  # ibm-apiconnect
  if $MY_APIC; then
    mylog info "==== Uninstalling APIC." 1>&2

    #export MY_NAMESPACE="${MY_OC_PROJECT}"
    #export MY_ROUTE_NAME="${MY_APIC_INSTANCE_NAME}-gw-webconsole"
    #export MY_ROUTE_BALANCE="roundrobin"
    #export MY_ROUTE_INSTANCE="${MY_APIC_INSTANCE_NAME}-gw"
    #export MY_ROUTE_PARTOF="${MY_APIC_INSTANCE_NAME}"
    #export lf_ingress=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
    #export MY_ROUTE_HOST="${MY_ROUTE_NAME}.${lf_ingress}"
    #export MY_ROUTE_PORT=9090
    #export MY_ROUTE_SERVICE=${MY_APIC_INSTANCE_NAME}-gw-datapower
    #decho 3 "${MY_NAMESPACE}, ${MY_ROUTE_NAME}, ${MY_ROUTE_BALANCE}, ${MY_ROUTE_INSTANCE}, ${MY_ROUTE_PARTOF}, ${MY_ROUTE_HOST}, ${MY_ROUTE_PORT}, ${MY_ROUTE_SERVICE}"

    delete_certificate ${MY_OC_PROJECT} cp4i-apic-ingress-ca ca.crt ${MY_WORKINGDIR}
    delete_certificate ${MY_OC_PROJECT} cp4i-apic-gw-gateway ca.crt ${MY_WORKINGDIR}

    local lf_type="Route"
    local lf_cr_name="${MY_APIC_INSTANCE_NAME}-gw-webconsole"
    local lf_yaml_file="${MY_RESOURCESDIR}route.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    #AD/SB]20240703 enable the Gateway Cluster webGui Management and add webgui-port to set it accessible
    mylog info "Delete web console of the API Connect Gateway"
    oc -n "${MY_OC_PROJECT}" delete GatewayCluster "${MY_APIC_INSTANCE_NAME}-gw"
    
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_APIC_VERSION" ]; then
      export MY_APIC_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_APIC_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    if $MY_APIC_BY_COMPONENT; then
      mylog info "HOLD PLACE"
    else
      # Deleting APIC instance
      local lf_file="${MY_OPERANDSDIR}APIC-Capability.yaml"
      local lf_ns="${MY_OC_PROJECT}"
      local lf_path="{.status.phase}"
      local lf_resource="$MY_APIC_INSTANCE_NAME"
      local lf_state="Ready"
      local lf_type="APIConnectCluster"
      local lf_wait_for_state=true
      delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
    fi

    # Deleting APIC operator subscription
    local lf_operator_name="$MY_APIC_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_APIC_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-apiconnect-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_APIC_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # delete catalog sources using ibm_pak plugin
    check_delete_cs_ibm_pak $MY_APIC_CASE amd64

    # Deleting DataPower operator
    lf_type="clusterserviceversion"
    lf_in_csv_name="datapower-operator"
    decho 3 "oc -n $MY_OPERATORS_NAMESPACE get $lf_type -o json | jq -r --arg my_resource \"$lf_in_csv_name\" '.items[].metadata | select (.name | contains ($my_resource)).name'"
    lf_resource=$(oc -n $MY_OPERATORS_NAMESPACE get $lf_type -o json | jq -r --arg my_resource "$lf_in_csv_name" '.items[].metadata | select (.name | contains ($my_resource)).name')
    oc delete csv $lf_resource -n $MY_OPERATORS_NAMESPACE
  fi

  decho 3 "F:OUT:uninstall_apic"
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
    envsubst <"${MY_RESOURCESDIR}self-signed-issuer.yaml" | oc delete -f - #|| exit 1
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
# Uninstall IBM Event streams
function uninstall_es() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_es"

  # ibm-eventstreams
  if $MY_ES; then
    mylog info "==== Uninstalling Event Streams." 1>&2
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_ES_VERSION" ]; then
      export MY_ES_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ES_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # Deleting Event Streams instance
    lf_file="${MY_OPERANDSDIR}ES-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_ES_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventStreams"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Deleting EventStreams operator subscription
    local lf_operator_name="$MY_ES_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_ES_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-eventstreams"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_ES_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # delete catalog sources using ibm_pak plugin
    check_delete_cs_ibm_pak $MY_ES_CASE amd64

  fi

  decho 3  "F:OUT:uninstall_es"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall EEM
function uninstall_eem() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_eem"

  local lf_in_ns=$1
  local varb64

  decho 3 "uninstall_eem: $lf_in_ns"

  if [ -z $lf_in_ns ]; then
    mylog error "Namespace is missing."
    return 1
  fi

  if $MY_EEM; then
    mylog info "==== Uninstalling Event Endpoint Management." 1>&2

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
    
    ## Creating EEM users and roles
    if $MY_KEYCLOAK_INTEGRATION; then
      oc -n $MY_OC_PROJECT delete secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles"
    else
      # local user credentials
      oc -n $MY_OC_PROJECT delete secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials"

      # local user roles
      oc -n $MY_OC_PROJECT delete secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles"
    fi

    lf_file="${MY_OPERANDSDIR}EEM-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EEM_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventEndpointManagement"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Deleting Event Endpoint Management operator subscription
    lf_operator_name="ibm-eventendpointmanagement"
    lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_operator_chl=$MY_EEM_CHL
    lf_strategy="Automatic"
    lf_catalog_source_name="ibm-eventendpointmanagement-catalog"
    lf_wait_for_state=true
    lf_csv_name=$MY_EEM_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    check_delete_cs_ibm_pak $MY_EEM_CASE amd64
  fi
  
  decho 3 "F:OUT:uninstall_eem"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall EGW
function uninstall_egw() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_egw"

  # Deleting EventGateway instance (Event Gateway)
  if $MY_EGW; then
    mylog info "==== Uninstalling Event Endpoint Gateway." 1>&2
    export MY_EEM_MANAGER_GATEWAY_ROUTE=$(oc -n $MY_OC_PROJECT get eem $MY_EEM_INSTANCE_NAME -o jsonpath='{.status.endpoints[1].uri}')

    lf_file="${MY_OPERANDSDIR}EG-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_EGW_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="EventGateway"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
  fi

  decho 3 "F:OUT:uninstall_egw"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall EP
function uninstall_ep() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_ep"

  local lf_in_ns=$1
  local varb64

  if $MY_EP; then
    mylog info "==== Uninstalling Event Processing." 1>&2

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_EP_VERSION" ]; then
      export MY_EP_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_EP_CASE" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # user roles
    oc -n $MY_OC_PROJECT delete secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles"

    # user credentials
    varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-credentials.yaml" | base64 -w0)
    oc -n $MY_OC_PROJECT delete secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials"

    lf_file="${MY_OPERANDSDIR}EP-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="$MY_EP_INSTANCE_NAME"
    lf_state="Running"
    lf_type="EventProcessing"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    ## Deleting Event processing operator subscription
    local lf_operator_name="$MY_EP_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_EP_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-eventprocessing-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_EP_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # add catalog sources using ibm_pak plugin
    check_delete_cs_ibm_pak $MY_EP_CASE amd64
  fi

  decho 3 "F:OUT:uninstall_ep"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Flink
function uninstall_flink() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_flink"

  local lf_in_ns=$1
  if $MY_FLINK; then
    mylog info "==== Uninstalling Flink." 1>&2

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
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    ## Creation of Event automation Flink PVC and instance
    # Even if it's a pvc we use the same generic function
    lf_file="${MY_OPERANDSDIR}EA-Flink-PVC.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.phase}"
    lf_resource="ibm-flink-pvc"
    lf_state="Bound"
    lf_type="PersistentVolumeClaim"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    ## Deleting Event processing operator subscription
    local lf_operator_name="$MY_FLINK_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_FLINK_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibm-eventautomation-flink-catalog"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_FLINK_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    check_delete_cs_ibm_pak $MY_FLINK_CASE amd64
  fi

  decho 3 "F:OUT:uninstall_flink"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Aspera HSTS
function uninstall_hsts() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_hsts"

  # ibm aspera hsts
  if $MY_HSTS; then
    mylog info "==== Uninstalling HSTS." 1>&2

    # Asperac License
    export MY_ASPERA_LICENSE_FILE="${MY_PRIVATEDIR}aspera-license"

    lf_file="${MY_OPERANDSDIR}AsperaHSTS-Capability.yaml"
    lf_ns="${MY_OC_PROJECT}"
    lf_path="{.status.conditions[0].type}"
    lf_resource="$MY_HSTS_INSTANCE_NAME"
    lf_state="Ready"
    lf_type="IbmAsperaHsts"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    # Deleting Aspera HSTS operator subscription
    local lf_operator_name="aspera-hsts-operator"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_HSTS_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="aspera-operators"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_HSTS_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Delete catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_HSTS_CASE amd64

  fi

  decho 3 "F:OUT:uninstall_hsts"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall MQ
function uninstall_mq() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_mq"

  # ibm-mq
  if $MY_MQ; then
    mylog info "==== Uninstalling MQ." 1>&2

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
      delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"
    fi

    # Deleting MQ operator subscription
    local lf_operator_name="$MY_MQ_CASE"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_MQ_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="ibmmq-operator-catalogsource"
    local lf_wait_for_state=true
    local lf_csv_name=$MY_MQ_CASE
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # delete catalog sources
    check_delete_cs_ibm_pak $MY_MQ_CASE amd64

  fi

  decho 3 "F:OUT:uninstall_mq"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall Instana
function uninstall_instana() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_instana"

  # SB]20240629 Instana Agent key
  export MY_INSTANA_AGENT_KEY=$(cat "${MY_PRIVATEDIR}instana_agent_key.txt")
  export MY_INSTANA_EP_HOST=ingress-orange-saas.instana.io
  export MY_INSTANA_ZONE_NAME="${MY_USER_EMAIL%@*}"

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA; then
    mylog info "==== Deleting Instana." 1>&2

    # Deleting Instana agent
    lf_file="${MY_OPERANDSDIR}Instana-Agent-CloudIBM-Capability.yaml"
    lf_ns="${MY_INSTANA_AGENT_NAMESPACE}"
    lf_path="{.status.numberReady}"
    lf_resource="$MY_INSTANA_INSTANCE_NAME"
    lf_state="$MY_CLUSTER_WORKERS"
    lf_type="daemonset"
    lf_wait_for_state=true
    delete_operand_instance "${lf_file}" "${lf_ns}" "${lf_path}" "${lf_resource}" "${lf_state}" "${lf_type}" "${lf_wait_for_state}"

    local lf_operator_name="instana-agent-operator"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$MY_INSTANA_CHL
    local lf_strategy="Automatic"
    local lf_catalog_source_name="certified-operators"
    local lf_csv_name=$MY_INSTANA_CSV_NAME
    local lf_wait_for_state=true
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_wait_for_state}\" \"${lf_csv_name}\""
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Delete Instana agent namespace. 
    oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy remove-scc-from-user privileged -z instana-agent
    delete_namespace $MY_INSTANA_AGENT_NAMESPACE

  fi

  decho 3 "F:OUT:uninstall_instana"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# Uninstall PostGreSQL 
function uninstall_postgresql() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :uninstall_postgresql"

  if $MY_POSTGRESQL; then

   mylog info "==== Deleting PostGreSQL." 1>&2
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
    delete_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_wait_for_state}" "${lf_csv_name}"

    # Delete namespace for PostGreSQL.
    create_namespace $MY_POSTGRESQL_NAMESPACE

    # add catalog sources using ibm_pak plugin
    check_delete_cs_ibm_pak $MY_POSTGRESQL_CASE amd64

  fi

  decho 3 "F:OUT:uninstall_postgresql"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}


################################################
# Delete a PostGreSQL DB
#
function delete_postgresql_db() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :delete_postgresql_db"

  if $MY_POSTGRESQL_DB; then
    
    # PostGreSQL DB
    local lf_type="Cluster"
    local lf_cr_name="${MY_POSTGRESQL_CLUSTER}"
    local lf_yaml_file="${MY_RESOURCESDIR}postgresql-cluster.yaml"
    local lf_namespace=$MY_POSTGRESQL_NAMESPACE
    check_delete_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_yaml_file}" "${lf_namespace}"

    # Delete a PostGreSQL DB secret
    local lf_type="Secret"
    local lf_cr_name="${MY_POSTGRESQL_SECRET}"
    local lf_namespace=$MY_POSTGRESQL_NAMESPACE
    if oc -n ${lf_namespace} get ${lf_type} ${lf_cr_name} >/dev/null 2>&1; then
      oc -n $lf_namespace delete secret $lf_cr_name
    else
      mylog info "Custom Resource $lf_type/$lf_cr_name already deleted"
    fi

    # Delete PostGreSQLnamespace
    #export MY_NAMESPACE=$MY_POSTGRESQL_NAMESPACE
    #envsubst <"${MY_RESOURCESDIR}namespace.yaml" | oc apply -f - || exit 1
    delete_namespace $MY_POSTGRESQL_NAMESPACE    
  fi

  decho 3 "F:OUT:delete_postgresql_db"
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
# function for the uninstalltion part of the script
################################################
function uninstall_part() {
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
  create_postgresql_db

  install_apic_graphql

  install_cluster_monitoring

  decho 3 "F:OUT:install_part"
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER - $SC_SPACES_INCR))
}

################################################
# function to run the whole script
function run_all() {
  SC_SPACES_COUNTER=$((SC_SPACES_COUNTER + $SC_SPACES_INCR))
  decho 3 "F:IN :run_all"

  # Start installation capabilities
  uninstall_part
  
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

      # Extract the function name and parameters
      lf_func=$(echo "$lf_cmd" | awk '{print $1}')
      lf_params=$(echo "$lf_cmd" | awk '{$1=""; sub(/^ /, ""); print}')  # Get all the parameters after the function name
      decho 3 "Function: $lf_func|Parameters: $lf_params"

      # Check if the function exists and call it
      if declare -f "$lf_func" > /dev/null; then
        if [ "$lf_func" = "main" ] || [ "$lf_func" = "process_calls" ]; then
          mylog error "Functions 'main', 'process_calls' cannot be called."
          return 1
        fi
        $lf_func $lf_params
      else
        #SC_SPACES_COUNTER=0
        #SC_SPACES_INCR=0
        mylog error "Function '$lf_func' not found."
        lf_list=$(grep -E '^\s*(function\s+\w+|\w+\s*\(\))' $(basename "$0") | sed -E 's/^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\2/')
        mylog info "Available functions are:"
        mylog info "$lf_list"
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
# other example: ./unprovision_cluster-v2.sh --call <function_name1>, <function_name2>, ...
# other example: ./unprovision_cluster-v2.sh --all
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

#trap 'display_access_info' EXIT
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
check_resource_exist storageclass $MY_BLOCK_STORAGE_CLASS
check_resource_exist storageclass $MY_FILE_STORAGE_CLASS

check_directory_exist_create "$MY_WORKINGDIR"

######################################################
# main entry
######################################################
main "$@"
