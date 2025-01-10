# EEM Usage

Check everything is ok
`oc exec $(kubectl get pod -l app.kubernetes.io/instance=cp4i-eem -n cp4i -o name) -n cp4i curl http://localhost:8081/ready`
where cp4i-eem is the instance name and cp4i is the namespave where EEM is installed.

``` json
{
  "code" : 200,
  "body" : {
    "components" : [ {
      "id" : "GatewayServices",
      "description" : "ok",
      "code" : 200,
      "conditions" : [ ]
    }, {
      "id" : "AdminService",
      "description" : "ok",
      "code" : 200,
      "conditions" : [ ]
    }, {
      "id" : "FileStorageProvider",
      "description" : "ok",
      "code" : 200,
      "conditions" : [ ]
    }, {
      "id" : "APIC_GATEWAY_REGISTRATION",
      "description" : "ok",
      "code" : 200,
      "conditions" : [ ]
    }, {
      "id" : "APIC Gateway Service",
      "description" : "ok",
      "code" : 200,
      "conditions" : [ ]
    }, {
      "id" : "EEMUI",
      "description" : "ok",
      "code" : 200,
      "conditions" : [ ]
    }, {
      "id" : "OperatorServices",
      "description" : "ok",
      "code" : 200,
      "conditions" : [ ]
    } ],
    "readyComponentCount" : 7,
    "notReadyComponentCount" : 0,
    "code" : 200,
    "status" : "ok"
  }
}
```

## Create topic

![EEM Add topic Step 1](../images/eem_create_topic-s1.png "EEM Add topic Step 1")

![EEM Add topic Step 2](../images/eem_create_topic-s2.png "EEM Add topic Step 2")

![EEM Add topic Step 3](../images/eem_create_topic-s3.png "EEM Add topic Step 3")

![EEM Add topic Step 4](../images/eem_create_topic-s4.png "EEM Add topic Step 4")

![EEM Add topic Step 5](../images/eem_create_topic-s5.png "EEM Add topic Step 5")

![EEM Add topic Step 6](../images/eem_create_topic-s6.png "EEM Add topic Step 6")

![EEM Add topic Step 7](../images/eem_create_topic-s7.png "EEM Add topic Step 7")

![EEM Add topic Step 8](../images/eem_create_topic-s8.png "EEM Add topic Step 8")

![EEM Add topic Step 9](../images/eem_create_topic-s9.png "EEM Add topic Step 9")

![EEM Add topic Step 10](../images/eem_create_topic-s10.png "EEM Add topic Step 10")

## Edit shcema information

Edit Schema and sample message

![EEM Edit schema on topic](../images/eem_edit_schema.png "EEM Edit schema on topic")

![EEM Edit sample on topic](../images/eem_edit_sample.png "EEM Edit sample on topic")

## Create option on topic

![EEM Add options Step 1](../images/eem_edit_option-s1.png "EEM Add options Step 1")

![EEM Add options Step 2](../images/eem_edit_option-s1.png "EEM Add options Step 2")

![EEM Add options Step 3](../images/eem_edit_option-s1.png "EEM Add options Step 3")

![EEM Add options Step 4](../images/eem_edit_option-s1.png "EEM Add options Step 4")

![EEM Add options Step 5](../images/eem_edit_option-s1.png "EEM Add options Step 5")

You create an option which contains controls.
A control is one of the following:

* Approval
* Quota enforcement
* Schema filtering
* Redaction

## Publish topic to gateway groups

![EEM Publish topic Step 1](../images/eem_publish-s1.png "EEM Publish topic Step 1")

![EEM Publish topic Step 2](../images/eem_publish-s2.png "EEM Publish topic Step 2")

![EEM Publish topic Step 3](../images/eem_publish-s3.png "EEM Publish topic Step 3")

## Subscribe to a Topic

![EEM Subscribe topic Step 1](../images/eem_subscribe-s1.png "EEM Subscribe topic Step 1")

![EEM Subscribe topic Step 2](../images/eem_subscribe-s2.png "EEM Subscribe topic Step 2")

This is the identity accessing Event Streams, so the client in Event Endpoint Management accessing Event Streams.

![EEM Subscribe topic Step 3](../images/eem_subscribe-s3.png "EEM Subscribe topic Step 3")

![EEM Subscribe topic Step 4](../images/eem_subscribe-s4.png "EEM Subscribe topic Step 4")

![EEM Subscribe topic Step 5](../images/eem_subscribe-s5.png "EEM Subscribe topic Step 5")

![EEM Subscribe topic Step 6](../images/eem_subscribe-s6.png "EEM Subscribe topic Step 6")

## Generate credentials

This is the identity accessing EEM, so the client of the Event Gateway.

![EEM Subscribe topic Step 7](../images/eem_subscribe-s7.png "EEM Subscribe topic Step 7")

![EEM Subscribe topic Step 9](../images/eem_subscribe-s9.png "EEM Subscribe topic Step 9")

![EEM Subscribe topic Step 10](../images/eem_subscribe-s10.png "EEM Subscribe topic Step 10")

![EEM Subscribe topic Step 11](../images/eem_subscribe-s11.png "EEM Subscribe topic Step 11")

## Use of the REST API

![IBM Event Automation demo](https://github.com/IBM/event-automation-demo/ "IBM Event Automation demo")

## Java client

We are using the code provided to acccess EEM topic.
