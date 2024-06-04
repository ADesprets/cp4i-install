# Set environment variables for the client
export MQCCDTURL=${MQ_GEN_CCDT_DIR}ccdt.json
export MQSSLKEYR=${MQ_GEN_KDB}
# check:
echo MQCCDTURL=$MQCCDTURL
ls -l $MQCCDTURL
echo MQSSLKEYR=$MQSSLKEYR
ls -l $MQSSLKEYR.*

# Get messages from the queue
amqsgetc Q1 $QMGR_UC