#!/bin/bash
#export MQCCDTURL=$MQCCDTURL
#export MQSSLKEYR=$MQSSLKEYR
#amqs${MQ_APP_LETTER}hac $QUEUE_TMPL $QMGR_TMPL

export MQCCDTURL=/home/saad/Mywork/Git/20240528-cp4i-install/customisation/working/MQ/generated/cp4iadmq/json/ccdt.json
export MQSSLKEYR=/home/saad/Mywork/Git/20240528-cp4i-install/customisation/working/MQ/generated/cp4iadmq/tls/clnt1/clnt1-keystore.kdb
amqsphac Q1 CP4IADMQ