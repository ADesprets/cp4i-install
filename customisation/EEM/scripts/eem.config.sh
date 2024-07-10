################################################################################################
# Start of the script main entry
# main

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

# load helper functions
. "${scriptdir}"lib.sh

#assumptions on the name of the file
read_config_file "${scriptdir}cp4i.properties"

read_config_file "${EEM_GEN_CUSTOMDIR}scripts/eem.properties"

SECONDS=0

duration=$SECONDS
mylog info "Configuration for Event Endpont Manager took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2