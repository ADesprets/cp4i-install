# Set environment variables for the client
export MQCCDTURL=/home/saad/Mywork/Git/20240713-cp4i-install/customisation/ACE/scripts/../../../customisation/working/MQ/generated/cp4imq/json/ccdt.json
export MQSSLKEYR=/home/saad/Mywork/Git/20240713-cp4i-install/customisation/ACE/scripts/../../../customisation/working/MQ/generated/cp4imq/tls/clnt1/clnt1-keystore.kdb
# check:
echo MQCCDTURL=
ls -l 
echo MQSSLKEYR=
ls -l .*

# Get messages from the queue
amqsgetc Q1 CP4IMQ