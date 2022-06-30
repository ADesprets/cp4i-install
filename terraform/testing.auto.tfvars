## terraform apply -var-file="testing.tfvars"

##############################################################################
## Global Variables
##############################################################################
#ibmcloud_api_key = ""      # Set the variable export TF_VAR_ibmcloud_api_key=
prefix         = "mytodo"
region         = "eu-de" # eu-de for Frankfurt MZR
resource_group = "cp4i"
tags           = ["tf", "cp4i"]


##############################################################################
## VPC
##############################################################################
vpc_classic_access            = false
vpc_address_prefix_management = "manual"
vpc_enable_public_gateway     = true


##############################################################################
## Cluster OpenShift
##############################################################################
openshift_cluster_name       = "cp4i-cluster"
openshift_worker_pool_flavor = "b3c.16x64"
openshift_version            = "4.10.17_openshift"
# Possible values: MasterNodeReady, OneWorkerNodeReady, or IngressReady
openshift_wait_till          = "IngressReady"
openshift_update_all_workers = false


##############################################################################
## COS
##############################################################################
cos_plan   = "standard"
cos_region = "global"


##############################################################################
## Observability: Log Analysis (LogDNA) & Monitoring (Sysdig)
##############################################################################
logdna_plan                 = "30-day"
logdna_enable_platform_logs = false

sysdig_plan                    = "graduated-tier-sysdig-secure-plus-monitor"
sysdig_enable_platform_metrics = false