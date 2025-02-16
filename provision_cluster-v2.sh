#!/bin/bash
# Main program to install CP4I end to end with customisation
# Laurent 2021
# Updated July 2023 Saad / Arnauld
################################################
# @param $1 
################################################

################################################
# Install Keycloak
# 20250117 : I'll follow the steps from the documentation:
# https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/26.0/html/operator_guide/index
function install_keycloak() {
  trace_in 3 install_keycloak

  if $MY_KEYCLOAK_EXTERNAL; then
    SECONDS=0

    mylog info "==== Installing Redhat Openshift Keycloak." 1>&2
    local lf_working_directory="${MY_KEYCLOAK_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"
  
    create_project "${MY_KEYCLOAK_NAMESPACE}" "${MY_KEYCLOAK_NAMESPACE} project" "For Keycloak" $lf_working_directory
  
    # Operator group for Keycloak in keycloak namespace
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_KEYCLOAK_OPERATORGROUP}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-single.yaml"
    local lf_namespace="${MY_KEYCLOAK_NAMESPACE}"
    export MY_OPERATORGROUP=$lf_cr_name
    export MY_PROJECT=$lf_namespace  
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}" 
    unset MY_OPERATORGROUP MY_PROJECT
  
    # Create a subscription object for Keycloak Operator
    local lf_operator_name="$MY_KEYCLOAK_OPERATOR"
    local lf_operator_namespace=$MY_KEYCLOAK_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\" "
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
  
    mylog info "Installation of keycloak took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_keycloak
}

################################################
# Create keycloak client
function create_keycloak_client() {
  trace_in 3 create_keycloak_client

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
  
  trace_out 3 create_keycloak_client
}

################################################
# Create keycloak instance
function create_keycloak_instance() {
  trace_in 3 create_keycloak_instance

  # create_keycloak_instance
  local lf_in_keycloak_name=$1
  local lf_in_keycloak_namespace=$2
  local lf_in_postgresql_cluster=$3
  local lf_in_keycloak_db_secret=$4
  local lf_in_keycloak_tls_secret=$5

  local lf_working_directory="${MY_KEYCLOAK_WORKINGDIR}"
  check_directory_exist_create "${lf_working_directory}"

  export MY_KEYCLOAK_NAME=$lf_in_keycloak_name
  export MY_KEYCLOAK_NAMESPACE=$lf_in_keycloak_namespace
  export MY_POSTGRESQL_HOSTNAME="${lf_in_postgresql_cluster}-rw.${MY_POSTGRESQL_NAMESPACE}.svc.cluster.local"
  export MY_KEYCLOAK_DB_SECRET=$lf_in_keycloak_db_secret
  export MY_KEYCLOAK_TLS_SECRET=$lf_in_keycloak_tls_secret
  export MY_CLUSTER_DOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')

  local lf_type="Keycloak"
  local lf_cr_name="${lf_in_keycloak_name}"
  local lf_source_directory="${MY_RESOURCESDIR}"
  local lf_target_directory="${lf_working_directory}"
  local lf_yaml_file="keycloak.yaml"
  local lf_namespace=$lf_in_keycloak_namespace
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}" 
  unset MY_KEYCLOAK_NAME MY_KEYCLOAK_NAMESPACE MY_POSTGRESQL_HOSTNAME MY_KEYCLOAK_DB_SECRET MY_KEYCLOAK_TLS_SECRET MY_CLUSTER_DOMAIN

  #local lf_cr_name=$(oc -n $lf_namespace get $lf_type -o json | jq -r --arg my_resource "$lf_cr_name" '.items[0].metadata | select (.name | contains ($my_resource)).name')
  local lf_cr_name=$(oc -n $lf_namespace get $lf_type -o jsonpath="{.items[0].metadata.name}")
  local lf_path="{.status.conditions[0].type}"
  local lf_state="Ready"
  decho 3 "wait_for_state \"$lf_type $lf_cr_name is $lf_state\" \"$lf_state\" \"oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'\""
  wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

  trace_out 3 create_keycloak_instance
}

################################################
# Install SFTP server, it is usefull for example for backups
function install_sftp() {
  trace_in 3 install_sftp

  if $MY_SFTP; then
    SECONDS=0
  
    mylog info "==== Installing SFTP server." 1>&2
    local lf_working_directory="${MY_SFTP_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"
  
    create_project "${MY_SFTP_SERVER_NAMESPACE}" "${MY_SFTP_SERVER_NAMESPACE} project" "For SFTP server" $lf_working_directory
  
    # Create secret with users
    mylog check "Checking Secret for credential ${MY_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" 1>&2
    if oc get secret -n ${MY_SFTP_SERVER_NAMESPACE} "${MY_SFTP_SERVER_NAMESPACE}-sftp-creds-secret" >/dev/null 2>&1; then
      mylog ok
    else
      generate_password 32
      adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ users.conf
      unset USER_PASSWORD_GEN
  
      local lf_apply_cmd="oc -n $MY_SFTP_SERVER_NAMESPACE create secret generic ${MY_SFTP_SERVER_NAMESPACE}-sftp-creds-secret --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/users.conf"
      local lf_delete_cmd="oc -n $MY_SFTP_SERVER_NAMESPACE delete secret ${MY_SFTP_SERVER_NAMESPACE}-sftp-creds-secret"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
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
      local lf_apply_cmd="oc -n $MY_SFTP_SERVER_NAMESPACE create configmap ${MY_SFTP_SERVER_NAMESPACE}-ssh-conf-cm \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_ed25519_key.pub \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/ssh_host_rsa_key.pub \
        --from-file=${MY_SFTP_GEN_CUSTOMDIR}config/sshd_config"
      local lf_delete_cmd="oc -n $MY_SFTP_SERVER_NAMESPACE delete configmap ${MY_SFTP_SERVER_NAMESPACE}-ssh-conf-cm"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
  
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
      local lf_apply_cmd="oc -n ${MY_SFTP_SERVER_NAMESPACE} create -f ${MY_SFTP_GEN_CUSTOMDIR}config/pvc.yaml"
      local lf_delete_cmd="oc -n ${MY_SFTP_SERVER_NAMESPACE} delete pvc $VAR_PVC_NAME"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
  	  oc -n ${MY_SFTP_SERVER_NAMESPACE} create -f ${MY_SFTP_GEN_CUSTOMDIR}config/pvc.yaml
  	  wait_for_state "$VAR_PVC_NAME status.phase is Bound" "Bound" "oc -n ${MY_SFTP_SERVER_NAMESPACE} get pvc $VAR_PVC_NAME -o jsonpath='{.status.phase}'"
    fi
  
    # Check security context constraint
    mylog check "Security Context Constraint anyuid" 1>&2
    if oc get SecurityContextConstraints anyuid >/dev/null 2>&1; then
      mylog ok
    else
      local lf_apply_cmd="oc adm policy add-scc-to-user anyuid -z default"
      local lf_delete_cmd="oc adm policy remove-scc-from-user anyuid -z default"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc adm policy add-scc-to-user anyuid -z default
      wait 10
      
      local lf_apply_cmd="oc patch scc anyuid --type=merge --patch '{\"users\": [\"system:serviceaccount:sftp:default\n\"]}'"
      local lf_delete_cmd="oc patch scc anyuid --type=merge --patch '{\"users\": []}'"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc patch scc anyuid --type=merge --patch '{"users": ["system:serviceaccount:sftp:default\n"]}'
      
      local lf_apply_cmd="oc patch scc anyuid --type=merge --patch '{\"allowedCapabilities\":[\"SYS_CHROOT\n\"]}'"
      local lf_delete_cmd="oc patch scc anyuid --type=merge --patch '{\"allowedCapabilities\":[]}'"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
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
      local lf_source_directory="${MY_SFTP_GEN_CUSTOMDIR}config/"
      local lf_target_directory="${lf_working_directory}"
      local lf_yaml_file="sftp_dep.yaml"
      local lf_namespace="${MY_SFTP_SERVER_NAMESPACE}"
      decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
      check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}" 
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
      local lf_source_directory="${MY_SFTP_GEN_CUSTOMDIR}config/"
      local lf_target_directory="${lf_working_directory}"
      local lf_yaml_file="sftp_svc.yaml"
      local lf_namespace="${MY_SFTP_SERVER_NAMESPACE}"
      decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
      check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    fi
  
    # Create the route to expose the SFTP server
    mylog check "Checking Route $MY_SFTP_SERVER_NAMESPACE-sftp-route" 1>&2
    if oc -n ${MY_SFTP_SERVER_NAMESPACE} get route "$MY_SFTP_SERVER_NAMESPACE-sftp-route" >/dev/null 2>&1; then
      mylog ok
    else
      adapt_file ${MY_SFTP_SCRIPTDIR}config/ ${MY_SFTP_GEN_CUSTOMDIR}config/ sftp_route.yaml
      local lf_type="Route"
      local lf_cr_name="$MY_SFTP_SERVER_NAMESPACE-sftp-route"
      local lf_source_directory="${MY_SFTP_GEN_CUSTOMDIR}config/"
      local lf_target_directory="${lf_working_directory}"
      local lf_yaml_file="sftp_route.yaml"
      local lf_namespace="${MY_SFTP_SERVER_NAMESPACE}"
      decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
      check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    fi
    mylog info "Installation of sftp took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_sftp
}

################################################
# Install GitOps
function install_gitops() {
  trace_in 3 install_gitops

  # https://docs.openshift.com/gitops/1.12/installing_gitops/installing-openshift-gitops.html
  if $MY_GITOPS; then
    SECONDS=0

    mylog info "==== Installing Redhat Openshift GitOps." 1>&2
    local lf_working_directory="${MY_GITOPS_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # Namespace openshift-gitops-operator does not exist and will be created.
    local lf_operator_name="$MY_GITOPS_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"

    mylog info "Installation of gitops took $SECONDS seconds." 1>&2
  fi
  
  trace_out 3 install_gitops
}

###############################################
# Install CP4I Cluster Logging : Loki log store
# use Openshift Logging
# https://docs.openshift.com/container-platform/4.16/observability/logging/cluster-logging-deploying.html#logging-loki-cli-install_cluster-logging-deploying
function install_logging_loki() {
  trace_in 3 install_logging_loki

  # Openshift Logging
  if $MY_LOGGING_LOKI; then
    SECONDS=0

    mylog info "==== Installing Cluster Logging : Loki log store." 1>&2
    # Create a namespace object for Loki Operator
    local lf_working_directory="${MY_LOKI_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    create_project "${MY_LOKI_NAMESPACE}" "${MY_LOKI_NAMESPACE} project" "For Loki log store" $lf_working_directory

    local lf_apply_cmd="oc patch namespace ${MY_LOKI_NAMESPACE} -p '{\"metadata\": {\"annotations\": {\"openshift.io/node-selector\": \"\"}}}'"
    local lf_delete_cmd="oc patch namespace ${MY_LOKI_NAMESPACE} -p '{\"metadata\": {\"annotations\": {\"openshift.io/node-selector\": null}}}'"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc patch namespace ${MY_LOKI_NAMESPACE} -p '{"metadata": {"annotations": {"openshift.io/node-selector": ""}}}'

    local lf_apply_cmd="oc patch namespace ${MY_LOKI_NAMESPACE} -p '{\"metadata\": {\"labels\": {\"openshift.io/cluster-monitoring\": \"true\"}}}'"
    local lf_delete_cmd="oc patch namespace ${MY_LOKI_NAMESPACE} -p '{\"metadata\": {\"labels\": {\"openshift.io/cluster-monitoring\": null}}}'"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc patch namespace ${MY_LOKI_NAMESPACE} -p '{"metadata": {"labels": {"openshift.io/cluster-monitoring": "true"}}}'

    local lf_type="Route"
    local lf_cr_name="$MY_SFTP_SERVER_NAMESPACE-sftp-route"
    local lf_yaml_file="sftp_route.yaml"
    local lf_namespace="${MY_SFTP_SERVER_NAMESPACE}"

    # Operator group for Loki in all namespaces
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LOKI_OPERATORGROUP}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-all.yaml"
    local lf_namespace="openshift-operators-redhat"
    export MY_OPERATORGROUP=$lf_cr_name
    export MY_PROJECT=$lf_namespace  
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT

    # Create a subscription object for Loki Operator (because there are two loki-operator : community and Redhat, so the command to get the chl is different) 
    local lf_operator_name=$MY_LOKI_OPERATOR
    local lf_operator_namespace="openshift-operators-redhat"
    local lf_operator_chl=$(oc get packagemanifest -n $MY_CATALOGSOURCES_NAMESPACE -o json | jq -r '.items[] | select(.metadata.name=="loki-operator" and .status.catalogSource=="redhat-operators") | .status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name="redhat-operators"
    local lf_csv_name=$(oc get packagemanifest -n $MY_CATALOGSOURCES_NAMESPACE -o json | jq -r '.items[] | select(.metadata.name=="loki-operator" and .status.catalogSource=="redhat-operators") | .status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"

    # Create a namespace object for Red Hat Openshift Logging Operator
    create_project "${MY_LOGGING_NAMESPACE}" "${MY_LOGGING_NAMESPACE} project" "For Red Hat Openshift Logging Operator" $lf_working_directory
    oc patch namespace ${MY_LOGGING_NAMESPACE} -p '{"metadata": {"annotations": {"openshift.io/node-selector": ""}}}'
    oc patch namespace ${MY_LOGGING_NAMESPACE} -p '{"metadata": {"labels": {"openshift.io/cluster-logging": "true"}}}'
    oc patch namespace ${MY_LOGGING_NAMESPACE} -p '{"metadata": {"labels": {"openshift.io/cluster-monitoring": "true"}}}'

    # Create an OperatorGroup object for Red Hat Openhsift Logging Operator
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LOGGING_OPERATOR}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-single.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    export MY_OPERATORGROUP=$lf_cr_name
    export MY_PROJECT=$lf_namespace  
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT
    
    # Create a subscription object for Red Hat Openshift Logging Operator
    local lf_operator_name=$MY_LOGGING_OPERATOR
    local lf_operator_namespace="${MY_LOGGING_NAMESPACE}"
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name="redhat-operators"
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"

    # create an ObjectBucketClaim in openshift-logging namespace
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/installing-log-storage.html#logging-loki-storage-odf_installing-log-storage
    local lf_type="ObjectBucketClaim"
    local lf_cr_name=$MY_LOKI_BUCKET_INSTANCE_NAME
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="objectbucketclaim.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    # get the needed parameters to create the object storage secret
    export MY_LOKI_ACCESS_KEY_ID=$(oc -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.AccessKey}'| base64 --decode)
    export MY_LOKI_ACCESS_KEY_SECRET=$(oc -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.SecretKey}'| base64 --decode)
    export MY_LOKI_ENDPOINT=$(oc -n openshift-storage get secret rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -o jsonpath='{.data.Endpoint}'| base64 --decode)
    decho 3 "MY_LOKI_ACCESS_KEY_ID=$MY_LOKI_ACCESS_KEY_ID|MY_LOKI_ACCESS_KEY_SECRET=$MY_LOKI_ACCESS_KEY_SECRET|MY_LOKI_ENDPOINT=$MY_LOKI_ENDPOINT"

    local lf_type="Secret"
    local lf_cr_name=$MY_LOKI_SECRET
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="loki-secret.yaml"
    local lf_namespace="${MY_LOGGING_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_LOKI_ACCESS_KEY_ID MY_LOKI_ACCESS_KEY_SECRET MY_LOKI_ENDPOINT

    # Create a LokiStack instance
    local lf_type="LokiStack"
    local lf_cr_name="$MY_LOKI_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="Loki-Capability.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    # SB]20241204 Configuring LokiStack log store
    # https://docs.openshift.com/container-platform/4.16/observability/logging/log_storage/cluster-logging-loki.html

    # Create a new group for the cluster-admin user role
    local lf_apply_cmd="oc adm groups new cluster-admin"
    local lf_delete_cmd="oc adm groups delete cluster-admin"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm groups new cluster-admin

    # add the desired user to the cluster-admin group
    local lf_apply_cmd="oc adm groups add-users cluster-admin $MY_USER"
    local lf_delete_cmd="oc adm groups remove-users cluster-admin $MY_USER"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm groups add-users cluster-admin $MY_USER

    # add the cluster-admin user role to the cluster-admin group
    local lf_apply_cmd="oc adm policy add-cluster-role-to-group cluster-admin cluster-admin"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-group cluster-admin cluster-admin"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-group cluster-admin cluster-admin
    
    # Create a ClusterLogging CR object
    # SB]20250207 Quelle galère toujours la même erreur : 
    # CMD: check_create_oc_yaml "ClusterLogging" "instance" "/home/saad/Mywork/Git/202500204-cp4i-install/templates/operands/" "/home/saad/Mywork/Git/202500204-cp4i-install/working/LOKI/" "Rhol-Loki-Capability.yaml" "openshift-logging"
    #          CMD: F:IN :check_create_oc_yaml
    #            Checking ClusterLogging instance in openshift-logging project...                CMD: oc -n openshift-logging get ClusterLogging instance
    #error: resource mapping not found for name: "instance" namespace: "openshift-logging" from "/home/saad/Mywork/Git/202500204-cp4i-install/working/LOKI/Rhol-Loki-Capability.yaml": no matches for kind "ClusterLogging" in version "logging.openshift.io/v1"
    #ensure CRDs are installed first
    # J'ai fini par trouver cec : https://github.com/openshift/cluster-logging-operator/blob/master/docs/administration/upgrade/v6.0_changes.adoc#the-main-change-highlights-are
    # 
    # 

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
    local lf_apply_cmd="oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE"
    local lf_delete_cmd="oc delete sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    # Allow the collector’s service account to write data to the LokiStack CR
    local lf_apply_cmd="oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA 

    # Allow the collector’s service account to collect logs
    local lf_apply_cmd="oc project $MY_LOGGING_NAMESPACE"
    local lf_delete_cmd="oc project $MY_LOGGING_NAMESPACE"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc project $MY_LOGGING_NAMESPACE

    local lf_apply_cmd="oc adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    local lf_apply_cmd="oc adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    local lf_apply_cmd="oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    export VAR_LOKI_HOST=$(oc get route $MY_LOKI_INSTANCE_NAME -n $MY_LOGGING_NAMESPACE -o jsonpath='{.spec.host}')
    local lf_type="ClusterLogForwarder"
    local lf_cr_name="$MY_RHOL_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="Rhol-Loki-Capability.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset VAR_LOKI_HOST
    local lf_path='{.status.conditions[?(@.type=="Ready")].status}'
    local lf_state="True"
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    
    # Create a UIPlugin CR to enable the Log section in the Observe tab
    decho 3 "install_openshift_monitoring create the UI plugin"
    local lf_type="UIPlugin"
    local lf_cr_name="logging"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="uiplugin.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

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

    mylog info "Installation of loki took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_logging_loki
}

###############################################
# Install Redhat Cluster Observability Operator
# # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview
# SB]20250116 TODO : Revoir la configuration de l'observabilité du cluster à la lumière de la documentation ci-dessus.
function install_cluster_observability() {
  trace_in 3 install_cluster_observability

  # Openshift Observability
  if $MY_COO; then
    SECONDS=0

    mylog info "==== Installing Cluster Observability." 1>&2

    local lf_working_directory="${MY_COO_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # Create a service account for the collector
    local lf_apply_cmd="oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE"
    local lf_delete_cmd="oc delete sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    # Create a ClusterRole for the collector
    local lf_apply_cmd="oc apply -f ${MY_RESOURCESDIR}collector-ClusterRole.yaml"
    local lf_delete_cmd="oc delete -f ${MY_RESOURCESDIR}collector-ClusterRole.yaml"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc apply -f "${MY_RESOURCESDIR}collector-ClusterRole.yaml"

    # Bind the ClusterRole to the service account
    local lf_apply_cmd="oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # SB]20241203 https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/logging/logging-6-0#cluster-role-binding-for-your-service-account
    # Create a ClusterRoleBinding for the service account
    local lf_type="ClusterRoleBinding"
    local lf_cr_name="manager-rolebinding"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="role_binding.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    # Install the Cluster Observability Operator
    # https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html-single/cluster_observability_operator/index#cluster-observability-operator-overview

    # Create a subscription object for Cluster Observability Operator
    local lf_operator_name="$MY_COO_OPERATOR"
    local lf_operator_namespace="$MY_OPERATORS_NAMESPACE"
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    
    mylog info "Installation of observability $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_cluster_observability
}

###############################################
# Install Logging OpenTelemetry
# https://docs.openshift.com/container-platform/4.16/observability/logging/logging-6.1/log6x-about-6.1.html
# Pre requisite : Install the Red Hat OpenShift Logging Operator, Loki Operator, and Cluster Observability Operator (COO)
function install_logging_otel() {
  trace_in 3 install_logging_otel

  # Openshift Observability
  if $MY_COO; then
    SECONDS=0

    local lf_working_directory="${MY_COO_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # Create a service account for the collector
    local lf_apply_cmd="oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE"
    local lf_delete_cmd="oc delete sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc create sa $MY_LOGGING_COLLECTOR_SA -n $MY_LOGGING_NAMESPACE

    # Allow the collector’s service account to write data to the LokiStack CR
    local lf_apply_cmd="oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    # Allow the collector’s service account to collect logs
    local lf_apply_cmd="oc project $MY_LOGGING_NAMESPACE"
    local lf_delete_cmd="oc project $MY_LOGGING_NAMESPACE"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc project $MY_LOGGING_NAMESPACE

    local lf_apply_cmd="oc adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user collect-application-logs -z $MY_LOGGING_COLLECTOR_SA

    local lf_apply_cmd="oc adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user collect-audit-logs -z $MY_LOGGING_COLLECTOR_SA

    local lf_apply_cmd="oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z $MY_LOGGING_COLLECTOR_SA

    # Create a UIPlugin CR to enable the Log section in the Observe tab
    decho 3 "install_openshift_monitoring create the UI plugin"
    local lf_type="UIPlugin"
    local lf_cr_name="logging"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="uiplugin.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    # Create a ClusterLogForwarder CR to configure log forwarding
    local lf_type="ClusterLogForwarder"
    local lf_cr_name="${MY_LOGGING_COLLECTOR_SA}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="clusterlogforwarder-otel.yaml"
    local lf_namespace=$MY_LOGGING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    # Bind the ClusterRole to the service account
    local lf_apply_cmd="oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    local lf_delete_cmd="oc adm policy remove-cluster-role-from-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z $MY_LOGGING_COLLECTOR_SA

    mylog info "Installation of otel took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_logging_otel
}


###############################################
# Install/Configure Redhat Cluster Monitoring
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/index
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/monitoring/common-monitoring-configuration-scenarios#configuring-core-platform-monitoring-postinstallation-steps_common-monitoring-configuration-scenarios
# 
function install_cluster_monitoring() {
  trace_in 3 install_cluster_monitoring

  # Openshift cluster monitoring
  if $MY_CLUSTER_MONITORING; then
    SECONDS=0

    local lf_working_directory="${MY_OPENSHIFT_MONITORING_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    create_project "${MY_OPENSHIFT_MONITORING_NAMESPACE}" "${MY_OPENSHIFT_MONITORING_NAMESPACE} project" "For Openshift monitoring" $lf_working_directory

    # Create the cluster-monitoring-config cm
    export MY_MONITORING_CM_NAME="cluster-monitoring-config"
    export MY_MONITORING_NAMESPACE="openshift-monitoring"

    local lf_type="ConfigMap"
    local lf_cr_name="${MY_MONITORING_CM_NAME}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="monitoring-cm.yaml"
    local lf_namespace=$MY_OPENSHIFT_MONITORING_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_MONITORING_CM_NAME MY_MONITORING_NAMESPACE

    # Enable monitoring for user-defines projects
    # If you enable monitoring for user-defined projects, the user-workload-monitoring-config ConfigMap object is created by default.
    # The enableUserWorkload parameter enables monitoring for user-defined projects in the OpenShift cluster. 
    # This action creates a prometheus-operated service in the openshift-user-workload-monitoring namespace.
    #export MY_MONITORING_CM_NAME="user-workload-monitoring-config"
    #export MY_MONITORING_NAMESPACE="openshift-user-workload-monitoring"
    local lf_apply_cmd="oc patch configmap ${MY_MONITORING_CM_NAME} -n $MY_OPENSHIFT_MONITORING_NAMESPACE --type=merge --patch '{\"data\":{\"config.yaml\":\"enableUserWorkload: true\n\"}}'"
    local lf_delete_cmd="oc patch configmap ${MY_MONITORING_CM_NAME} -n $MY_OPENSHIFT_MONITORING_NAMESPACE --type=merge --patch '{\"data\":{\"config.yaml\":\"enableUserWorkload: false\n\"}}'"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc patch configmap ${MY_MONITORING_CM_NAME} -n $MY_OPENSHIFT_MONITORING_NAMESPACE --type=merge --patch '{"data":{"config.yaml":"enableUserWorkload: true\n"}}'

    # Granting users permissions for core platform monitoring

    mylog info "Installation of monitoring took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_cluster_monitoring
}

##################################################
# Install OADP (OpenShift API for Data Protection)
function install_oadp() {
  trace_in 3 install_oadp

  if $MY_OADP; then
    SECONDS=0

    mylog info "==== Installing Redhat Openshift OADP." 1>&2
    local lf_working_directory="${MY_OADP_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # OpenShift restricts creating namespaces with the openshift- prefix via oc create namespace. 
    # However, you can bypass this limitation using oc apply:
    create_project "$MY_OADP_NAMESPACE" "${MY_OADP_NAMESPACE} project" "For OADP deployment" $lf_working_directory

    # Operator group for OADP in single namespace
    export MY_OPERATORGROUP="${MY_OADP_OPERATORGROUP}"
    export MY_PROJECT="${MY_OADP_NAMESPACE}"

    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_OADP_OPERATORGROUP}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-single.yaml"
    local lf_namespace="${MY_OADP_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT


    # Create a subscription object for OADP Operator
    local lf_operator_name="${MY_OADP_OPERATOR}"
    local lf_operator_namespace=$MY_OADP_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"

    mylog info "Installation of oadp took $SECONDS seconds." 1>&2
  fi
  trace_out 3 install_oadp
}

################################################
# Install redhat Pipelines (tekton)
function install_pipelines() {
  trace_in 3 install_pipelines

  if $MY_TEKTON; then
    SECONDS=0
  
    # https://docs.openshift.com/pipelines/1.14/install_config/installing-pipelines.html
  
    mylog info "==== Installing Redhat Openshift Pipelines (tekton)." 1>&2
    local lf_working_directory="${MY_PIPELINES_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # Create a subscription object for pipelines Operator
    local lf_operator_name="$MY_PIPELINES_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
  
    mylog info "Installation of pipelines took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_pipelines
}

################################################
# Add mailhog app to openshift
# Port is hard coded to 8025 and is defined by mailhog (default port)
function install_mailhog() {
  trace_in 3 install_mailhog

  if $MY_MAILHOG; then
    SECONDS=0

    mylog info "==== Installing Mailhog (server and client)." 1>&2
    local lf_working_directory="${MY_MAIL_SERVER_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    local lf_type="deployment"
    local lf_name="mailhog"

    # May need some properties
    # read_config_file "${MY_YAMLDIR}ldap/ldap.properties"

    # create namespace if needed
    create_project "${MY_MAIL_SERVER_NAMESPACE}" "${MY_MAIL_SERVER_NAMESPACE} project" "For Mailhog fake SMTP server deployment" $lf_working_directory

    deploy_mailhog ${lf_type} ${lf_name} ${MY_MAIL_SERVER_NAMESPACE}
    expose_service_mailhog ${lf_name} ${MY_MAIL_SERVER_NAMESPACE} '8025'

    mylog info "Installation of mailhog took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_mailhog
}

################################################
# Add OpenLdap app to openshift
function install_openldap() {
  trace_in 3 install_openldap

  if $MY_LDAP; then
    SECONDS=0

    mylog info "==== Installing OpenLdap." 1>&2
    local lf_working_directory="${MY_LDAP_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    local lf_type="deployment"
    local lf_name="openldap"

    read_config_file "${MY_YAMLDIR}ldap/ldap.properties"

    # create namespace if needed
    create_project "${MY_LDAP_NAMESPACE}" "${MY_LDAP_NAMESPACE} project" "For OpenLDAP deployment" $lf_working_directory

    #SB]20231207 checks if used directories and files exists
    check_file_exist ${MY_YAMLDIR}ldap/ldap-pvc.main.yaml
    check_file_exist ${MY_YAMLDIR}ldap/ldap-pvc.config.yaml
    check_file_exist ${MY_YAMLDIR}ldap/ldap-config.json
    check_file_exist ${MY_YAMLDIR}ldap/ldap-users.ldif

    provision_persistence_openldap ${MY_LDAP_NAMESPACE}
    deploy_openldap ${lf_type} ${lf_name} ${MY_LDAP_NAMESPACE}
    expose_service_openldap ${lf_name} ${MY_LDAP_NAMESPACE}
    
    mylog info "Installation of openldap took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_openldap
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
  trace_in 3 install_cert_manager

  if $MY_CERT_MANAGER; then
    SECONDS=0
  
    mylog info "==== Installing Redhat Cert Manager." 1>&2
    local lf_working_directory="${MY_CERTMANAGER_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"
    
    create_project "$MY_CERTMANAGER_OPERATOR_NAMESPACE" "${MY_CERTMANAGER_OPERATOR_NAMESPACE} project" "For cert manager" $lf_working_directory
    
    export MY_OPERATORGROUP="${MY_CERTMANAGER_OPERATOR}"
    export MY_PROJECT="${MY_CERTMANAGER_OPERATOR_NAMESPACE}"
  
    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_CERTMANAGER_OPERATOR}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-cert-manager.yaml"
    local lf_namespace="${MY_CERTMANAGER_OPERATOR_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT
  
    # Create a subscription object for cert manager Operator
    local lf_operator_name="${MY_CERTMANAGER_OPERATOR}"
    local lf_operator_namespace=$MY_CERTMANAGER_OPERATOR_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
  
    mylog info "Installation of cert manager took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_cert_manager
}

################################################
# Install Licensing Server
# 2025010 https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-license-openshift-container-platform
#
function install_lic_svc() {
  trace_in 3 install_lic_svc

  # ibm-license-server
  if $MY_LIC_SRV; then
    SECONDS=0

    mylog info "==== Installing IBM License Server." 1>&2
    local lf_working_directory="${MY_LICENSE_SERVICE_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    create_project "$MY_LICENSE_SERVICE_NAMESPACE"  "${MY_LICENSE_SERVICE_NAMESPACE} project" "For License Server deployment" $lf_working_directory

    check_add_cs_ibm_pak $MY_LICENSE_SERVICE_CASE amd64
    wait_for_resource "packagemanifest" "${MY_LICENSE_SERVICE_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    export MY_OPERATORGROUP="${MY_LICENSE_SERVICE_OPERATORGROUP}"
    export MY_PROJECT="${MY_LICENSE_SERVICE_NAMESPACE}"

    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LICENSE_SERVICE_OPERATORGROUP}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-single.yaml"
    local lf_namespace=$MY_LICENSE_SERVICE_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT

    # Create a subscription object for license service Operator
    local lf_operator_name="${MY_LICENSE_SERVICE_OPERATOR}"
    local lf_operator_namespace=$MY_LICENSE_SERVICE_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"

    local lf_cr_name=$(oc -n $lf_operator_namespace get IBMLicensing -o jsonpath='{.items[0].metadata.name}')
    decho 3 "lf_cr_name=$lf_cr_name"
    accept_license_fs $lf_operator_namespace IBMLicensing  ${lf_cr_name}

    mylog info "Check if Installing network policies for license Service is needed" 1>&2
    #mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license"
    search_networkpolicies
    local lf_res=$?
    decho 3 "lf_res=$lf_res"
    if [ $lf_res -eq 1 ]; then
      mylog info "Please import and install network policies for License Service."
      mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license#installing-network-policies"
    else
      mylog info "Network policies for License Service not needed."
    fi

    mylog info "Installation of license service took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_lic_svc
}

################################################
# Install Licensing Service Reporter
# 2025010 https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=repository-installing-license-service-reporter-cli
#
function install_lic_reporter_svc() {
  trace_in 3 install_lic_reporter_svc

  # ibm-license-server
  if $MY_LIC_SRV_REPORTER; then
    SECONDS=0

    mylog info "==== Installing IBM License Service Reporter." 1>&2
    local lf_working_directory="${MY_LICENSE_SERVICE_REPORTER_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    create_project "$MY_LICENSE_SERVICE_REPORTER_NAMESPACE" "${MY_LICENSE_SERVICE_REPORTER_NAMESPACE} project" "For License Service Reporter deployment" $lf_working_directory

    check_add_cs_ibm_pak $MY_LICENSE_SERVICE_REPORTER_CASE amd64
    wait_for_resource "packagemanifest" "${MY_LICENSE_SERVICE_REPORTER_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Operator group for License Service Reporter in single namespace
    export MY_OPERATORGROUP="${MY_LICENSE_SERVICE_REPORTER_OPERATORGROUP}"
    export MY_PROJECT="${MY_LICENSE_SERVICE_REPORTER_NAMESPACE}"

    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_LICENSE_SERVICE_REPORTER_OPERATORGROUP}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-single.yaml"
    local lf_namespace="${MY_LICENSE_SERVICE_REPORTER_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT

    # Create a subscription object for license service reporter Operator
    local lf_operator_name="${MY_LICENSE_SERVICE_REPORTER_OPERATOR}"
    local lf_operator_namespace=$MY_LICENSE_SERVICE_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    mylog info "Creating the License Service Reporter instance" 1>&2
    mylog warn "Saad: Check that it is working to wait for the state, if not we need a temporisation" 1>&2
    export MY_LICENSE_SERVICE_REPORTER_VERSION=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSVDesc.version')
    # Creating Creating the License Service Reporter instance 
    local lf_type="IBMLicenseServiceReporter"
    local lf_cr_name="$MY_LICENSE_SERVICE_REPORTER_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="LIC-Reporter-Capability.yaml"
    local lf_namespace="${MY_LICENSE_SERVICE_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.LicenseServiceReporterPods[-1].phase}"
    local lf_state="Running"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"


    # Add license service to the reporter
    # oc get routes -n ibm-licensing | grep ibm-license-service-reporter | awk '{print $2}'
    mylog info "Add license service to the reporter" 1>&2
    decho 3 "oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name==\"ibm-license-service-reporter\")].spec.host}'"
    lf_licensing_service_reporter_url=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-license-service-reporter")].spec.host}')
    decho 4 "License Service Reporter URL: $lf_licensing_service_reporter_url"
    oc -n $MY_LICENSE_SERVICE_NAMESPACE patch IBMLicensing instance --type merge --patch "{\"spec\":{\"sender\":{\"reporterSecretToken\":\"ibm-license-service-reporter-token\",\"reporterURL\":\"https://$lf_licensing_service_reporter_url/\",\"clusterID\":\"MyClusterTest1\",\"clusterName\":\"MyClusterTest1\"}}}"

    mylog info "Check if Installing network policies for license Service is needed" 1>&2
    #mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license"
    search_networkpolicies
    local lf_res=$?
    decho 3 "lf_res=$lf_res"
    if [ $lf_res -eq 1 ]; then
      mylog info "Please import and install network policies for License Service."
      mylog info "https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.6?topic=service-installing-network-policies-license#installing-network-policies"
    else
      mylog info "Network policies for License Service not needed."
    fi

    mylog info "Installation of license service reporter took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_lic_reporter_svc
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
  trace_in 3 install_fs

  if $MY_COMMONSERVICES; then
    SECONDS=0

    mylog info "==== Installing IBM Common Services." 1>&2
    local lf_working_directory="${MY_COMMONSERVICES_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    create_project "$MY_COMMONSERVICES_NAMESPACE" "$MY_COMMONSERVICES_NAMESPACE project" "For the common services" $lf_working_directory

    # ibm-cp-common-services
    check_add_cs_ibm_pak $MY_COMMONSERVICES_CASE amd64 $MY_COMMONSERVICES_VERSION
    export MY_COMMONSERVICES_VERSION=$VAR_APP_VERSION
    unset VAR_APP_VERSION
    wait_for_resource "packagemanifest" "${MY_COMMONSERVICES_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Create a subscription object for common services Operator
    local lf_operator_name="${MY_COMMONSERVICES_OPERATOR}"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    ## Setting hardware  Accept the license to use foundational services by adding spec.license.accept: true in the spec section.
    #accept_license_fs $MY_OPERATORS_NAMESPACE
    accept_license_fs $lf_operator_namespace CommonService ${MY_COMMONSERVICES_INSTANCE_NAME}

    # Configuring foundational services by using the CommonService custom resource.
    local lf_type="CommonService"
    local lf_cr_name=$MY_COMMONSERVICES_INSTANCE_NAME
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="foundational-services-cr.yaml"
    local lf_namespace="${MY_OPERATORS_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    mylog info "Installation of foundational services took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_fs
}
 
################################################
# Install Open Liberty
function install_openliberty() {
  trace_in 3 install_openliberty

  # backend J2EE applications
  if $MY_OPENLIBERTY; then
    SECONDS=0

    mylog info "==== Installing OPEN Liberty." 1>&2
    local lf_working_directory="${MY_OPENLIBERTY_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    create_project "$MY_BACKEND_NAMESPACE" "$MY_BACKEND_NAMESPACE project" "For Open Liberty instances and create custom API" $lf_working_directory

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
      local lf_apply_cmd="oc apply --server-side -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml"
      local lf_delete_cmd="oc delete --server-side -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc apply --server-side -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-crd.yaml

      local lf_apply_cmd="oc apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml"
      local lf_delete_cmd="oc delete -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-rbac-watch-all.yaml

      local lf_apply_cmd="oc -n ${MY_BACKEND_NAMESPACE} apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml"
      local lf_delete_cmd="oc -n ${MY_BACKEND_NAMESPACE} delete -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc -n ${MY_BACKEND_NAMESPACE} apply -f ${MY_OPENLIBERTY_GEN_CUSTOMDIR}config/openliberty-app-operator.yaml
    fi

    mylog info "Installation of openliberty took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_openliberty
}

################################################
# Install WebSphere Liberty
function install_wasliberty() {
  trace_in 3 install_wasliberty

  if $MY_WASLIBERTY; then
    SECONDS=0

    mylog info "==== Installing WAS Liberty." 1>&2
    local lf_working_directory="${MY_WASLIBERTY_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    create_project "$MY_BACKEND_NAMESPACE" "$MY_BACKEND_NAMESPACE project" "For WebSphere Application Server (Liberty) instances and create custom API" $lf_working_directory

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_WASLIBERTY_OPERATOR amd64
    wait_for_resource "packagemanifest" "${MY_WASLIBERTY_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Operator group for WAS Liberty in single namespace
    export MY_OPERATORGROUP="${MY_WASLIBERTY_OPERATORGROUP}"
    export MY_PROJECT="${MY_BACKEND_NAMESPACE}" 

    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_WASLIBERTY_OPERATORGROUP}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-single.yaml"
    local lf_namespace="${MY_BACKEND_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT

    # Creating WebSphere Liberty operator subscription
    local lf_operator_name="${MY_WASLIBERTY_OPERATOR}"
    local lf_operator_namespace=$MY_BACKEND_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    mylog info "Installation of was liberty took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_wasliberty
}

################################################
# Install Navigator (depending on two boolean)
function install_navigator() {
  trace_in 3 install_navigator

  ## ibm-integration-platform-navigator
  # SB,AD]20240103 Suite au pb installation keycloak (besoin de l'operateur IBM Cloud Pak for Integration)
  # Creating Navigator operator subscription
  if $MY_NAVIGATOR; then
    SECONDS=0

    mylog info "==== Installing CP4I Navigator." 1>&2
    local lf_working_directory="${MY_NAVIGATOR_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_NAVIGATOR_OPERATOR amd64
    export MY_MSGSRV_VERSION=$VAR_APP_VERSION
    unset VAR_APP_VERSION
    wait_for_resource "packagemanifest" "${MY_NAVIGATOR_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating Navigator operator subscription
    local lf_operator_name="$MY_NAVIGATOR_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    
  fi

  if $MY_NAVIGATOR_INSTANCE; then
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_NAVIGATOR_VERSION" ]; then
      export MY_NAVIGATOR_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_NAVIGATOR_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
      decho 3 "MY_NAVIGATOR_VERSION=$MY_NAVIGATOR_VERSION"
    fi

    # Creating Navigator instance
    local lf_type="PlatformNavigator"
    local lf_cr_name="$MY_NAVIGATOR_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="Navigator-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    mylog info "Installation of navigator took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_navigator
}

################################################
# Install Asset Repository
function install_assetrepo() {
  trace_in 3 install_assetrepo

  if $MY_ASSETREPO; then
    SECONDS=0

    mylog info "==== Installing CP4I Asset Repository." 1>&2
    local lf_working_directory="${MY_ASSETREPO_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ASSETREPO_OPERATOR amd64
    wait_for_resource "packagemanifest" "${MY_ASSETREPO_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating Asset Repository operator subscription
    local lf_operator_name=$MY_ASSETREPO_OPERATOR
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    if $MY_ASSETREPO_INSTANCE; then
      #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
      if [ -z "$MY_ASSETREPO_VERSION" ]; then
        export MY_ASSETREPO_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_ASSETREPO_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
        decho 3 "MY_ASSETREPO_VERSION=$MY_ASSETREPO_VERSION"
      fi

      # Creating Asset Repository instance
      local lf_type="AssetRepository"
      local lf_cr_name="$MY_ASSETREPO_INSTANCE_NAME"
      local lf_source_directory="${MY_OPERANDSDIR}"
      local lf_target_directory=$lf_working_directory
      local lf_yaml_file="AR-Capability.yaml"
      local lf_namespace="${MY_OC_PROJECT}"
      decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
      check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

      local lf_path="{.status.phase}"
      local lf_state="Ready"
      #local lf_wait_for_state=true
      wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    fi

    mylog info "Installation of asset repository took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_assetrepo
}

################################################
# Install Integration Assembly
function install_intassembly() {
  trace_in 3 install_intassembly

  # Creating Integration Assembly instance
  if $MY_INTASSEMBLY; then
    SECONDS=0

    mylog info "==== Installing CP4I Integration Assembly." 1>&2
    local lf_working_directory="${MY_INTASSEMBLY_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    local lf_type="IntegrationAssembly"
    local lf_cr_name="$MY_INTASSEMBLY_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="IntegrationAssembly-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    mylog info "Installation of integration assembly took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_intassembly
}

################################################
# Install ACE
function install_ace() {
  trace_in 3 install_ace

  # ibm-appconnect
  if $MY_ACE; then
    SECONDS=0

    mylog info "==== Installing CP4I ACE." 1>&2

    local lf_working_directory="${MY_ACE_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ACE_OPERATOR amd64
    export MY_ACE_VERSION=$VAR_APP_VERSION
    unset VAR_APP_VERSION
    wait_for_resource "packagemanifest" "${MY_ACE_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating ACE operator subscription
    local lf_operator_name="$MY_ACE_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    
    # Creating ACE Switch Server instance (used for callable flows)
    local lf_type="SwitchServer"
    local lf_cr_name="$MY_ACE_SWITCHSERVER_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="ACE-SwitchServer-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    # Creating ACE Dashboard instance
    local lf_type="Dashboard"
    local lf_cr_name="$MY_ACE_DASHBOARD_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="ACE-Dashboard-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    # Creating ACE Designer instance
    local lf_type="DesignerAuthoring"
    local lf_cr_name="$MY_ACE_DESIGNER_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="ACE-Designer-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    mylog info "Installation of ace took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_ace
}

################################################
# Install APIC
function install_apic() {
  trace_in 3 install_apic

  # ibm-apiconnect
  if $MY_APIC; then
    SECONDS=0

    mylog info "==== Installing CP4I APIC." 1>&2

    local lf_working_directory="${MY_APIC_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_APIC_OPERATOR amd64
    export MY_APIC_VERSION=$VAR_APP_VERSION
    unset VAR_APP_VERSION
    wait_for_resource "packagemanifest" "${MY_APIC_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating APIC operator subscription
    local lf_operator_name="$MY_APIC_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    
    if $MY_APIC_BY_COMPONENT; then
      mylog info "HOLD PLACE"
    else
      # Creating APIC instance
      local lf_type="APIConnectCluster"
      local lf_cr_name="$MY_APIC_INSTANCE_NAME"
      local lf_source_directory="${MY_OPERANDSDIR}"
      local lf_target_directory=$lf_working_directory
      local lf_yaml_file="APIC-Capability.yaml"
      local lf_namespace="${MY_OC_PROJECT}"
      decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
      check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

      local lf_path="{.status.phase}"
      local lf_state="Ready"
      #local lf_wait_for_state=true
      wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    fi

    #AD/SB]20240703 enable the Gateway Cluster webGui Management and add webgui-port to set it accessible
    mylog info "Enable web console of the API Connect Gateway"
    oc -n "${MY_OC_PROJECT}" patch GatewayCluster "${MY_APIC_INSTANCE_NAME}-gw" --type merge -p '{"spec": {"webGUIManagementEnabled": true}}'

    local lf_ingress=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

    export MY_PROJECT="${MY_OC_PROJECT}"
    export MY_ROUTE_NAME="${MY_APIC_INSTANCE_NAME}-gw-webconsole"
    export MY_ROUTE_BALANCE="roundrobin"
    export MY_ROUTE_INSTANCE="${MY_APIC_INSTANCE_NAME}-gw"
    export MY_ROUTE_PARTOF="${MY_APIC_INSTANCE_NAME}"
    export MY_ROUTE_HOST="${MY_ROUTE_NAME}.${lf_ingress}"
    export MY_ROUTE_PORT=9090
    export MY_ROUTE_SERVICE=${MY_APIC_INSTANCE_NAME}-gw-datapower

    decho 3 "${MY_PROJECT}, ${MY_ROUTE_NAME}, ${MY_ROUTE_BALANCE}, ${MY_ROUTE_INSTANCE}, ${MY_ROUTE_PARTOF}, ${MY_ROUTE_HOST}, ${MY_ROUTE_PORT}, ${MY_ROUTE_SERVICE}"

    local lf_type="Route"
    local lf_cr_name="${MY_APIC_INSTANCE_NAME}-gw-webconsole"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="route.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_PROJECT MY_ROUTE_NAME MY_ROUTE_BALANCE MY_ROUTE_INSTANCE MY_ROUTE_PARTOF MY_ROUTE_HOST MY_ROUTE_PORT MY_ROUTE_SERVICE

    save_certificate ${MY_OC_PROJECT} cp4i-apic-ingress-ca ca.crt ${MY_WORKINGDIR}
    save_certificate ${MY_OC_PROJECT} cp4i-apic-gw-gateway ca.crt ${MY_WORKINGDIR}

    mylog info "Installation of apic took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_apic
}

################################################
# Install APIC Graphql (Ex Stepzen)
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=installing-maintaining-api-connect-graphql
# https://www.ibm.com/docs/en/api-connect/graphql/1.x?topic=graphql-installing-api-connect
function install_apic_graphql() {
  trace_in 3 install_apic_graphql

  # ibm apic graphql
  if $MY_APIC_GRAPHQL; then
    SECONDS=0

    mylog info "==== Installing CP4I APIC Graphql." 1>&2

    # Create the apic_graphql working directory if it does not exist
    local lf_working_directory="${MY_APIC_GRAPHQL_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"
  
    # create a PostgreSQL database for the APIC Graphql
    create_postgresql_db "apic-graphql-cluster" "apic-graphql-db" "apic-graphql-pg-user" "apic-graphql-pg-password" "apic-graphql-pg-secret" "apic graphql pg database"

    # Create namespace for IBM Stepzen.
    create_project "$MY_APIC_GRAPHQL_NAMESPACE" "$MY_APIC_GRAPHQL_NAMESPACE project" "For IBM Stepzen instances and create custom API" $lf_working_directory
    add_ibm_entitlement $MY_APIC_GRAPHQL_NAMESPACE $MY_CONTAINER_ENGINE

    local lf_namespace="${MY_APIC_GRAPHQL_NAMESPACE}"
    local lf_postgresql_host lf_dsn lf_type lf_cr_name
    local lf_case_version lf_tgz_file lf_deploy_dir
    local lf_path lf_state lf_cr_name lf_url

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
      local lf_apply_cmd="oc -n ${lf_namespace} create secret generic $lf_cr_name --from-literal=DSN=\"${lf_dsn}\""
      local lf_delete_cmd="oc -n ${lf_namespace} delete secret $lf_cr_name"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc -n ${lf_namespace} create secret generic $lf_cr_name --from-literal=DSN="${lf_dsn}"
    fi

    # Download and extract the CASE bundle.
    lf_case_version=$(oc ibm-pak list -o json | jq -r --arg case "$MY_APIC_GRAPHQL_CASE" '.[] | select (.name == $case ) | .latestVersion')
    oc ibm-pak get ${MY_APIC_GRAPHQL_CASE} --version ${lf_case_version} 1>&2

    lf_tgz_file=${MY_IBMPAK_CASESDIR}${MY_APIC_GRAPHQL_CASE}/${lf_case_version}/${MY_APIC_GRAPHQL_CASE}-${lf_case_version}.tgz
    if [ -e "$lf_tgz_file" ]; then
      tar xvzf ${lf_tgz_file} -C ${lf_working_directory} >/dev/null 2>&1
    fi    
    
    # Apply the operator manifest files to the cluster
    lf_deploy_dir="${lf_working_directory}${MY_APIC_GRAPHQL_CASE}/inventory/stepzenGraphOperator/files/deploy/"
    decho 3 "Applying the operator manifest files to the cluster : crd.yaml." 1>&2
    local lf_apply_cmd="oc -n ${lf_namespace} apply -f ${lf_deploy_dir}crd.yaml"
    local lf_delete_cmd="oc -n ${lf_namespace} delete -f ${lf_deploy_dir}crd.yaml"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc -n ${lf_namespace} apply -f ${lf_deploy_dir}crd.yaml

    decho 3 "Applying the operator manifest files to the cluster : operator.yaml." 1>&2
    local lf_apply_cmd="oc -n ${lf_namespace} apply -f ${lf_deploy_dir}operator.yaml"
    local lf_delete_cmd="oc -n ${lf_namespace} delete -f ${lf_deploy_dir}operator.yaml"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc -n ${lf_namespace} apply -f ${lf_deploy_dir}operator.yaml
    sleep 10

    # Configuring APIC Graphql
    decho 3 "Configuring APIC Graphql." 1>&2
    local lf_type="StepZenGraphServer"
    local lf_cr_name="stepzen"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="stepzen.yaml"
    local lf_namespace=$MY_APIC_GRAPHQL_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}" 

    #local lf_cr_name=$(oc -n $lf_namespace get $lf_type -o json | jq -r --arg my_resource "$lf_cr_name" '.items[0].metadata | select (.name | contains ($my_resource)).name')
    lf_type="StepZenGraphServer"
    lf_cr_name="stepzen"
    lf_path="{.status.conditions[-1].type}"
    lf_state="Ready"

    lf_cr_name=$(oc -n $lf_namespace get $lf_type -o jsonpath="{.items[0].metadata.name}")
    decho 3 "wait_for_state \"$lf_type $lf_cr_name is $lf_state\" \"$lf_state\" \"oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'\""
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    # Creating APIC Graphql route
    # first create a cluster issuer (this creates a simple self-signed issuer for the root certificate)
    local lf_type="Issuer"
    local lf_cr_name="${MY_ISSUER}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="self-signed-issuer.yaml"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

    # The first method to get the cluster domain
    #lf_url=$(oc get infrastructure cluster -o jsonpath='{.status.apiServerURL}')
    #export MY_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1)
    #export MY_CLUSTER_DOMAIN=$(echo "$lf_url" | cut -d'/' -f3 | cut -d':' -f1 | cut -d'.' -f2-)

    # The second method to get the cluster domain
    export MY_CLUSTER_DOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
    decho 3 "MY_CLUSTER_DOMAIN=$MY_CLUSTER_DOMAIN"

    # Add the certificate csr for routes (following chatgpt advice)
    adapt_file ${MY_RESOURCESDIR} ${MY_WORKINGDIR} stepzen-graphql-csr.yaml
    local lf_apply_cmd="oc apply -f ${MY_WORKINGDIR}stepzen-graphql-csr.yaml"
    local lf_delete_cmd="oc delete -f ${MY_WORKINGDIR}stepzen-graphql-csr.yaml"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    if ! oc apply -f "${MY_WORKINGDIR}stepzen-graphql-csr.yaml" ; then
      unset MY_CLUSTER_DOMAIN
      trace_out 3 install_apic_graphql
      exit 1
    fi

    # Then Install OpenShift Route Support for cert-manager (openshift-routes).
    # ATTENTION REVOIR le namespace : c'est cert-manager et non pas cert-manager-namespace (https://github.com/cert-manager/openshift-routes?tab=readme-ov-file)
    # https://github.com/cert-manager/openshift-routes
    local lf_apply_cmd="helm install openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes"
    local lf_delete_cmd="helm uninstall openshift-routes -n cert-manager"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    helm install openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes
    #oc -n cert-manager apply -f <(helm template openshift-routes -n cert-manager oci://ghcr.io/cert-manager/charts/openshift-routes --set omitHelmLabels=true)

    # Set up a stepzen-graph-server route for the stepzen account. This is the "root" account of the API Connect Graphql service, 
    # which is used to host endpoints that modify the metadata database but does not serve application requests. 
    # The stepzen-graph-server route is required for the API Connect Graphql CLI to function.
    local lf_type="Route"
    local lf_cr_name="stepzen-to-graph-server"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="stepzen-route.yaml"
    local lf_namespace=$MY_APIC_GRAPHQL_NAMESPACE
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"     

    # Set up stepzen-graph-server and stepzen-graph-server-subscriptions routes for the graphql account.
    # This is the default account for serving application requests.
    adapt_file ${MY_RESOURCESDIR} ${lf_working_directory} graphql-route.yaml
    local lf_apply_cmd="oc apply -f ${lf_working_directory}graphql-route.yaml"
    local lf_delete_cmd="oc delete -f ${lf_working_directory}graphql-route.yaml"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    if ! oc apply -f "${lf_working_directory}graphql-route.yaml" ; then
      unset MY_CLUSTER_DOMAIN
      trace_out 3 install_apic_graphql
      exit 1
    fi

    # Install Introspection service
    adapt_file ${MY_RESOURCESDIR} ${lf_working_directory} introspection.yaml
    local lf_apply_cmd="oc apply -f ${lf_working_directory}introspection.yaml"
    local lf_delete_cmd="oc delete -f ${lf_working_directory}introspection.yaml"
    append_to_file  "${lf_apply_cmd}" $sc_install_executed_commands_file
    prepend_to_file  "${lf_delete_cmd}" $sc_uninstall_executed_commands_file
    if ! oc apply -f "${lf_working_directory}introspection.yaml" ; then
      trace_out 3 install_apic_graphql
      exit 1
    fi
    
    mylog info "Installation of apic graphql took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_apic_graphql
}


################################################
# Install IBM Event streams
function install_es() {
  trace_in 3 install_es

  # ibm-eventstreams
  if $MY_ES; then
    SECONDS=0

    mylog info "==== Installing CP4I Event Streams." 1>&2

    local lf_working_directory="${MY_ES_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_ES_OPERATOR amd64
    export MY_ES_VERSION=$VAR_APP_VERSION
    unset VAR_APP_VERSION
    wait_for_resource "packagemanifest" "${MY_ES_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating EventStreams operator subscription
    local lf_operator_name="$MY_ES_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    
    # Creating Event Streams instance
    local lf_type="EventStreams"
    local lf_cr_name="$MY_ES_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="ES-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.phase}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    
    mylog info "Installation of event streams took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_es
}

################################################
# Install EEM
function install_eem() {
  trace_in 3 install_eem


  if $MY_EEM; then
    SECONDS=0

    local lf_varb64
    mylog info "==== Installing CP4I Event Endpoint Management." 1>&2

    local lf_working_directory="${MY_EEM_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    ## event endpoint management
    ## to get the name of the pak to use : oc ibm-pak list
    ## https://ibm.github.io/event-automation/eem/installing/installing/, chapter : Install the operator by using the CLI (oc ibm-pak)
    check_add_cs_ibm_pak $MY_EEM_OPERATOR amd64
    wait_for_resource "packagemanifest" "${MY_EEM_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating Event Endpoint Management operator subscription
    local lf_operator_name="${MY_EEM_OPERATOR}"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_EEM_VERSION" ]; then
      export MY_EEM_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_EEM_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # Creating EventEndpointManager instance (Event Processing)
    if $MY_KEYCLOAK_INTEGRATION; then
      export MY_EEM_AUTH_TYPE=INTEGRATION_KEYCLOAK
    else
      export MY_EEM_AUTH_TYPE=LOCAL
    fi
    
    local lf_type="EventEndpointManagement"
    local lf_cr_name="$MY_EEM_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="EEM-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    ## Creating EEM users and roles
    if $MY_KEYCLOAK_INTEGRATION; then
      # generate properties files
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ keycloak-user-roles
      # keycloak user roles
      local lf_varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/keycloak-user-roles.yaml" | base64 -w0)
      local lf_apply_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]'"
      local lf_delete_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"\"}]'"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]"
    else
      # generate properties files
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ local-user-credentials.yaml
      adapt_file ${MY_EEM_SCRIPTDIR}config/ ${MY_EEM_GEN_CUSTOMDIR}config/ local-user-roles.yaml
      # base64 generates an error ": illegal base64 data at input byte 76". Solution found here : https://bugzilla.redhat.com/show_bug.cgi?id=1809431. use base64 -w0
      # local user credentials
      local lf_varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/local-user-credentials.yaml" | base64 -w0)
      local lf_apply_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$lf_varb64\"}]'"
      local lf_delete_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"\"}]'"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$lf_varb64\"}]"
      
      # local user roles
      local lf_varb64=$(cat "${MY_EEM_GEN_CUSTOMDIR}config/local-user-roles.yaml" | base64 -w0)
      local lf_apply_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]'"
      local lf_delete_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"\"}]'"
      append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
      prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
      oc -n $MY_OC_PROJECT patch secret "${MY_EEM_INSTANCE_NAME}-ibm-eem-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]"
    fi
    
    mylog info "Installation of evet endpoint management took $SECONDS seconds." 1>&2
  fi
  
  trace_out 3 install_eem
}

################################################
# Install EGW
function install_egw() {
  trace_in 3 install_egw

  # Creating EventGateway instance (Event Gateway)
  if $MY_EGW; then
    SECONDS=0

    mylog info "==== Installing CP4I Event Endpoint Gateway." 1>&2
    local lf_working_directory="${MY_EGW_WORKINGDIR}"
    check_directory_exist_create "${lf_target_directory}"

    export MY_EEM_MANAGER_GATEWAY_ROUTE=$(oc -n $MY_OC_PROJECT get eem $MY_EEM_INSTANCE_NAME -o jsonpath='{.status.endpoints[1].uri}')

    local lf_type="EventGateway"
    local lf_cr_name="$MY_EGW_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="EG-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    
    mylog info "Installation of event gateway took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_egw
}

################################################
# Install EP
function install_ep() {
  trace_in 3 install_ep


  if $MY_EP; then
    SECONDS=0
    
    local lf_varb64
    mylog info "==== Installing CP4I Event Processing." 1>&2

    local lf_working_directory="${MY_EP_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_EP_OPERATOR amd64
    wait_for_resource "packagemanifest" "${MY_EP_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    ## Creating Event processing operator subscription
    local lf_operator_name="$MY_EP_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_EP_VERSION" ]; then
      export MY_EP_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_EP_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
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
      export MY_EP_AUTH_TYPE=OIDC
    else
      export MY_EP_AUTH_TYPE=LOCAL
    fi

    local lf_type="EventProcessing"
    local lf_cr_name="$MY_EP_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="EP-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.phase}"
    local lf_state="Running"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    # generate properties files
    adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-credentials.yaml
    adapt_file ${MY_EP_SCRIPTDIR}config/ ${MY_EP_GEN_CUSTOMDIR}config/ user-roles.yaml

    # user credentials
    local lf_varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-credentials.yaml" | base64 -w0)
    local lf_apply_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$lf_varb64\"}]'"
    local lf_delete_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"\"}]'"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-credentials" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-credentials.json\" ,\"value\" : \"$lf_varb64\"}]"

    # user roles
    lf_varb64=$(cat "${MY_EP_GEN_CUSTOMDIR}config/user-roles.yaml" | base64 -w0)
    local lf_apply_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]'"
    local lf_delete_cmd="oc -n $MY_OC_PROJECT patch secret ${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles --type='json' -p '[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"\"}]'"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc -n $MY_OC_PROJECT patch secret "${MY_EP_INSTANCE_NAME}-ibm-ep-user-roles" --type='json' -p "[{\"op\" : \"replace\" ,\"path\" : \"/data/user-mapping.json\" ,\"value\" : \"$lf_varb64\"}]"
    
    mylog info "Installation of evebt processing took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_ep
}

################################################
# Install Flink
function install_flink() {
  trace_in 3 install_flink

  if $MY_FLINK; then
    SECONDS=0

    mylog info "==== Installing CP4I Flink." 1>&2

    local lf_working_directory="${MY_FLINK_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    ## SB]20231020 For Flink and Event processing first you have to apply the catalog source to your cluster :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter Applying catalog sources to your cluster
    # event flink
    check_add_cs_ibm_pak $MY_FLINK_OPERATOR amd64
    wait_for_resource "packagemanifest" "${MY_FLINK_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    ## SB]20231020 For Flink and Event processing install the operator with the following command :
    ## https://ibm.github.io/event-automation/ep/installing/installing/, Chapter : Install the operator by using the CLI (oc ibm-pak)
    ## event flink
    ## Creating Eventautomation Flink operator subscription
    ## Creating Event processing operator subscription
    local lf_operator_name="$MY_FLINK_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    ## Creation of Event automation Flink PVC and instance
    # Even if it's a pvc we use the same generic function
    local lf_type="PersistentVolumeClaim"
    local lf_cr_name="ibm-flink-pvc"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="EA-Flink-PVC.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.phase}"
    local lf_state="Bound"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_FLINK_VERSION" ]; then
      export MY_FLINK_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_FLINK_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    ## SB]20231023 to check the status of created Flink instance : https://ibm.github.io/event-automation/ep/installing/post-installation/
    ## The status field displays the current state of the FlinkDeployment custom resource.
    ## When the Flink instance is ready, the custom resource displays status.lifecycleState: STABLE and status.jobManagerDeploymentStatus: READY.
    ## STANLE and READY (uppercase!!!)
    local lf_type="FlinkDeployment"
    local lf_cr_name="$MY_FLINK_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="EA-Flink-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.lifecycleState}-{.status.jobManagerDeploymentStatus}"
    local lf_state="STABLE-READY"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    
    mylog info "Installation of flink took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_flink
}

################################################
# Install Aspera HSTS
function install_hsts() {
  trace_in 3 install_hsts

  # ibm aspera hsts
  if $MY_HSTS; then
    SECONDS=0

    mylog info "==== Installing CP4I HSTS." 1>&2

    local lf_working_directory="${MY_HSTS_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # Asperac License
    export MY_ASPERA_LICENSE_FILE="${MY_PRIVATEDIR}aspera-license"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_HSTS_OPERATOR amd64
    wait_for_resource "packagemanifest" "${MY_HSTS_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating Aspera HSTS operator subscription
    local lf_operator_name="${MY_HSTS_OPERATOR}" 
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    local lf_type="IbmAsperaHsts"
    local lf_cr_name="$MY_HSTS_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="AsperaHSTS-Capability.yaml"
    local lf_namespace="${MY_OC_PROJECT}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.conditions[0].type}"
    local lf_state="Ready"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    
    mylog info "Installation of aspera hsts took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_hsts
}

################################################
# Install MQ
function install_mq() {
  trace_in 3 install_mq

  # ibm-mq
  if $MY_MQ; then
    SECONDS=0

    mylog info "==== Installing CP4I MQ." 1>&2

    local lf_working_directory="${MY_MQ_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_MQ_OPERATOR amd64
    export MY_MQ_VERSION=$VAR_APP_VERSION
    unset VAR_APP_VERSION
    wait_for_resource "packagemanifest" "${MY_MQ_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE

    # Creating MQ operator subscription
    local lf_operator_name="$MY_MQ_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    

    # Use the new CRD MessagingServer(available since CP4I 16.1.0-SC2) 
    if $MY_MESSAGINGSERVER; then
      # Creating MQ MessagingServer instance
      local lf_type="MessagingServer"
      local lf_cr_name="$MY_MSGSRV_INSTANCE_NAME"
      local lf_source_directory="${MY_OPERANDSDIR}"
      local lf_target_directory=$lf_working_directory
      local lf_yaml_file="MessagingServer-Capability.yaml"
      local lf_namespace="${MY_OC_PROJECT}"
      decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
      check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

      local lf_path="{.status.conditions[0].type}"
      local lf_state="Ready"
      #local lf_wait_for_state=true
      wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    fi
    
    mylog info "Installation of mq took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_mq
}

################################################
# Install Instana
# Voir ceci dans CP4I 16.1.1 : With the release of Cloud Pak for Integration 16.1.1 , Instana agents are now included in the Cloud Pak for Integration package. 
# https://www.ibm.com/docs/en/cloud-paks/cp-integration/16.1.1?topic=planning-licensing#instana__title__1
function install_instana() {
  trace_in 3 install_instana

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA; then
    SECONDS=0

    mylog info "==== Installing Instana." 1>&2
    
    # SB]20240629 Instana Agent key
    export MY_INSTANA_AGENT_KEY=$(cat "${MY_PRIVATEDIR}instana_agent_key.txt")
    export MY_INSTANA_EP_HOST=ingress-orange-saas.instana.io
    export MY_INSTANA_ZONE_NAME="${MY_USER_EMAIL%@*}"

    local lf_working_directory="${MY_INSTANA_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # Create namespace for Instana agent. The instana agent must be istalled in instana-agent namespace.
    create_project "$MY_INSTANA_AGENT_NAMESPACE" "$MY_INSTANA_AGENT_NAMESPACE project" "For monitoring with Instana" $lf_working_directory

    local lf_apply_cmd="oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy add-scc-to-user privileged -z instana-agent"
    local lf_delete_cmd="oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy remove-scc-from-user privileged -z instana-agent"
    append_to_file  "$lf_apply_cmd" $sc_install_executed_commands_file
    prepend_to_file  "$lf_delete_cmd" $sc_uninstall_executed_commands_file
    oc -n $MY_INSTANA_AGENT_NAMESPACE adm policy add-scc-to-user privileged -z instana-agent

    # Create a subscription object for instana Operator
    local lf_operator_name="$MY_INSTANA_OPERATOR"
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    local lf_operator_chl=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.defaultChannel')
    local lf_strategy="Automatic"
    local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\" \"${lf_work_dir}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"

    # Creating Instana agent
    local lf_type="daemonset"
    local lf_cr_name="$MY_INSTANA_INSTANCE_NAME"
    local lf_source_directory="${MY_OPERANDSDIR}"
    local lf_target_directory=$lf_working_directory
    local lf_yaml_file="Instana-Agent-CloudIBM-Capability.yaml"
    local lf_namespace="${MY_INSTANA_AGENT_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    local lf_path="{.status.numberReady}"
    local lf_state="$MY_CLUSTER_WORKERS"
    #local lf_wait_for_state=true
    wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"
    
    mylog info "Installation of instana took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_instana
}

################################################
# Install PostGreSQL cloudnative-pg, see https://github.com/cloudnative-pg/cloudnative-pg TODO This does not work
# SB]20241228 : after many tentatives to install PostgrSQL, getting errors (conflict errors, no operator errors, ...). I found that PostgreSQL operator
# is already installed and a subscription already exists (edb-keycloak)
#  !!! check to see how to use it because it's a pre requisite for installing IBM APIC Graphql
function install_postgresql() {
  trace_in 3 install_postgresql

  if $MY_POSTGRESQL; then
    SECONDS=0

    mylog info "==== Installing PostGreSQL." 1>&2

    local lf_working_directory="${MY_POSTGRESQL_WORKINGDIR}"
    check_directory_exist_create "${lf_working_directory}"

    # add catalog sources using ibm_pak plugin
    check_add_cs_ibm_pak $MY_POSTGRESQL_CASE amd64
    wait_for_resource "packagemanifest" "${MY_POSTGRESQL_OPERATOR}" $MY_CATALOGSOURCES_NAMESPACE
    #local lf_catalog_source_name=$VAR_CATALOG_SOURCE

    # Suppress the "" from the variable because when used in jq expression it does not return the expected value !
    local lf_catalog_source_name=${VAR_CATALOG_SOURCE//\"/}
    unset VAR_CATALOG_SOURCE

    # export this variable to be used in the postgresql database creation (choose the correct image)
    export MY_POSTGRESQL_CATALOGSOURCE_NAME=$lf_catalog_source_name

    # Create namespace for PostGreSQL.
    create_project "$MY_POSTGRESQL_NAMESPACE" "$MY_POSTGRESQL_NAMESPACE project" "For PostGreSQL" $lf_working_directory

    # Operator group for PostGreSQL in single namespace (TODO should it be operators.coreos.com/v1 instead of operators.coreos.com/v1alpha2)
    export MY_OPERATORGROUP="${MY_POSTGRESQL_OPERATORGROUP}"
    export MY_PROJECT="${MY_POSTGRESQL_NAMESPACE}"

    local lf_type="OperatorGroup"
    local lf_cr_name="${MY_POSTGRESQL_OPERATORGROUP}"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="operator-group-single.yaml"
    local lf_namespace="${MY_POSTGRESQL_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
    unset MY_OPERATORGROUP MY_PROJECT

    # Creating EDB Postgres for Kubernetes operator subscription
    local lf_operator_name=$MY_POSTGRESQL_OPERATOR
    local lf_operator_namespace=$MY_OPERATORS_NAMESPACE
    lf_operator_chl=$(oc get packagemanifest -o json | jq -r --arg op $lf_operator_name --arg cs $lf_catalog_source_name '.items[] | select(.metadata.name==$op and .status.catalogSource==$cs) | .status.defaultChannel')
    local lf_strategy="Automatic"
    #local lf_catalog_source_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status.catalogSource')
    #local lf_csv_name=$(oc -n $MY_CATALOGSOURCES_NAMESPACE get packagemanifest $lf_operator_name  -o json | jq -r '.status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_csv_name=$(oc get packagemanifest -o json | jq -r --arg op "$lf_operator_name" --arg cs "$lf_catalog_source_name" '.items[] | select(.metadata.name==$op and .status.catalogSource==$cs) | .status | .defaultChannel as $dc | .channels[] | select(.name == $dc) | .currentCSV')
    local lf_work_dir=$lf_working_directory
    decho 3 "create_operator_subscription \"${lf_operator_name}\" \"${lf_operator_namespace}\" \"${lf_operator_chl}\" \"${lf_strategy}\" \"${lf_catalog_source_name}\" \"${lf_csv_name}\""
    create_operator_subscription "${lf_operator_name}" "${lf_operator_namespace}" "${lf_operator_chl}" "${lf_strategy}" "${lf_catalog_source_name}" "${lf_csv_name}" "${lf_work_dir}"
    
    
    mylog info "Installation of postgresql took $SECONDS seconds." 1>&2
  fi

  trace_out 3 install_postgresql
}

################################################
# Customise ldap adding users and groups
function customise_openldap() {
  trace_in 3 customise_openldap

  if $MY_LDAP_CUSTOM; then
    mylog info "==== Customise ldap ()." 1>&2
    read_config_file "${MY_YAMLDIR}ldap/ldap.properties"
    check_file_exist ${MY_YAMLDIR}ldap/ldap-config.json
    check_file_exist ${MY_YAMLDIR}ldap/ldap-users.ldif
  fi

  trace_out 3 customise_openldap
}

################################################
# Customise Open Liberty
function customise_openliberty() {
  trace_in 3 customise_openliberty

  # backend J2EE applications
  if $MY_OPENLIBERTY_CUSTOM; then
  mylog info "==== Customise Open Liberty (olp.config.sh)." 1>&2
    . ${MY_OPENLIBERTY_SCRIPTDIR}scripts/olp.config.sh
  fi

  trace_out 3 customise_openliberty
}

################################################
# Customise WebSphere Liberty
function customise_wasliberty() {
  trace_in 3 customise_wasliberty

  if $MY_WASLIBERTY_CUSTOM; then
  mylog info "==== Customise WAS Liberty (was.config.sh)." 1>&2
    . ${MY_WASLIBERTY_SCRIPTDIR}scripts/was.config.sh
    fi

  trace_out 3 customise_wasliberty
}

################################################
# Customise ACE
function customise_ace() {
  trace_in 3 customise_ace

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_ACE_CUSTOM; then
    mylog info "==== Customise ACE (ace.config.sh)." 1>&2
    . ${MY_ACE_SCRIPTDIR}scripts/ace.config.sh
  fi

  trace_out 3 customise_ace
}

################################################
# Customise APIC
function customise_apic() {
  trace_in 3 customise_apic

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_APIC_CUSTOM; then
    mylog info "==== Customise APIC (apic.config.sh)." 1>&2
    . ${MY_APIC_SCRIPTDIR}scripts/apic.config.sh
  fi

  trace_out 3 customise_apic
}

################################################
# Customise IBM Event streams
function customise_es() {
  trace_in 3 customise_es

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

      local lf_working_directory="${MY_ES_WORKINGDIR}"
      check_directory_exist_create "${lf_working_directory}"

    # generate the differents properties files
    # SB]20231109 some generated files (yaml) are based on other generated files (properties), so :
    # - in template custom dirs, separate the files to two categories : scripts (*.properties) and config (*.yaml)
    # - generate first the *.properties files to be sourced then generate the *.yaml files
    check_directory_exist_create "${MY_ES_GEN_CUSTOMDIR}scripts"
    check_directory_exist_create "${MY_ES_GEN_CUSTOMDIR}config"
    generate_files $MY_ES_SCRIPTDIR $MY_ES_GEN_CUSTOMDIR false

    # SB]20231211 https://ibm.github.io/event-automation/es/installing/installing/
    # Question : Do we have to create this configmap before installing ES or even after ? Used for monitoring
    local lf_type="configmap"
    local lf_cr_name="cluster-monitoring-config"
    local lf_source_directory="${MY_RESOURCESDIR}"
    local lf_target_directory="${lf_working_directory}"
    local lf_yaml_file="openshift-monitoring-cm.yaml"
    local lf_namespace="${MY_OPENSHIFT_MONITORING_NAMESPACE}"
    decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
    check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

    . ${MY_ES_SCRIPTDIR}scripts/es.config.sh
  fi

  trace_out 3 customise_es
}

################################################
# Customise EEM
function customise_eem() {
  trace_in 3 customise_eem

  if $MY_EEM_CUSTOM; then
    mylog info "==== Customise Event Endpoint Management (eem.config.sh)." 1>&2
    # launch custom script
      . ${MY_EEM_SCRIPTDIR}scripts/eem.config.sh
  fi

  trace_out 3 customise_eem
}

################################################
# Customise EGW
function customise_egw() {
  trace_in 3 customise_egw

  if $MY_EGW_CUSTOM; then
    mylog info "==== Customise Event Endpoint Gateway ()." 1>&2
  fi

  trace_out 3 customise_egw
}

################################################
# Customise EP
function customise_ep() {
  trace_in 3 customise_ep

  local lf_in_ns=$1
  local varb64

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  ## Creating Event Processing users and roles
  if $MY_EP_CUSTOM; then
    mylog info "==== Customise Event Endpoint Processing ()." 1>&2
    # launch custom script
  fi

  trace_out 3 customise_ep
}

################################################
# Customise Flink
function customise_flink() {
  trace_in 3 customise_flink

  local lf_in_ns=$1
  if $MY_FLINK_CUSTOM; then
    mylog info "==== Customise Flink ()." 1>&2
  fi

  trace_out 3 customise_flink
}

################################################
# Customise Aspera HSTS
function customise_hsts() {
  trace_in 3 customise_hsts

  # ibm aspera hsts
  if $MY_HSTS_CUSTOM; then
    mylog info "==== Customise HSTS ()." 1>&2
  fi

  trace_out 3 customise_hsts
}

################################################
# Customise MQ
function customise_mq() {
  trace_in 3 customise_mq

  # Takes all the templates associated with the capabilities and generate the files from the context variables
  # The files are generated into ./customisation/working/<capability>/config
  if $MY_MQ_CUSTOM; then
 
    #SB]20240612 prise en compte de l'existence ou non de la variable portant la version
    if [ -z "$MY_MQ_VERSION" ]; then
      export MY_MQ_VERSION=$(oc ibm-pak list -o json | jq  --arg case "$MY_MQ_OPERATOR" '.[] | select (.name == $case ) | .latestAppVersion')
    fi

    # launch custom script
    mylog info "Customise MQ (mq.config.sh)."
   # . ${MY_MQ_SCRIPTDIR}scripts/mq.config.sh -i ${sc_properties_file} ${MY_MQ_INSTANCE_NAME}
    mylog info "Customise MQ (mq.demo.config.sh)."
    . ${MY_MQ_SCRIPTDIR}scripts/mq.demo.config.sh -i ${sc_properties_file} ${MY_MQ_INSTANCE_NAME}

  fi

  trace_out 3 customise_mq
}

################################################
# Customise Instana
function customise_instana() {
  trace_in 3 customise_instana

  # instana
  #SB]20230201 Ajout d'Instana
  # Creating Instana operator subscription
  if $MY_INSTANA_CUSTOM; then
    mylog info "==== Customise Instana ()." 1>&2
  fi

  trace_out 3 customise_instana
}

################################################
# Create a PostGreSQL DB
# @param 1: postgresql cluster name
# @param 2: postgresql database name
# @param 3: postgresql database username
# @param 4: postgresql database password
# @param 5: postgresql secret name
# @param 6: postgresql database description
# 
function create_postgresql_db() {
  trace_in 3 create_postgresql_db

  # local lf_in_cluster_name=$1 : pas besoin utiliser le cluster : MY_POSTGRESQL_CLUSTER
  # local lf_in_namespace=$ : pas besoin utiliser le ns : MY_POSTGRESQL_NAMESPACE

  local lf_working_directory="${MY_POSTGRESQL_WORKINGDIR}"
  check_directory_exist_create "${lf_working_directory}"

  create_project "$MY_POSTGRESQL_NAMESPACE" "PostGreSQL" "PostGreSQL DB namespace" $lf_working_directory
  add_ibm_entitlement "$MY_POSTGRESQL_NAMESPACE" $MY_CONTAINER_ENGINE

  local lf_in_cluster_name=$1
  local lf_in_db_name=$2
  local lf_in_db_username=$3
  local lf_in_db_password=$4
  local lf_in_secret_name=$5
  local lf_in_db_description=$6

  # Create a PostGreSQL DB secret
  local lf_username=$(echo -n "${lf_in_db_username}" | base64 -w0)
  local lf_password=$(echo -n "${lf_in_db_password}" | base64 -w0)
  local lf_secret_type="Opaque"

  export MY_SECRET_NAME=$lf_in_secret_name
  export MY_PROJECT=$MY_POSTGRESQL_NAMESPACE
  export MY_SECRET_TYPE=$lf_secret_type
  export MY_USERNAME=$lf_username
  export MY_PASSWORD=$lf_password
  
  local lf_type="Secret"
  local lf_cr_name="${lf_in_secret_name}"
  local lf_source_directory="${MY_RESOURCESDIR}"
  local lf_target_directory="${lf_working_directory}"
  local lf_yaml_file="secret.yaml"
  local lf_namespace=$MY_POSTGRESQL_NAMESPACE
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}" 
  unset MY_SECRET_NAME MY_PROJECT MY_SECRET_TYPE MY_USERNAME MY_PASSWORD

  # get the Postgresql image name version


  # PostGreSQL DB
  local lf_type="Cluster"
  local lf_cr_name="${lf_in_cluster_name}"
  local lf_source_directory="${MY_RESOURCESDIR}"
  local lf_target_directory="${lf_working_directory}"
  local lf_yaml_file="postgresql-cluster.yaml"
  local lf_namespace=$MY_POSTGRESQL_NAMESPACE

  export MY_POSTGRESQL_CLUSTER="${lf_in_cluster_name}"
  export MY_POSTGRESQL_DATABASE="${lf_in_db_name}"
  export MY_POSTGRESQL_USER="${lf_in_db_username}"
  export MY_POSTGRESQL_SECRET="${lf_in_secret_name}"
  export MY_POSTGRESQL_DESCRIPTION="${lf_in_db_description}"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}" 
  unset MY_POSTGRESQL_CLUSTER MY_POSTGRESQL_DATABASE MY_POSTGRESQL_USER MY_POSTGRESQL_SECRET

  #local lf_cr_name=$(oc -n $lf_namespace get $lf_type -o json | jq -r --arg my_resource "$lf_cr_name" '.items[0].metadata | select (.name | contains ($my_resource)).name')
  local lf_cr_name=$(oc -n $lf_namespace get $lf_type -o jsonpath="{.items[0].metadata.name}")
  local lf_path="{.status.conditions[0].type}"
  local lf_state="Ready"
  decho 3 "wait_for_state \"$lf_type $lf_cr_name is $lf_state\" \"$lf_state\" \"oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'\""
  wait_for_state "$lf_type $lf_cr_name $lf_path is $lf_state" "$lf_state" "oc -n $lf_namespace get $lf_type $lf_cr_name -o jsonpath='$lf_path'"

  # Authorize superuser access
  oc -n $lf_namespace patch $lf_type $lf_cr_name --type=merge -p '{"spec":{"enableSuperuserAccess":true}}' #| awk '{printf "%*s%s\n", NR * $SC_SPACES_COUNTER, "", $0}'

  # Here after how to check the status of the PostGreSQL DB and connect to it
  # oc run pg-check --image=postgres:15 --restart=Never -- sleep 3600
  # oc exec -it pg-check -- bash
  # psql -h <postgresql_svc> -U <postgres_user> -d <database_name> // password is asked
  # \q to quit

  trace_out 3 create_postgresql_db
}


################################################
# Display information to access CP4I
function display_access_info() {
  # To start displaying access info from the start of the line
  SC_SPACES_COUNTER=0
  trace_in 3 display_access_info

  mylog info "==== Displaying Access Info to CP4I." 1>&2

  # Initialisation of the bookmark
  echo ${BOOKMARK_PROLOGUE} > ${MY_WORKINGDIR}/bookmarks.html

  # Temporary access with Keycloack

  local lf_mailhog_hostname
  lf_mailhog_hostname=$(oc -n ${MY_MAIL_SERVER_NAMESPACE} get route mailhog -o jsonpath='{.spec.host}')
  mylog info "MailHog accessible at http://${lf_mailhog_hostname}"
  echo "<DT><A HREF=\"http://${lf_mailhog_hostname}\">MailHog</A>" >> ${MY_WORKINGDIR}/bookmarks.html

  lf_keycloak_admin_ui=$(oc -n $MY_COMMONSERVICES_NAMESPACE get route keycloak --template='{{ .spec.host }}')
  mylog info "Keycloak admin UI URL: " $lf_keycloak_admin_ui
  echo "<DT><A HREF=\"https://${lf_keycloak_admin_ui}\">Keycloak Admin UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  lf_keycloak_admin_pwd=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret cs-keycloak-initial-admin -o jsonpath={.data.password} | base64 -d)
  mylog info "Keycloak admin password: " $lf_keycloak_admin_pwd
  
  local lf_temp_integration_admin_pwd cp4i_url
  if $MY_NAVIGATOR_INSTANCE; then
    lf_temp_integration_admin_pwd=$(oc -n $MY_COMMONSERVICES_NAMESPACE get secret integration-admin-initial-temporary-credentials -o jsonpath={.data.password} | base64 -d)
    mylog info "Integration admin password: ${lf_temp_integration_admin_pwd}"
    cp4i_url=$(oc -n $MY_OC_PROJECT get platformnavigator cp4i-navigator -o jsonpath='{range .status.endpoints[?(@.name=="navigator")]}{.uri}{end}')
    mylog info "CP4I Platform UI URL: " $cp4i_url
    echo "<DT><A HREF=\"${cp4i_url}\">CP4I Platform UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html 
  fi

  local lf_ace_ui_db_url lf_ace_ui_dg_url
  if $MY_ACE; then
    lf_ace_ui_db_url=$(oc -n $MY_OC_PROJECT get Dashboard -o=jsonpath='{.items[?(@.kind=="Dashboard")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Dahsboard UI endpoint: " $lf_ace_ui_db_url
    echo "<DT><A HREF=\"${lf_ace_ui_db_url}\">ACE Dashboard UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_ace_ui_dg_url=$(oc -n $MY_OC_PROJECT get DesignerAuthoring -o=jsonpath='{.items[?(@.kind=="DesignerAuthoring")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "ACE Designer UI endpoint: " $lf_ace_ui_dg_url
    echo "<DT><A HREF=\"${lf_ace_ui_dg_url}\">ACE Designer UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  fi

  local lf_gtw_url lf_apic_gtw_admin_pwd_secret_name lf_cm_admin_pwd lf_cm_url lf_cm_admin_pwd_secret_name lf_cm_admin_pwd lf_mgr_url lf_ptl_url lf_jwks_url
  if $MY_APIC; then
    lf_gtw_url=$(oc -n $MY_OC_PROJECT get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "APIC Gateway endpoint: ${lf_gtw_url}"
    lf_gtw_webconsole_url=$(oc -n $MY_OC_PROJECT get Route ${MY_APIC_INSTANCE_NAME}-gw-webconsole -o=jsonpath='{.spec.host}')
    mylog info "APIC Gateway web console endpoint: ${lf_gtw_webconsole_url}"
    echo "<DT><A HREF=\"https://${lf_gtw_webconsole_url}\">APIC Gateway Web Console</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_apic_gtw_admin_pwd_secret_name=$(oc -n $MY_OC_PROJECT get GatewayCluster -o=jsonpath='{.items[?(@.kind=="GatewayCluster")].spec.adminUser.secretName}')
    lf_cm_admin_pwd=$(oc -n $MY_OC_PROJECT get secret ${lf_apic_gtw_admin_pwd_secret_name} -o jsonpath={.data.password} | base64 -d)
    mylog info "APIC Gateway admin password: ${lf_cm_admin_pwd}"
    lf_cm_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="admin")].uri}')
    mylog info "APIC Cloud Manager endpoint: ${lf_cm_url}"
    echo "<DT><A HREF=\"${lf_cm_url}\">APIC Cloud Manager UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_cm_admin_pwd_secret_name=$(oc -n $MY_OC_PROJECT get ManagementCluster -o=jsonpath='{.items[?(@.kind=="ManagementCluster")].spec.adminUser.secretName}')
    lf_cm_admin_pwd=$(oc -n $MY_OC_PROJECT get secret ${lf_cm_admin_pwd_secret_name} -o jsonpath='{.data.password}' | base64 -d)
    mylog info "APIC Cloud Manager admin password: ${lf_cm_admin_pwd}"
    lf_mgr_url=$(oc -n $MY_OC_PROJECT get APIConnectCluster -o=jsonpath='{.items[?(@.kind=="APIConnectCluster")].status.endpoints[?(@.name=="ui")].uri}')
    echo "<DT><A HREF=\"${lf_mgr_url}\">APIC API Manager UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
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
    echo  "<DT><A HREF=\"${lf_es_ui_url}\">Event Streams Management UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
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
    echo  "<DT><A HREF=\"${lf_eem_ui_url}\">Event Endpoint Management UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_eem_lf_gtw_url=$(oc -n $MY_OC_PROJECT get EventEndpointManagement -o=jsonpath='{.items[?(@.kind=="EventEndpointManagement")].status.endpoints[?(@.name=="gateway")].uri}')
    mylog info "Event Endpoint Management Gateway endpoint: ${lf_eem_lf_gtw_url}"
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi

  local lf_ep_ui_url
  if $MY_EP; then
    lf_ep_ui_url=$(oc -n $MY_OC_PROJECT get EventProcessing -o=jsonpath='{.items[?(@.kind=="EventProcessing")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Event Processing UI endpoint: ${lf_ep_ui_url}"
    echo "<DT><A HREF=\"${lf_ep_ui_url}\">Event Processing UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    mylog info "The credentials are defined in the file ./customisation/EP/config/user-credentials.yaml"
  fi
  
  local lf_ldap_hostname lf_ldap_port
  if $MY_LDAP; then
    read_config_file "${MY_YAMLDIR}ldap/ldap.properties"
    lf_ldap_hostname=$(oc -n ${MY_LDAP_NAMESPACE} get route openldap-external -o jsonpath='{.spec.host}')
    lf_ldap_port=$(oc -n ${MY_LDAP_NAMESPACE} get route openldap-external -o jsonpath='{.spec.port.targetPort}')
    mylog info "LDAP hostname:port: ${lf_ldap_hostname}:${lf_ldap_port}"
    echo  "<DT><A HREF=\"ldap://${lf_ldap_hostname}:${lf_ldap_port}\">LDAP</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    mylog info "LDAP admin dn/password: ${ldap_admin_dn}/${ldap_admin_password}"
  fi

  local lf_ar_ui_url
  if $MY_ASSETREPO; then
    lf_ar_ui_url=$(oc -n $MY_OC_PROJECT get AssetRepository -o=jsonpath='{.items[?(@.kind=="AssetRepository")].status.endpoints[?(@.name=="ui")].uri}')
    mylog info "Asset Repository UI endpoint: ${lf_ar_ui_url}"
    echo  "<DT><A HREF=\"${lf_ar_ui_url}\">Asset Repository UI</A>" >> ${MY_WORKINGDIR}/bookmarks.html
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
    echo  "<DT><A HREF=\"https://${lf_mq_admin_url}\">MQ Management Console</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  fi

  local lf_was_liberty_app_demo_url
  if $MY_WASLIBERTY_CUSTOM; then
    lf_was_liberty_app_demo_url=$(oc -n $MY_BACKEND_NAMESPACE get route demo -o jsonpath='{.status.ingress[0].host}')
    mylog info "WAS Liberty $MY_WASLIBERTY_APP_NAME application URL : https://${lf_was_liberty_app_demo_url}/$MY_WASLIBERTY_APP_NAME"
    echo "<DT><A HREF=\"https://${lf_was_liberty_app_demo_url}/$MY_WASLIBERTY_APP_NAME\">WAS Liberty $MY_WASLIBERTY_APP_NAME application</A>" >> ${MY_WORKINGDIR}/bookmarks.html
  fi

  local lf_licensing_service_url lf_licensing_secret_token lf_licensing_service_reporter_url lf_licensing_reporter_password
  if $MY_LIC_SRV; then
    lf_licensing_service_url=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get Route -o=jsonpath='{.items[?(@.metadata.name=="ibm-licensing-service-instance")].spec.host}')
    mylog info "Licensing service endpoint: https://${lf_licensing_service_url}"
    echo "<DT><A HREF=\"https://${lf_licensing_service_url}\">Licensing Service</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_licensing_secret_token=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get secret ibm-licensing-token -o jsonpath='{.data.token}' | base64 -d)
    mylog info "Licensing service token: ${lf_licensing_secret_token}"
    lf_licensing_service_reporter_url=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get Route ibm-lsr-console -o=jsonpath='{.status.ingress[0].host}')
    mylog info "Licensing service reporter console endpoint: https://${lf_licensing_service_reporter_url}/license-service-reporter/"
    echo "<DT><A HREF=\"https://${lf_licensing_service_reporter_url}/license-service-reporter/\">Licensing Service Reporter</A>" >> ${MY_WORKINGDIR}/bookmarks.html
    lf_licensing_reporter_password=$(oc -n ${MY_LICENSE_SERVICE_NAMESPACE} get secret ibm-license-service-reporter-credentials -o jsonpath='{.data.password}' | base64 -d)
    mylog info "Licensing service reporter credential: license-administrator/${lf_licensing_reporter_password}"
  fi

  echo ${BOOKMARK_EPILOGUE} >> ${MY_WORKINGDIR}/bookmarks.html

  trace_out 3 display_access_info
}

################################################
# function for the installtion of needed resources
# namespaces, operatorgroup, entitlement, ...
################################################
function install_needed_resources_part() {
  trace_in 3 install_needed_resources_part

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
  local lf_working_directory="${MY_CP4I_WORKINGDIR}"
  check_directory_exist_create "${lf_working_directory}"
  create_project "$MY_OC_PROJECT" "$MY_OC_PROJECT project" "For the Cloud Pak for Integration" $lf_working_directory

  # Add ibm entitlement key to namespace
  # SB]20230209 Aspera hsts service cannot be created because a problem with the entitlement, it must be added in the openshift-operators namespace.
  mylog info "Creating entitlement, need to check if it is needed or works"
  add_ibm_entitlement $MY_OC_PROJECT $MY_CONTAINER_ENGINE
  add_ibm_entitlement $MY_OPERATORS_NAMESPACE $MY_CONTAINER_ENGINE

  trace_out 3 install_needed_resources_part
}

################################################
# function for the installtion part of the script
################################################
function install_part() {
  trace_in 3 install_part

  # needed by other components
  install_cert_manager

  # Start by installing Redhat needed/useful features
  install_oadp
  install_gitops
  install_pipelines
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
  #create_keycloak_client
  install_ep
  install_flink
  install_hsts
  install_mq
  
  install_instana
  
  #install_postgresql
  
  install_apic_graphql

  install_cluster_monitoring

  #test_keycloak

  trace_out 3 install_part
}

################################################
# function for the customization part of the script
################################################
function customise_part() {
  trace_in 3 customise_part

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

  trace_out 3 customise_part
}

################################################
# ephemeral function to test some features
# here we will test keycloak configuration
# which needs :
# - installation of keycloak operator and operand
# - installation of PostgreSQL operator and creation of a database
# - setting up TLS Certificate and associated keys
#
function test_keycloak() {
  trace_in 3 test_keycloak

  local lf_working_directory="${MY_KEYCLOAK_WORKINGDIR}"
  check_directory_exist_create "${lf_working_directory}"

  # Start installation capabilities
  install_postgresql
  create_postgresql_db "keycloak-postgresql-cluster" "keycloak-db" "keycloak-pg-user" "keycloak-pg-password" "keycloak-pg-secret"
  install_keycloak

  # create keycloak tls secret
  local lf_username=$(echo -n "keycloak-pg-user" | base64 -w0)
  local lf_password=$(echo -n "keycloak-pg-password" | base64 -w0)
  local lf_secret_type="Opaque"

  export MY_SECRET_NAME=${MY_KEYCLOAK_DB_SECRET}
  export MY_PROJECT=$MY_KEYCLOAK_NAMESPACE
  export MY_SECRET_TYPE=$lf_secret_type
  export MY_USERNAME=$lf_username
  export MY_PASSWORD=$lf_password
  
  local lf_type="Secret"
  local lf_cr_name=${MY_KEYCLOAK_TLS_SECRET}
  local lf_source_directory="${MY_RESOURCESDIR}"
  local lf_target_directory="${lf_working_directory}"
  local lf_yaml_file="secret.yaml"
  local lf_namespace="${MY_KEYCLOAK_NAMESPACE}"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"
  unset MY_SECRET_NAME MY_PROJECT MY_SECRET_TYPE MY_USERNAME MY_PASSWORD
  
  # Creating keycloak route
  # first create a cluster issuer (this creates a simple self-signed issuer for the root certificate)
  local lf_type="Issuer"
  local lf_cr_name="${MY_ISSUER}"
  local lf_source_directory="${MY_RESOURCESDIR}"
  local lf_target_directory="${lf_working_directory}"
  local lf_yaml_file="self-signed-issuer.yaml"
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}"

  export MY_CLUSTER_DOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')

  # Add the certificate csr for routes
  local lf_type="Certificate"
  local lf_cr_name="keycloak-cert"
  local lf_source_directory="${MY_RESOURCESDIR}"
  local lf_target_directory="${lf_working_directory}"
  local lf_yaml_file="keycloak-csr.yaml"
  local lf_namespace=$MY_KEYCLOAK_NAMESPACE
  decho 3 "check_create_oc_yaml \"${lf_type}\" \"${lf_cr_name}\" \"${lf_source_directory}\" \"${lf_target_directory}\" \"${lf_yaml_file}\" \"${lf_namespace}\""
  check_create_oc_yaml "${lf_type}" "${lf_cr_name}" "${lf_source_directory}" "${lf_target_directory}" "${lf_yaml_file}" "${lf_namespace}"

  create_keycloak_instance "keycloak" "${MY_KEYCLOAK_NAMESPACE}" "keycloak-postgresql-cluster" "keycloak-pg-password" "${MY_KEYCLOAK_TLS_SECRET}"

  trace_out 3 test_keycloak
}

################################################
# Keycloak: Get an Admin Access Token
function get_access_token() {
  trace_in 3 get_access_token

  local lf_keycloak_admin
  local lf_keycloak_admin_password
  local lf_keycloak_host
  local lf_keycloak_access_token
  
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

  decho 3 "lf_keycloak_admin=$lf_keycloak_admin|lf_keycloak_admin_password=$lf_keycloak_admin_password|lf_keycloak_access_token=$lf_keycloak_access_token"
  export MY_ACCESS_TOKEN=$lf_keycloak_access_token  
  trace_out 3 get_access_token
}

################################################
# Keycloak: Get resources
function get_keycloak_resources() {
  trace_in 3 get_keycloak_resources

  local lf_in_keycloak_realm=$1

  local lf_working_directory="${MY_KEYCLOAK_WORKINGDIR}${lf_in_keycloak_realm}/"
  check_directory_exist_create "${lf_working_directory}"

  local lf_keycloak_admin
  local lf_keycloak_admin_password
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

# Get Realms resources
  curl -s -X GET "https://${lf_keycloak_host}/admin/realms" \
       -H "Authorization: Bearer $lf_keycloak_access_token" \
       -H "Content-Type: application/json" | jq  > "${lf_working_directory}realms.json"

  curl -s -X GET "https://${lf_keycloak_host}/admin/realms/${lf_in_keycloak_realm}" \
       -H "Authorization: Bearer $lf_keycloak_access_token" \
       -H "Content-Type: application/json" | jq  > "${lf_working_directory}${lf_in_keycloak_realm}.json"

  local lf_file="${MY_RESOURCESDIR}keycloak-resources.txt"
  while IFS= read -r line || [[ -n $line ]]; do
    # Trim leading and trailing whitespace
    local lf_trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Replace '/' with '_' to create the filename
    local lf_filename=$(echo "$lf_trimmed_line" | tr '/' '_')
    curl -s -X GET "https://${lf_keycloak_host}/admin/realms/${lf_in_keycloak_realm}/$lf_trimmed_line" \
         -H "Authorization: Bearer $lf_keycloak_access_token" \
         -H "Content-Type: application/json" | jq  > "${lf_working_directory}${lf_filename}.json"
  done < "$lf_file"

  trace_out 3 get_keycloak_resources
}

################################################
# function to run the whole script
function run_all() {
  trace_in 3 run_all

  # Start installation capabilities
  install_part
  
  # Start customization capabilities
  # No need to customise navigator, intassembly, assetrepo
  customise_part

  trace_out 3 run_all
}

################################################
# Function to process calls
function process_calls() {
  trace_in 3 process_calls

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
          trace_out 3 process_calls
          return 1
        fi
        #install_needed_resources_part
        $lf_func $lf_params
      else
        mylog error "Function '$lf_func' not found."
        lf_list=$(grep -E '^\s*(function\s+\w+|\w+\s*\(\))' $(basename "$0") | sed -E 's/^\s*(function\s+)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\2/')
        mylog info "Available functions are:"
        mylog info "$lf_list"
        trace_out 3 process_calls
        return 1
      fi
    done

  trace_out 3 process_calls
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
  trace_in 3 main

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
        install_needed_resources_part
        run_all
        shift
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
        trace_out 3 main
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
      trace_out 3 main
      return 1
    fi
  fi

  trace_out 3 main
  exit 0
}

################################################################################################
# Start of the script main entry
################################################################################################
# other example: ./provision_cluster-v2.sh --call <function_name1>, <function_name2>, ...
# other example: ./provision_cluster-v2.sh --all
#
export ADEBUG=1
export TECHZONE=true
export TRACELEVEL=4


# SB]20240404 Global Index sequence for incremental output for each function call
export SC_SPACES_COUNTER=0
export SC_SPACES_INCR=2
export SC_SPACES_INCR_INSIDE_FUNCTION=2

sc_parameters=./script-parameters.properties
sc_properties_file=./properties/cp4i.properties
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

# files containing the list of  executed commands
sc_install_executed_commands_file="${MY_WORKINGDIR}install_executed_commands.sh"
sc_uninstall_executed_commands_file="${MY_WORKINGDIR}uninstall_executed_commands.sh"
cat /dev/null > $sc_install_executed_commands_file
cat /dev/null > $sc_uninstall_executed_commands_file

# check the differents pre requisites
check_exec_prereqs
check_resource_exist storageclass $MY_BLOCK_STORAGE_CLASS
check_resource_exist storageclass $MY_FILE_STORAGE_CLASS
check_directory_exist_create "$MY_WORKINGDIR"

######################################################
# main entry
######################################################
main "$@"
