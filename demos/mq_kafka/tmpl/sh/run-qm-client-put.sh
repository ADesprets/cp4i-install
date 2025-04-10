# Set environment variables for the client
export MQCCDTURL=${MQ_GEN_CCDT_DIR}ccdt.json
export MQSSLKEYR=${MQ_GEN_KDB}

# check:
echo MQCCDTURL=$MQCCDTURL
ls -l $MQCCDTURL
echo MQSSLKEYR=$MQSSLKEYR
ls -l $MQSSLKEYR.*

# Put messages to the queue
echo "Test message 1" | amqsputc Q1 $VAR_QMGR_UC
echo "Test message 2" | amqsputc Q1 $VAR_QMGR_UC