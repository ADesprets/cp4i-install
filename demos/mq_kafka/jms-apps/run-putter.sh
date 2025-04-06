#!/bin/bash

# exit when any command fails
set -e

# allow this script to be run from other locations, despite the
#  relative file paths used in it
if [[ $BASH_SOURCE = */* ]]; then
  cd -- "${BASH_SOURCE%/*}/" || exit
fi

echo "-----------------------------------------"
echo "Putting messages on to the COMMANDS queue"
echo "-----------------------------------------"

java -cp ./mq-jms-simple/target/mq-jms-simple-0.0.1.jar com.ibm.clientengineering.mq.samples.Putter

