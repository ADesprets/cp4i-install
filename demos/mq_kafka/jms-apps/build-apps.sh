#!/bin/bash

# exit when any command fails
set -e

# allow this script to be run from other locations, despite the
#  relative file paths used in it
if [[ $BASH_SOURCE = */* ]]; then
  cd -- "${BASH_SOURCE%/*}/" || exit
fi

echo "--------------------------------------------------------------------------"
echo "Building the JMS apps that will put and get messages to the COMMANDS queue"
echo "--------------------------------------------------------------------------"

echo "> updating app config with hostname for queue manager"
MQHOST=$(oc get routes -nibmmq queuemanager-ibm-mq-qm -ojsonpath='{.spec.host}')
gsed -i -e 's/PLACEHOLDERHOSTNAME/'$MQHOST'/' mq-jms-simple/src/main/java/com/ibm/clientengineering/mq/samples/Config.java

echo "> building apps"
cd mq-jms-simple
mvn package

echo "----------------------------------------------------------------------"
echo "Apps are ready to run"
echo "----------------------------------------------------------------------"
