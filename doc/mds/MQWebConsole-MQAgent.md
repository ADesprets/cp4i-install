# Proof of Technology: IBM MQ stand-alone Web Console and IBM MQ Agent on OpenShift

In this lab you install, step by step:

1. **Part A**: the IBM MQ **stand-alone Web Console** (the `mqweb` server shipped as a separate package). It runs in its own namespace and administers *remote* queue managers.
2. **Part B**: the IBM MQ **Agent**, an AI assistant that answers questions about your queue managers. It uses an IBM watsonx.ai model.
3. **Part C**: the **connection** between the two: an AI chat appears in the console.
4. **Part D** (optional): a second agent that uses your own **vLLM** server (or another OpenAI-compatible server) instead of watsonx.ai.

Each step gives a short explanation, then the commands to run. Run the commands in the same terminal: later steps use the variables defined in [Step 0](#step-0-prerequisites-and-variables).

```
 Browser ──► MQ Console (namespace ibmint-mqweb)
                 │  ├─ channel MQWEB.SVRCONN ──────────────► queue managers Orders, Sensors (namespace ibmint)
                 │  └─ AI chat (HTTPS + API key)
                 ▼
             MQ Agent (namespace ibmint-mqagent)
                 ├─ agent ──────────────────────────────────► watsonx.ai (gpt-oss-120b, granite-4-h-small)
                 └─ MCP server ── channel MQAGENT.SVRCONN ──► queue managers Orders, Sensors
```

## Step 0: prerequisites and variables

**What you need**

* An OpenShift cluster where the MQ Operator runs two TLS queue managers, `orders` (`Orders`) and `sensors` (`Sensors`), in namespace `ibmint`.
* On your workstation: `oc` (logged in as cluster administrator), `helm` (v3), `jq`, `openssl`, `curl`.
* The IBM MQ Web Server package `10.0.1.0-IBM-MQ-Web-Server-LinuxX64.tar.gz` (Fix Central), and the files `Containerfile` and `entrypoint.sh` provided with the lab.
* Your IBM entitlement key (container software library), and a watsonx.ai project in region **us-south** with its IBM Cloud API key.

**Variables**

Adapt the first lines to your environment, then run the whole block:

```bash
export LAB_DIR=~/mq-pot                        # working directory of the lab
export LAB_FILES=~/lab-files                   # Containerfile, entrypoint.sh and the MQ Web Server tarball
export MQ_NS=ibmint                            # namespace of the queue managers
export QMGRS="orders sensors"                  # QueueManager resources to work with
export MQWEB_NS=ibmint-mqweb                   # namespace of the console
export MQAGENT_NS=ibmint-mqagent               # namespace of the agent
export STORAGE_CLASS=ocs-storagecluster-ceph-rbd
export WATSONX_URL=https://us-south.ml.cloud.ibm.com
export WATSONX_PROJECT_ID=<your watsonx.ai project id>

mkdir -p $LAB_DIR && chmod 700 $LAB_DIR
export APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
echo "Cluster apps domain: $APPS_DOMAIN"
```

Put your keys in files, each key alone on one line, readable only by you:

```bash
( umask 077; vi $LAB_DIR/entitlement_key.txt )     # IBM entitlement key
( umask 077; vi $LAB_DIR/watsonx_api_key.txt )     # IBM Cloud API key of the watsonx.ai project
```

Check that the queue managers are running and use TLS (column `PKI` not empty):

```bash
oc -n $MQ_NS get queuemanager -o custom-columns=NAME:.metadata.name,QMGR:.spec.queueManager.name,PHASE:.status.phase,PKI:.spec.pki.keys[0].secret.secretName
```

---

# Part A: IBM MQ stand-alone Web Console

The MQ Operator does not deploy the stand-alone web server. You build an image from the IBM package and deploy it as a plain OpenShift Deployment. The console connects to each queue manager as an MQ client, through a dedicated channel described in a CCDT (Client Channel Definition Table).

## Step A1: create the namespace of the console

```bash
oc new-project $MQWEB_NS
```

## Step A2: create the console users' passwords

The console uses a Liberty *basic registry* with two users:

* `mqadmin`: administrator (role `MQWebAdmin`),
* `mqreader`: read-only (role `MQWebAdminRO`).

Their passwords are generated and stored in a Secret. The pod reads them as environment variables, so they never appear in a configuration file. The same Secret holds the password of the truststore that the console builds at startup.

```bash
oc -n $MQWEB_NS create secret generic mqweb-credentials \
  --from-literal=MQWEB_ADMIN_PWD=$(openssl rand -base64 18 | tr -d '/+=') \
  --from-literal=MQWEB_READER_PWD=$(openssl rand -base64 18 | tr -d '/+=') \
  --from-literal=MQWEB_TRUSTSTORE_PWD=$(openssl rand -base64 24 | tr -d '/+=')
```

## Step A3: prepare the queue managers for the console

On each queue manager, create:

* the server-connection channel `MQWEB.SVRCONN` (TLS),
* a channel authentication rule mapping every connection on this channel to the user `mqwebadm`,
* the authorities of `mqwebadm` (full administration through the console). The `@class` profiles give the right to *create* objects,
* the authorities of the console users on the queues: the messaging REST API acts as the logged-in user (`mqadmin`: all, `mqreader`: browse only).

First generate the MQSC script:

```bash
{
cat <<'EOF'
DEFINE CHANNEL('MQWEB.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) MCAUSER('mqwebadm') SSLCIPH('ANY_TLS12_OR_HIGHER') SSLCAUTH(OPTIONAL) REPLACE
SET CHLAUTH('MQWEB.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('*') USERSRC(MAP) MCAUSER('mqwebadm') ACTION(REPLACE)
SET AUTHREC OBJTYPE(QMGR) PRINCIPAL('mqwebadm') AUTHADD(ALL)
EOF
for T in QUEUE TOPIC CHANNEL CLNTCONN PROCESS NAMELIST AUTHINFO LISTENER SERVICE COMMINFO; do
  echo "SET AUTHREC PROFILE('**') OBJTYPE($T) PRINCIPAL('mqwebadm') AUTHADD(ALL)"
  echo "SET AUTHREC PROFILE('@class') OBJTYPE($T) PRINCIPAL('mqwebadm') AUTHADD(CRT)"
done
cat <<'EOF'
SET AUTHREC OBJTYPE(QMGR) PRINCIPAL('mqadmin') AUTHADD(CONNECT,INQ,DSP)
SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) PRINCIPAL('mqadmin') AUTHADD(ALL)
SET AUTHREC OBJTYPE(QMGR) PRINCIPAL('mqreader') AUTHADD(CONNECT,INQ,DSP)
SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) PRINCIPAL('mqreader') AUTHADD(BROWSE,INQ,DSP)
EOF
} > $LAB_DIR/mqweb.mqsc
cat $LAB_DIR/mqweb.mqsc
```

Then run it on each queue manager, in its active pod:

```bash
for QM in $QMGRS; do
  QMNAME=$(oc -n $MQ_NS get queuemanager $QM -o jsonpath='{.spec.queueManager.name}')
  POD=$(oc -n $MQ_NS get pod -l app.kubernetes.io/instance=$QM \
        -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -1)
  echo "=== $QMNAME (pod $POD)"
  oc -n $MQ_NS exec -i $POD -c qmgr -- runmqsc $QMNAME < $LAB_DIR/mqweb.mqsc | tail -3
done
```

The last line of each run must report `No commands have a syntax error`.

## Step A4: give the console the certificates of the queue managers

The channels use TLS: the console must trust the certificates of the queue managers. Copy the CA and server certificates of each queue manager into a Secret. At startup, the console imports every `.pem` file of this Secret into its truststore.

```bash
mkdir -p $LAB_DIR/mq-certs
for QM in $QMGRS; do
  S=$(oc -n $MQ_NS get queuemanager $QM -o jsonpath='{.spec.pki.keys[0].secret.secretName}')
  oc -n $MQ_NS get secret $S -o jsonpath='{.data.ca\.crt}'  | base64 -d > $LAB_DIR/mq-certs/$MQ_NS.$QM.ca.pem
  oc -n $MQ_NS get secret $S -o jsonpath='{.data.tls\.crt}' | base64 -d > $LAB_DIR/mq-certs/$MQ_NS.$QM.tls.pem
done
ls $LAB_DIR/mq-certs
oc -n $MQWEB_NS create secret generic mqweb-mq-certs --from-file=$LAB_DIR/mq-certs/
```

## Step A5: describe the queue managers in CCDT files

Each queue manager gets a JSON CCDT named `<queue manager name>.json`. It points to the **internal service** of the queue manager (`<resource>-ibm-mq.<namespace>.svc.cluster.local:1414`), so no OpenShift route is involved. At startup the console registers one remote queue manager per file.

```bash
mkdir -p $LAB_DIR/ccdt
for QM in $QMGRS; do
  QMNAME=$(oc -n $MQ_NS get queuemanager $QM -o jsonpath='{.spec.queueManager.name}')
  jq -n --arg qm "$QMNAME" --arg host "$QM-ibm-mq.$MQ_NS.svc.cluster.local" \
    '{channel: [{name: "MQWEB.SVRCONN", type: "clientConnection",
                 clientConnection: {connection: [{host: $host, port: 1414}], queueManager: $qm},
                 connectionManagement: {heartbeatInterval: 30},
                 transmissionSecurity: {cipherSpecification: "ANY_TLS12_OR_HIGHER"}}]}' > $LAB_DIR/ccdt/$QMNAME.json
done
cat $LAB_DIR/ccdt/*.json
oc -n $MQWEB_NS create configmap mqweb-ccdt --from-file=$LAB_DIR/ccdt/
```

## Step A6: configure the security of the console

The file `mqwebuser.xml` defines the users and maps them to the roles of the console (`MQWebAdmin`, `MQWebAdminRO`, `MQWebUser`) for the console application and the messaging REST API. `${env.MQWEB_ADMIN_PWD}` is resolved by Liberty from the environment of the pod (Step A2).

```bash
cat > $LAB_DIR/mqwebuser.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<server>
  <featureManager>
    <feature>appSecurity-2.0</feature>
    <feature>basicAuthenticationMQ-1.0</feature>
  </featureManager>
  <enterpriseApplication id="com.ibm.mq.console">
    <application-bnd>
      <security-role name="MQWebAdmin"><group name="MQWebAdminGroup" realm="defaultRealm"/></security-role>
      <security-role name="MQWebAdminRO"><group name="MQWebAdminROGroup" realm="defaultRealm"/></security-role>
      <security-role name="MQWebUser"><special-subject type="ALL_AUTHENTICATED_USERS"/></security-role>
    </application-bnd>
  </enterpriseApplication>
  <enterpriseApplication id="com.ibm.mq.rest">
    <application-bnd>
      <security-role name="MQWebAdmin"><group name="MQWebAdminGroup" realm="defaultRealm"/></security-role>
      <security-role name="MQWebAdminRO"><group name="MQWebAdminROGroup" realm="defaultRealm"/></security-role>
      <security-role name="MQWebUser"><special-subject type="ALL_AUTHENTICATED_USERS"/></security-role>
    </application-bnd>
  </enterpriseApplication>
  <basicRegistry id="basic" realm="defaultRealm">
    <user name="mqadmin" password="${env.MQWEB_ADMIN_PWD}"/>
    <user name="mqreader" password="${env.MQWEB_READER_PWD}"/>
    <group name="MQWebAdminGroup"><member name="mqadmin"/></group>
    <group name="MQWebAdminROGroup"><member name="mqreader"/></group>
  </basicRegistry>
  <variable name="httpHost" value="*"/>
</server>
EOF
oc -n $MQWEB_NS create configmap mqweb-config --from-file=mqwebuser.xml=$LAB_DIR/mqwebuser.xml
```

## Step A7: build the console image

The image is built **in the cluster** (OpenShift BuildConfig, Docker strategy) from three files:

* `mqweb.tar.gz`: the IBM MQ Web Server package,
* `Containerfile`: UBI 9 minimal image, extracts the package, accepts the license, makes the paths writable for the random user of OpenShift,
* `entrypoint.sh`: at each start, applies `mqwebuser.xml`, rebuilds the truststore from `/mq-certs`, registers each CCDT of `/ccdt` with `setmqweb remote add`, connects the console to the MQ Agent when its settings are present (Part C), then starts the server.

```bash
mkdir -p $LAB_DIR/build
cp $LAB_FILES/Containerfile $LAB_FILES/entrypoint.sh $LAB_DIR/build/
cp $LAB_FILES/10.0.1.0-IBM-MQ-Web-Server-LinuxX64.tar.gz $LAB_DIR/build/mqweb.tar.gz

oc -n $MQWEB_NS apply -f - <<EOF
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: mqweb
---
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: mqweb
spec:
  source:
    type: Binary
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Containerfile
  output:
    to:
      kind: ImageStreamTag
      name: mqweb:10.0
EOF

oc -n $MQWEB_NS start-build mqweb --from-dir=$LAB_DIR/build --follow --wait
```

The build takes a few minutes and ends with `Push successful`.

## Step A8: deploy the console

Create:

* a PersistentVolumeClaim: the server configuration and the registered queue managers survive restarts,
* the Deployment: one replica, with the Secrets and ConfigMaps of the previous steps mounted. The `mqweb-agent` Secret is optional: it is created in Part C,
* a Service and a Route. The route uses `passthrough` TLS: the browser talks HTTPS directly to the console.

```bash
oc -n $MQWEB_NS apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mqweb-data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mqweb
  labels:
    app: mqweb
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: mqweb
  template:
    metadata:
      labels:
        app: mqweb
    spec:
      containers:
        - name: mqweb
          image: image-registry.openshift-image-registry.svc:5000/$MQWEB_NS/mqweb:10.0
          imagePullPolicy: Always
          ports:
            - name: https
              containerPort: 9443
          envFrom:
            - secretRef:
                name: mqweb-credentials
          env:
            - name: MQWEB_AGENT_HOSTNAME
              valueFrom:
                secretKeyRef: {name: mqweb-agent, key: MQWEB_AGENT_HOSTNAME, optional: true}
            - name: MQWEB_AGENT_APIKEY
              valueFrom:
                secretKeyRef: {name: mqweb-agent, key: MQWEB_AGENT_APIKEY, optional: true}
          resources:
            requests: {cpu: 200m, memory: 512Mi}
            limits: {cpu: "1", memory: 1Gi}
          readinessProbe:
            tcpSocket: {port: 9443}
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            tcpSocket: {port: 9443}
            initialDelaySeconds: 120
            periodSeconds: 20
          volumeMounts:
            - {name: data, mountPath: /var/mqweb}
            - {name: config, mountPath: /config}
            - {name: ccdt, mountPath: /ccdt}
            - {name: mq-certs, mountPath: /mq-certs}
            - {name: mq-agent, mountPath: /mq-agent}
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: mqweb-data}
        - name: config
          configMap: {name: mqweb-config}
        - name: ccdt
          configMap: {name: mqweb-ccdt}
        - name: mq-certs
          secret: {secretName: mqweb-mq-certs}
        - name: mq-agent
          secret:
            secretName: mqweb-agent
            optional: true
            items: [{key: ca.crt, path: ca.crt}]
---
apiVersion: v1
kind: Service
metadata:
  name: mqweb
spec:
  selector:
    app: mqweb
  ports:
    - {name: https, port: 9443, targetPort: 9443}
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: mqweb
spec:
  to:
    kind: Service
    name: mqweb
  port:
    targetPort: https
  tls:
    termination: passthrough
EOF

oc -n $MQWEB_NS rollout status deployment/mqweb --timeout=600s
```

## Step A9: check and log in

The start-up log shows the certificates imported and the queue managers registered:

```bash
oc -n $MQWEB_NS logs deployment/mqweb | grep '\[entrypoint\]'
```

Get the URL and the password of `mqadmin`:

```bash
echo "https://$(oc -n $MQWEB_NS get route mqweb -o jsonpath='{.spec.host}')/ibmmq/console/"
oc -n $MQWEB_NS get secret mqweb-credentials -o jsonpath='{.data.MQWEB_ADMIN_PWD}' | base64 -d; echo
```

Open the URL, accept the self-signed certificate of the console, and log in as `mqadmin`. The `Orders` and `Sensors` queue managers are listed as remote queue managers. Open one and look at its queues.

On the queue manager side, the console connection is visible:

```bash
POD=$(oc -n $MQ_NS get pod -l app.kubernetes.io/instance=orders -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -1)
echo "DISPLAY CHSTATUS('MQWEB.SVRCONN') MCAUSER" | oc -n $MQ_NS exec -i $POD -c qmgr -- runmqsc Orders
```

Log out and log in again as `mqreader` (password `MQWEB_READER_PWD`): the objects are visible but cannot be changed.

---

# Part B: IBM MQ Agent

The agent is installed with the Helm chart `ibm-mq-agent`. Its pod has three containers:

* **agent**: the AI assistant. It calls the watsonx.ai models and exposes an HTTPS API (A2A protocol) used by the console,
* **MCP server**: connects to the queue managers as an MQ client and gives the agent its tools (display queues, channels, error logs...),
* **embedding service**: a local model used to search the MQ documentation.

Models (validated by IBM): `openai/gpt-oss-120b` (main reasoning model) and `ibm/granite-4-h-small` (lighter tasks), both available in us-south.

## Step B1: create the namespace of the agent and the pull secret

The agent images are in the IBM entitled registry `cp.icr.io`.

```bash
oc new-project $MQAGENT_NS
oc -n $MQAGENT_NS create secret docker-registry ibm-entitlement-key \
  --docker-server=cp.icr.io --docker-username=cp --docker-password="$(tr -d '\r\n' < $LAB_DIR/entitlement_key.txt)"
```

## Step B2: check the access to watsonx.ai

Before deploying, check the three causes of failure seen most often: an invalid API key, a region without the models, and a project not associated with a watsonx.ai Runtime instance.

1. Get an IAM token from the API key (the key is sent through stdin, not on the command line):

```bash
export WX_TOKEN=$(tr -d '\r\n' < $LAB_DIR/watsonx_api_key.txt | curl -s -X POST https://iam.cloud.ibm.com/identity/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ibm:params:oauth:grant-type:apikey" --data-urlencode "apikey@-" | jq -r '.access_token // empty')
[[ -n $WX_TOKEN ]] && echo "IAM token OK" || echo "Invalid API key"
```

2. Check that the region provides the models:

```bash
curl -s "$WATSONX_URL/ml/v1/foundation_model_specs?version=2024-05-01&limit=200" | jq -r '.resources[].model_id' \
  | grep -E '^(openai/gpt-oss-120b|ibm/granite-4-h-small)$'
```

Both models must be listed.

3. Send a minimal chat to the main model in your project:

```bash
curl -s -X POST "$WATSONX_URL/ml/v1/text/chat?version=2024-05-01" \
  -H "Authorization: Bearer $WX_TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg p "$WATSONX_PROJECT_ID" '{model_id: "openai/gpt-oss-120b", project_id: $p, max_tokens: 50,
                                              messages: [{role: "user", content: "Reply with OK"}]}')" \
  | jq '.choices[0].message.content // .errors'
```

An answer (not an error) means the project is ready. The error `project_id ... is not associated with a WML instance` means the project must be associated with a watsonx.ai Runtime (project > Manage > Services & integrations).

## Step B3: give the agent read access to the queue managers

The MCP server connects through a dedicated channel `MQAGENT.SVRCONN`, mapped to the user `mqagent`. This user only gets **read** authorities:

* connect, inquire and display the queue manager, read its error logs (`CTRL`),
* send read-only PCF commands (`SYSTEM.ADMIN.COMMAND.QUEUE`) and get their responses (`SYSTEM.DEFAULT.MODEL.QUEUE`),
* display and browse all the queues, display all the other objects.

```bash
{
cat <<'EOF'
DEFINE CHANNEL('MQAGENT.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) SSLCIPH('ANY_TLS12_OR_HIGHER') SSLCAUTH(OPTIONAL) REPLACE
SET CHLAUTH('MQAGENT.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('*') USERSRC(MAP) MCAUSER('mqagent') ACTION(REPLACE)
SET AUTHREC OBJTYPE(QMGR) PRINCIPAL('mqagent') AUTHADD(CONNECT,CTRL,INQ,DSP)
SET AUTHREC PROFILE('SYSTEM.ADMIN.COMMAND.QUEUE') OBJTYPE(QUEUE) PRINCIPAL('mqagent') AUTHADD(DSP,INQ,PUT)
SET AUTHREC PROFILE('SYSTEM.DEFAULT.MODEL.QUEUE') OBJTYPE(QUEUE) PRINCIPAL('mqagent') AUTHADD(DSP,GET)
SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) PRINCIPAL('mqagent') AUTHADD(DSP,BROWSE)
EOF
for T in CHANNEL CLNTCONN TOPIC PROCESS NAMELIST AUTHINFO LISTENER SERVICE COMMINFO; do
  echo "SET AUTHREC PROFILE('**') OBJTYPE($T) PRINCIPAL('mqagent') AUTHADD(DSP)"
done
} > $LAB_DIR/mqagent.mqsc

for QM in $QMGRS; do
  QMNAME=$(oc -n $MQ_NS get queuemanager $QM -o jsonpath='{.spec.queueManager.name}')
  POD=$(oc -n $MQ_NS get pod -l app.kubernetes.io/instance=$QM \
        -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -1)
  echo "=== $QMNAME (pod $POD)"
  oc -n $MQ_NS exec -i $POD -c qmgr -- runmqsc $QMNAME < $LAB_DIR/mqagent.mqsc | tail -3
done
```

## Step B4: CCDT of the MCP server

Unlike the console, the MCP server reads **one** CCDT listing all the queue managers (at most 20).

```bash
for QM in $QMGRS; do
  QMNAME=$(oc -n $MQ_NS get queuemanager $QM -o jsonpath='{.spec.queueManager.name}')
  jq -n --arg qm "$QMNAME" --arg host "$QM-ibm-mq.$MQ_NS.svc.cluster.local" \
    '{name: "MQAGENT.SVRCONN", type: "clientConnection",
      clientConnection: {connection: [{host: $host, port: 1414}], queueManager: $qm},
      connectionManagement: {heartbeatInterval: 30},
      transmissionSecurity: {cipherSpecification: "ANY_TLS12_OR_HIGHER"}}'
done | jq -s '{channel: .}' > $LAB_DIR/mqagent-ccdt.json
cat $LAB_DIR/mqagent-ccdt.json
oc -n $MQAGENT_NS create configmap mqagent-ccdt --from-file=ccdt.json=$LAB_DIR/mqagent-ccdt.json
```

## Step B5: key store of the MCP server

The MCP server needs a PKCS#12 key store containing the CA that signed the queue manager certificates. The key store is created with `runmqakm`, the MQ certificate tool. It is available in the queue manager container, so you don't need an MQ client on your workstation: the CA is sent to the pod, and the key store comes back encoded in base64.

In this lab both queue managers share the same CA, so it is added once. With different CAs, add each CA with its own `-label`.

```bash
export KS_PWD=$(openssl rand -hex 12)
S=$(oc -n $MQ_NS get queuemanager orders -o jsonpath='{.spec.pki.keys[0].secret.secretName}')
oc -n $MQ_NS get secret $S -o jsonpath='{.data.ca\.crt}' | base64 -d > $LAB_DIR/qm-ca.pem
POD=$(oc -n $MQ_NS get pod -l app.kubernetes.io/instance=orders -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -1)

oc -n $MQ_NS exec -i $POD -c qmgr -- bash -c "cat > /tmp/qm-ca.pem \
  && runmqakm -keydb -create -db /tmp/agent-ks.p12 -pw $KS_PWD -type pkcs12 > /dev/null \
  && runmqakm -cert -add -db /tmp/agent-ks.p12 -pw $KS_PWD -label qm-ca -file /tmp/qm-ca.pem -format ascii \
  && base64 -w0 /tmp/agent-ks.p12; rm -f /tmp/agent-ks.* /tmp/qm-ca.pem" < $LAB_DIR/qm-ca.pem | base64 -d > $LAB_DIR/keystore.p12

ls -l $LAB_DIR/keystore.p12
oc -n $MQAGENT_NS create secret generic mqagent-qm-keystore \
  --from-file=keystore.p12=$LAB_DIR/keystore.p12 --from-literal=password=$KS_PWD
```

## Step B6: configuration of the MCP server

No credentials are needed: the channel maps every connection to `mqagent` (Step B3). The configuration only enables the `/health` route of the MCP server.

```bash
cat > $LAB_DIR/mcpconfig.ini <<'EOF'
[mqenv]
# No credentials: the channel MQAGENT.SVRCONN maps every connection to mqagent
[routes]
health = enabled
EOF
oc -n $MQAGENT_NS create secret generic mqagent-mcp-configuration --from-file=mcpconfig.ini=$LAB_DIR/mcpconfig.ini
```

## Step B7: TLS certificate of the agent

The agent serves HTTPS with its own certificate, created by cert-manager:

1. a self-signed issuer,
2. a CA certificate signed by it,
3. an issuer using this CA,
4. the server certificate of the agent, valid for its route (`ibm-mq-agent-mqagent-<namespace>.<apps domain>`) and its internal service.

The console will trust the CA (Part C).

```bash
oc -n $MQAGENT_NS apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: mqagent-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mqagent-ca
spec:
  isCA: true
  commonName: mqagent-ca
  secretName: mqagent-ca-secret
  duration: 8760h
  privateKey: {algorithm: RSA, size: 4096}
  issuerRef: {kind: Issuer, name: mqagent-selfsigned}
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: mqagent-ca-issuer
spec:
  ca:
    secretName: mqagent-ca-secret
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mqagent-tls
spec:
  commonName: ibm-mq-agent-mqagent
  dnsNames:
    - ibm-mq-agent-mqagent-$MQAGENT_NS.$APPS_DOMAIN
    - ibm-mq-agent-mqagent.$MQAGENT_NS.svc.cluster.local
  secretName: mqagent-tls
  duration: 8760h
  privateKey: {algorithm: RSA, size: 2048}
  usages: [server auth, digital signature, key encipherment]
  issuerRef: {kind: Issuer, name: mqagent-ca-issuer}
EOF

oc -n $MQAGENT_NS wait certificate/mqagent-ca certificate/mqagent-tls --for=condition=Ready --timeout=120s
```

## Step B8: install the agent with Helm

The values file connects everything: the watsonx.ai runtime and the models, the TLS Secret, and the CCDT, key store and configuration of the MCP server. The two secrets (watsonx API key and key store password) are **not** written in this file: they are given to Helm through a pipe.

```bash
helm repo add ibm-helm https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm --force-update
helm repo update ibm-helm

cat > $LAB_DIR/mqagent-values.yaml <<EOF
license:
  accept: true
  license: L-CXDB-XTZ9J8
agent:
  identifier: mqagent
  model:
    providers:
      myWatsonxRuntime:
        type: watsonxService
        uri: $WATSONX_URL
        watsonxService:
          projectID: $WATSONX_PROJECT_ID
    defaultProvider: myWatsonxRuntime
    roles:
      primaryLLM:
        modelId: "openai/gpt-oss-120b"
      secondaryLLM:
        enabled: true
        modelId: "ibm/granite-4-h-small"
  tlsSecretName: mqagent-tls
mcpServer:
  ccdtConfigMapName: mqagent-ccdt
  keyStoreSecretName: mqagent-qm-keystore
  configurationSecretName: mqagent-mcp-configuration
route:
  enabled: true
EOF

KS_PWD=$(oc -n $MQAGENT_NS get secret mqagent-qm-keystore -o jsonpath='{.data.password}' | base64 -d)
helm upgrade --install mqagent ibm-helm/ibm-mq-agent --version 2.1.0 -n $MQAGENT_NS \
  -f $LAB_DIR/mqagent-values.yaml \
  -f <(KS_PWD=$KS_PWD jq -n --rawfile k $LAB_DIR/watsonx_api_key.txt \
         '{agent: {model: {providers: {myWatsonxRuntime: {watsonxService: {key: ($k | gsub("[\r\n]"; ""))}}}}},
           mcpServer: {keyStorePassword: $ENV.KS_PWD}}')

oc -n $MQAGENT_NS rollout status deployment/ibm-mq-agent-mqagent --timeout=900s
oc -n $MQAGENT_NS get pods
```

The first start takes several minutes (image pull). One restart of the `agent` container is normal: it waits at most 120 seconds for the MCP server.

## Step B9: ask the agent a question, without the console

The agent speaks the A2A protocol over HTTPS. Clients authenticate with an API key, generated by the chart in a Secret. The key of user `mqagent` is the one the console will use.

```bash
export AGENT_HOST=$(oc -n $MQAGENT_NS get route ibm-mq-agent-mqagent -o jsonpath='{.spec.host}')
oc -n $MQAGENT_NS get secret mqagent-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > $LAB_DIR/agent-ca.crt
export AGENT_KEY=$(oc -n $MQAGENT_NS get secret ibm-mq-agent-mqagent-api-key-file -o jsonpath='{.data.api\.key}' | base64 -d \
                   | jq -r '.[] | select(.user == "mqagent") | .key')

# Agent card: name, skills, endpoints
curl -s --cacert $LAB_DIR/agent-ca.crt https://$AGENT_HOST/.well-known/agent-card.json | jq '{name, description, skills: [.skills[]?.name]}'

# Question
curl -s --max-time 300 --cacert $LAB_DIR/agent-ca.crt -X POST https://$AGENT_HOST/a2a/message:send \
  -H "Content-Type: application/json" -H "A2A-Version: 1.0" -H @<(printf 'x-api-key: %s\n' "$AGENT_KEY") \
  -d '{"message": {"messageId": "1", "role": "ROLE_USER", "parts": [{"text": "List the local queues defined on queue manager Orders with their current depth."}]}}' \
  | jq -r '.task.status.state, ([.. | .text? // empty] | .[0])'
```

`TASK_STATE_COMPLETED` followed by a list of queues means the whole chain works: watsonx.ai, MCP server, channel and authorities. The MCP server connection is visible on the queue manager:

```bash
POD=$(oc -n $MQ_NS get pod -l app.kubernetes.io/instance=orders -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -1)
echo "DISPLAY CHSTATUS('MQAGENT.SVRCONN') MCAUSER" | oc -n $MQ_NS exec -i $POD -c qmgr -- runmqsc Orders
```

---

# Part C: connect the console to the agent

The console needs three things to call the agent: its URL, the API key of user `mqagent`, and the CA of its certificate. They go in the Secret `mqweb-agent`, which the console Deployment already references (Step A8). At startup, `entrypoint.sh`:

* sets the console properties `agentHostname` and `agentAPIKey` (`setmqweb properties`). The key stays in the environment, it is not written in `mqwebuser.xml`,
* adds the CA of the agent to the default truststore of the console (`key.p12`).

## Step C1: create the Secret and restart the console

```bash
oc -n $MQWEB_NS create secret generic mqweb-agent \
  --from-literal=MQWEB_AGENT_HOSTNAME=https://$AGENT_HOST \
  --from-literal=MQWEB_AGENT_APIKEY="$AGENT_KEY" \
  --from-file=ca.crt=$LAB_DIR/agent-ca.crt

oc -n $MQWEB_NS rollout restart deployment/mqweb
oc -n $MQWEB_NS rollout status deployment/mqweb --timeout=600s
oc -n $MQWEB_NS logs deployment/mqweb | grep '\[entrypoint\]'
```

The log must show `Connecting the console to the IBM MQ Agent https://ibm-mq-agent-mqagent-...`. If it also shows `WARNING: CA of the agent not added`, the default truststore did not exist yet (first start of the console): restart the console once more.

## Step C2: use the AI chat of the console

Reload the console (`https://<console route>/ibmmq/console/`, as `mqadmin`). An **AI chat icon** appears at the bottom right. Some questions to try:

* *How many queue managers can you access, and what are their names?*
* *List the local queues of Orders with their current depth.*
* *Are there messages on the dead-letter queue of Sensors?*
* *Show the status of the channels of Orders.*
* *Are there recent errors in the error logs of Sensors?*

Each answer takes from a few seconds to about a minute. Each question makes several calls to the models, which use resource units of your watsonx.ai plan.

---

# Part D (optional): MQ Agent with a vLLM server

Besides watsonx.ai, the chart supports any server with an **OpenAI-compatible API** (chart provider type `vllmService`): vLLM, or a hosted service exposing the same API. In this part you deploy a **second** agent, Helm release `mqagent-vllm`, next to the watsonx one. It reuses the queue manager objects of Part B (channel, CCDT, key store, MCP configuration). Then you switch the console from one agent to the other.

```
 MQ Console ──► MQ Agent mqagent-vllm (ibmint-mqagent) ──(OpenAI API: POST /v1/chat/completions)──► vLLM server
                    └─ MCP server ── MQAGENT.SVRCONN ──► queue managers
```

## What the server must provide

Check these points before you start. Each one caused real failures during the preparation of this lab.

| Requirement | Why | What to check |
|---|---|---|
| A GPT-OSS model (`openai/gpt-oss-120b` recommended by IBM, `openai/gpt-oss-20b` at least) | The chart states that the main reasoning model must be GPT-OSS | `GET /v1/models` |
| Context of at least **32k tokens** | One agent request is about 14,000 tokens (system prompt and the definitions of the 39 tools) | `--max-model-len 32768` |
| **Tool calling**, including a *named* `tool_choice` (`{"type": "function", "function": {"name": ...}}`) | The agent forces the use of a given tool | Step D2, test 3 |
| **Speed**: a 14,000-token prompt processed in a few seconds | The agent abandons a question after **180 seconds** (not configurable), and each question makes several calls | Step D2, test 4 |
| No low token limit per minute | Free hosted tiers reject the agent requests (`413 ... tokens per minute (TPM): Limit 8000, Requested 13611`) | Plan of the hosted service |
| Reachable from the agent pod | The agent calls the server from the cluster | In-cluster service, or HTTPS URL |

Sizing: the GPU must hold the whole model, about 24 GB or more for `gpt-oss-20b` and 80 GB for `gpt-oss-120b`. A laptop with an 8 GB GPU took 164 s (20b) and 228 s (120b) to process a 17,000-token prompt: too slow for the agent.

## Step D1: start the vLLM server

On a GPU machine (or a GPU node of the cluster), start vLLM with the options the agent needs:

* `--served-model-name`: the model id the agent sends,
* `--max-model-len 32768`: the context size,
* `--enable-auto-tool-choice` and `--tool-call-parser`: tool calling (the parser depends on the model, see the tool calling page of the vLLM documentation for your version),
* `--api-key` (optional): the key the clients must send.

```bash
vllm serve openai/gpt-oss-120b \
  --served-model-name openai/gpt-oss-120b \
  --max-model-len 32768 \
  --enable-auto-tool-choice --tool-call-parser openai \
  --api-key "$(cat ~/vllm_api_key.txt)" \
  --host 0.0.0.0 --port 8000
```

Then set the variables of Part D on your workstation:

```bash
export VLLM_URI=http://<vllm host>:8000/v1           # base URL, ending with /v1
export VLLM_MODEL=openai/gpt-oss-120b                # served model name
( umask 077; vi $LAB_DIR/vllm_api_key.txt )          # the --api-key value; leave the file empty without --api-key
```

## Step D2: check the server

Run these four tests from your workstation. Test 4 is the one that predicts whether the agent will answer in time.

```bash
# Key header file (empty without --api-key): the key is not on the command line
( umask 077; K=$(tr -d '\r\n' < $LAB_DIR/vllm_api_key.txt); [[ -n $K ]] && echo "Authorization: Bearer $K" > $LAB_DIR/vllm_auth.hdr || : > $LAB_DIR/vllm_auth.hdr )

# 1. Models served: the list must contain $VLLM_MODEL
curl -s -H @$LAB_DIR/vllm_auth.hdr $VLLM_URI/models | jq -r '.data[].id'

# 2. Simple chat
curl -s -H @$LAB_DIR/vllm_auth.hdr -H "Content-Type: application/json" $VLLM_URI/chat/completions \
  -d "$(jq -n --arg m "$VLLM_MODEL" '{model: $m, max_tokens: 100, messages: [{role: "user", content: "Reply with OK"}]}')" \
  | jq '.choices[0].message.content // .error'
```

Test 3 forces the tool by name, as the agent does. It must print a `tool_calls` entry for `list_queues`, not an error:

```bash
curl -s -H @$LAB_DIR/vllm_auth.hdr -H "Content-Type: application/json" $VLLM_URI/chat/completions \
  -d "$(jq -n --arg m "$VLLM_MODEL" '{model: $m,
        messages: [{role: "user", content: "List the queues of QM1"}],
        tools: [{type: "function", function: {name: "list_queues",
                 parameters: {type: "object", properties: {qmgr: {type: "string"}}, required: ["qmgr"]}}}],
        tool_choice: {type: "function", function: {name: "list_queues"}}}')" \
  | jq '.choices[0].message.tool_calls // .error'
```

Test 4 sends a prompt of about 17,000 tokens, the size of an agent request. A random value prevents a cached answer. It should take a few seconds, and **must take well under 60 seconds**:

```bash
S=$RANDOM
CTX=$(for i in $(seq 1 1200); do printf 'Queue manager QM%d has queue Q%d with depth %d. ' $i $((i+S)) $((i*3)); done)
time curl -s -H @$LAB_DIR/vllm_auth.hdr -H "Content-Type: application/json" $VLLM_URI/chat/completions \
  -d "$(jq -n --arg m "$VLLM_MODEL" --arg c "$CTX" '{model: $m,
        messages: [{role: "system", content: $c}, {role: "user", content: "How many queue managers are listed? Answer with a number."}]}')" \
  | jq '.usage'
```

## Step D3: TLS certificate of the second agent

The second release has its own route (`ibm-mq-agent-mqagent-vllm-...`): create its certificate with the CA issuer of Step B7.

```bash
oc -n $MQAGENT_NS apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mqagent-vllm-tls
spec:
  commonName: ibm-mq-agent-mqagent-vllm
  dnsNames:
    - ibm-mq-agent-mqagent-vllm-$MQAGENT_NS.$APPS_DOMAIN
    - ibm-mq-agent-mqagent-vllm.$MQAGENT_NS.svc.cluster.local
  secretName: mqagent-vllm-tls
  duration: 8760h
  privateKey: {algorithm: RSA, size: 2048}
  usages: [server auth, digital signature, key encipherment]
  issuerRef: {kind: Issuer, name: mqagent-ca-issuer}
EOF
oc -n $MQAGENT_NS wait certificate/mqagent-vllm-tls --for=condition=Ready --timeout=120s
```

## Step D4: install the vLLM agent with Helm

Differences with Step B8:

* provider type `vllmService` with the `uri` of the server,
* only the primary model: the secondary model is disabled, so everything goes to `$VLLM_MODEL` (recommended with a single GPU),
* the key of the server goes in `vllmService.key`. The chart refuses an empty `vllmService` block (`Provider 'myVllmRuntime' has type 'vllmService' but no vllmService configuration`), so without `--api-key` a placeholder is sent, which vLLM ignores.

```bash
cat > $LAB_DIR/mqagent-vllm-values.yaml <<EOF
license:
  accept: true
  license: L-CXDB-XTZ9J8
agent:
  identifier: mqagent-vllm
  model:
    providers:
      myVllmRuntime:
        type: vllmService
        uri: $VLLM_URI
    defaultProvider: myVllmRuntime
    roles:
      primaryLLM:
        modelId: "$VLLM_MODEL"
      secondaryLLM:
        enabled: false
  tlsSecretName: mqagent-vllm-tls
mcpServer:
  ccdtConfigMapName: mqagent-ccdt
  keyStoreSecretName: mqagent-qm-keystore
  configurationSecretName: mqagent-mcp-configuration
route:
  enabled: true
EOF

KS_PWD=$(oc -n $MQAGENT_NS get secret mqagent-qm-keystore -o jsonpath='{.data.password}' | base64 -d)
helm upgrade --install mqagent-vllm ibm-helm/ibm-mq-agent --version 2.1.0 -n $MQAGENT_NS \
  -f $LAB_DIR/mqagent-vllm-values.yaml \
  -f <(KS_PWD=$KS_PWD jq -n --rawfile k $LAB_DIR/vllm_api_key.txt \
         '{agent: {model: {providers: {myVllmRuntime: {vllmService: {key: (($k | gsub("[\r\n]"; "")) as $v | if $v == "" then "no-api-key" else $v end)}}}}},
           mcpServer: {keyStorePassword: $ENV.KS_PWD}}')

oc -n $MQAGENT_NS rollout status deployment/ibm-mq-agent-mqagent-vllm --timeout=900s
```

If the vLLM server uses a certificate signed by a private CA, put the CA in a Secret and add two keys to the provider in the values file:

```bash
oc -n $MQAGENT_NS create secret generic vllm-ca --from-file=ca.pem=<CA file of the vLLM server>
# in mqagent-vllm-values.yaml, under myVllmRuntime:
#        tlsCertSecretName: vllm-ca
#        tlsCertFileName: ca.pem
```

## Step D5: test the vLLM agent

Same test as Step B9. The API key of the console is the one of user `mqagent-vllm`:

```bash
export AGENT_HOST=$(oc -n $MQAGENT_NS get route ibm-mq-agent-mqagent-vllm -o jsonpath='{.spec.host}')
oc -n $MQAGENT_NS get secret mqagent-vllm-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > $LAB_DIR/agent-ca.crt
export AGENT_KEY=$(oc -n $MQAGENT_NS get secret ibm-mq-agent-mqagent-vllm-api-key-file -o jsonpath='{.data.api\.key}' | base64 -d \
                   | jq -r '.[] | select(.user == "mqagent-vllm") | .key')

time curl -s --max-time 300 --cacert $LAB_DIR/agent-ca.crt -X POST https://$AGENT_HOST/a2a/message:send \
  -H "Content-Type: application/json" -H "A2A-Version: 1.0" -H @<(printf 'x-api-key: %s\n' "$AGENT_KEY") \
  -d '{"message": {"messageId": "1", "role": "ROLE_USER", "parts": [{"text": "How many queue managers can you access, and what are their names?"}]}}' \
  | jq -r '.task.status.state, ([.. | .text? // empty] | .[0])'
```

If the answer is `TASK_STATE_FAILED`, read the agent log; the most frequent errors are in [Troubleshooting](#troubleshooting):

```bash
oc -n $MQAGENT_NS logs deployment/ibm-mq-agent-mqagent-vllm -c agent --since=10m | grep -E 'WARNING|ERROR'
```

## Step D6: switch the console to the vLLM agent

The console talks to one agent at a time. The variables `AGENT_HOST` and `AGENT_KEY` and the file `agent-ca.crt` of Step D5 now describe the vLLM agent. Replace the `mqweb-agent` Secret and restart the console:

```bash
oc -n $MQWEB_NS create secret generic mqweb-agent \
  --from-literal=MQWEB_AGENT_HOSTNAME=https://$AGENT_HOST \
  --from-literal=MQWEB_AGENT_APIKEY="$AGENT_KEY" \
  --from-file=ca.crt=$LAB_DIR/agent-ca.crt \
  --dry-run=client -o yaml | oc apply -f -

oc -n $MQWEB_NS rollout restart deployment/mqweb
oc -n $MQWEB_NS rollout status deployment/mqweb --timeout=600s
oc -n $MQWEB_NS logs deployment/mqweb | grep 'Connecting the console'
```

To go back to the watsonx agent, run the commands of Step B9 (they set the variables for release `mqagent`), then the commands above again.

## Step D7 (only if test 3 failed): proxy for servers without a named tool_choice

Some OpenAI-compatible servers, for example LM Studio, accept only `"none"`, `"auto"` or `"required"` as `tool_choice` and reject the agent requests (`Invalid tool_choice type: 'object'`). A **LiteLLM proxy** placed between the agent and the server fixes this. A small pre-call hook rewrites the request into its exact equivalent: only the named tool in `tools`, and `tool_choice: "required"`. The agent then calls the proxy, authenticated with a key of the proxy (*master key*), and the proxy calls the server with the server key.

```
 agent ──(OpenAI API, master key)──► LiteLLM proxy (hook) ──(OpenAI API, server key)──► LM Studio / server
```

1. Keys of the proxy:

```bash
K=$(tr -d '\r\n' < $LAB_DIR/vllm_api_key.txt)
oc -n $MQAGENT_NS create secret generic mqagent-vllm-litellm-keys \
  --from-literal=LITELLM_MASTER_KEY=sk-$(openssl rand -hex 24) \
  --from-literal=LLM_API_KEY="${K:-no-api-key}"
unset K
```

2. Configuration of the proxy and the hook (`tool_choice_hook.py`, loaded from the same directory as `config.yaml`):

```bash
oc -n $MQAGENT_NS apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: mqagent-vllm-litellm-config
data:
  config.yaml: |
    model_list:
      - model_name: "$VLLM_MODEL"
        litellm_params:
          model: "openai/$VLLM_MODEL"
          api_base: "$VLLM_URI"
          api_key: os.environ/LLM_API_KEY
    litellm_settings:
      callbacks: tool_choice_hook.proxy_handler_instance
      drop_params: true
    general_settings:
      master_key: os.environ/LITELLM_MASTER_KEY
  tool_choice_hook.py: |
    from litellm.integrations.custom_logger import CustomLogger


    class ToolChoiceHook(CustomLogger):
        async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
            tool_choice = data.get("tool_choice")
            if isinstance(tool_choice, dict):
                name = (tool_choice.get("function") or {}).get("name")
                tools = [t for t in (data.get("tools") or []) if (t.get("function") or {}).get("name") == name]
                if tools:
                    data["tools"] = tools
                data["tool_choice"] = "required"
            return data


    proxy_handler_instance = ToolChoiceHook()
EOF
```

3. Deployment and Service of the proxy:

```bash
oc -n $MQAGENT_NS apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mqagent-vllm-litellm
  labels: {app: mqagent-vllm-litellm}
spec:
  replicas: 1
  selector:
    matchLabels: {app: mqagent-vllm-litellm}
  template:
    metadata:
      labels: {app: mqagent-vllm-litellm}
    spec:
      containers:
        - name: litellm
          image: ghcr.io/berriai/litellm:v1.83.14-stable
          args: ["--config", "/config/config.yaml", "--port", "4000"]
          ports: [{name: http, containerPort: 4000}]
          envFrom: [{secretRef: {name: mqagent-vllm-litellm-keys}}]
          env: [{name: HOME, value: /tmp}]
          resources:
            requests: {cpu: 200m, memory: 512Mi}
            limits: {cpu: "1", memory: 1Gi}
          readinessProbe:
            httpGet: {path: /health/readiness, port: 4000}
            initialDelaySeconds: 10
            periodSeconds: 10
          volumeMounts:
            - {name: config, mountPath: /config}
            - {name: tmp, mountPath: /tmp}
      volumes:
        - name: config
          configMap: {name: mqagent-vllm-litellm-config}
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: mqagent-vllm-litellm
spec:
  selector: {app: mqagent-vllm-litellm}
  ports: [{name: http, port: 4000, targetPort: 4000}]
EOF
oc -n $MQAGENT_NS rollout status deployment/mqagent-vllm-litellm --timeout=600s
```

4. Point the agent to the proxy: in `$LAB_DIR/mqagent-vllm-values.yaml`, replace the `uri` with the proxy service, then run Helm again with the **master key** as provider key:

```bash
sed -i "s|uri: .*|uri: http://mqagent-vllm-litellm.$MQAGENT_NS.svc.cluster.local:4000/v1|" $LAB_DIR/mqagent-vllm-values.yaml
grep 'uri:' $LAB_DIR/mqagent-vllm-values.yaml

KS_PWD=$(oc -n $MQAGENT_NS get secret mqagent-qm-keystore -o jsonpath='{.data.password}' | base64 -d)
MK=$(oc -n $MQAGENT_NS get secret mqagent-vllm-litellm-keys -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
helm upgrade --install mqagent-vllm ibm-helm/ibm-mq-agent --version 2.1.0 -n $MQAGENT_NS \
  -f $LAB_DIR/mqagent-vllm-values.yaml \
  -f <(KS_PWD=$KS_PWD MK=$MK jq -n '{agent: {model: {providers: {myVllmRuntime: {vllmService: {key: $ENV.MK}}}}},
                                    mcpServer: {keyStorePassword: $ENV.KS_PWD}}')
unset MK
oc -n $MQAGENT_NS rollout restart deployment/ibm-mq-agent-mqagent-vllm
oc -n $MQAGENT_NS rollout status deployment/ibm-mq-agent-mqagent-vllm --timeout=900s
```

Then run Step D5 again. The proxy log shows each call of the agent:

```bash
oc -n $MQAGENT_NS logs deployment/mqagent-vllm-litellm | grep 'POST /v1/chat/completions'
```

---

# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Console log: `WARNING: registration of <QM> failed` | Invalid CCDT file | Check `$LAB_DIR/ccdt/<QM>.json`, recreate the ConfigMap (Step A5), restart the console |
| Console: queue manager listed but not connected, `AMQ9641` or TLS error in the queue manager log | Certificate of the queue manager not trusted | Check the `.pem` files of `mqweb-mq-certs` (Step A4), restart the console |
| Console: `MQRC_NOT_AUTHORIZED` (2035) | Missing channel rule or authorities | Run Step A3 again on the queue manager |
| B2: `project_id ... is not associated with a WML instance` | watsonx.ai project without Runtime | Associate it (project > Manage > Services & integrations) |
| B2: a model is not listed | Region without the models | Use us-south |
| Agent pod: `ImagePullBackOff` | Missing or invalid entitlement key | Recreate `ibm-entitlement-key` (Step B1) |
| B9: `TASK_STATE_FAILED` | Error between the agent and watsonx.ai or the queue managers | `oc -n $MQAGENT_NS logs deployment/ibm-mq-agent-mqagent -c agent` and `-c mcp-server` |
| B9 or chat: `Request of 1 token(s) from quota was rejected` | watsonx.ai plan quota used up | Wait for the monthly reset or upgrade the plan |
| No AI chat icon in the console | `mqweb-agent` Secret missing, or console not restarted | Step C1 |
| D2 or D5: `HTTP 000`, `Could not resolve host` | vLLM server not reachable from the workstation or from the agent pod | Check `VLLM_URI` (it ends with `/v1`), DNS, firewall |
| D4: `Provider 'myVllmRuntime' has type 'vllmService' but no vllmService configuration` | Empty `vllmService` block | Pass a key (placeholder `no-api-key` without `--api-key`), Step D4 |
| D5, agent log: `Invalid tool_choice type: 'object'` (400) | Server without named `tool_choice` | vLLM: `--enable-auto-tool-choice --tool-call-parser ...`; other servers: Step D7 |
| D5, agent log: `Error code: 413 ... tokens per minute (TPM)` | Token limit per minute of a hosted free tier | Paid plan, or your own server |
| D5: `TASK_STATE_FAILED` after exactly 180 s, no error in the agent log | Server too slow on the ~14,000-token prompts (Step D2, test 4) | GPU holding the whole model, smaller model, or watsonx.ai |

To list the container names of the agent pod: `oc -n $MQAGENT_NS get pod -l app.kubernetes.io/instance=mqagent -o jsonpath='{.items[0].spec.containers[*].name}'`.

# Cleanup

```bash
helm -n $MQAGENT_NS uninstall mqagent
helm -n $MQAGENT_NS uninstall mqagent-vllm 2>/dev/null     # Part D
oc delete project $MQAGENT_NS $MQWEB_NS

for QM in $QMGRS; do
  QMNAME=$(oc -n $MQ_NS get queuemanager $QM -o jsonpath='{.spec.queueManager.name}')
  POD=$(oc -n $MQ_NS get pod -l app.kubernetes.io/instance=$QM -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' | head -1)
  oc -n $MQ_NS exec -i $POD -c qmgr -- runmqsc $QMNAME <<'EOF'
STOP CHANNEL('MQWEB.SVRCONN') MODE(FORCE)
STOP CHANNEL('MQAGENT.SVRCONN') MODE(FORCE)
DELETE CHANNEL('MQWEB.SVRCONN')
DELETE CHANNEL('MQAGENT.SVRCONN')
SET CHLAUTH('MQWEB.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('*') ACTION(REMOVE)
SET CHLAUTH('MQAGENT.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('*') ACTION(REMOVE)
DELETE AUTHREC PRINCIPAL('mqwebadm') OBJTYPE(QMGR)
DELETE AUTHREC PRINCIPAL('mqagent') OBJTYPE(QMGR)
EOF
done

rm -rf $LAB_DIR
```

The profile-level authority records (`PROFILE('**')`) of `mqwebadm`, `mqagent`, `mqadmin` and `mqreader` stay on the queue managers: they grant nothing once the channels are deleted. Remove them with `DELETE AUTHREC PROFILE('**') OBJTYPE(<type>) PRINCIPAL('<user>')` if needed.

# References

* [Installing and configuring the IBM MQ Agent](https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=agent-installing-configuring-mq)
* [Foundation models for the IBM MQ Agent](https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=agent-foundation-models-mq)
* Automated version of this lab in this repository: [MQ_Agent.md](MQ_Agent.md), `demos/ibm_mq_standalone_webconsole`, `demos/mq_agent`
