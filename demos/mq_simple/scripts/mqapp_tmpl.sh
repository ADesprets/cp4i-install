#!/bin/bash
#export MQCCDTURL=$MQCCDTURL
#export MQSSLKEYR=$MQSSLKEYR
#amqs${MQ_APP_LETTER}hac $QUEUE_TMPL $QMGR_TMPL

export MQCCDTURL=${MY_MQ_WORKINGDIR}cp4iadmq/json/ccdt.json
export MQSSLKEYR=${MY_MQ_WORKINGDIR}cp4iadmq/tls/clnt1/clnt1-keystore.kdb
amqsphac Q1 CP4IADMQ
toto