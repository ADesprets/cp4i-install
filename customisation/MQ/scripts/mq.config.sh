################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=$(dirname "$0")/
configdir="${scriptdir}../config/"
mainscriptdir="${scriptdir}../../../"

# load helper functions
. "${mainscriptdir}"lib.sh

read_config_file "${mainscriptdir}cp4i.properties"
read_config_file "${configdir}mq.properties"

# Creation d'un Queue Manager
SECONDS=0
check_create_oc_yaml "QueueManager" "QM1" "${configdir}QM1.yaml" $mq_project
check_resource_availability "QueueManager" "${mq_instance_name}-qm1" $mq_project
wait_for_oc_state QueueManager "${mq_instance_name}-qm1" "Running" '.status.phase' $mq_project
duration=$SECONDS
mylog info "Creation of the Queue Manager took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2