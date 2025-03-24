# qmhostname=`oc get route -n cp4i qm1-ibm-mq-qm -o jsonpath="{.spec.host}"`
# ping -c 1 $qmhostname

# Set environment variables for the client
export MQCCDTURL=${MQ_GEN_CCDT_DIR}ccdt.json
export MQSSLKEYR=${MQ_GEN_KDB}
# check:
echo MQCCDTURL=$MQCCDTURL
ls -l $MQCCDTURL
echo MQSSLKEYR=$MQSSLKEYR
ls -l $MQSSLKEYR.*

# Get messages from the queue
amqsbcgc Q1 $VAR_QMGR_UC