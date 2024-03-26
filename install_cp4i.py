from kubernetes import client, config
from openshift.dynamic import DynamicClient
import time

# Load Kubernetes configuration
config.load_kube_config()

# Create a dynamic client
dyn_client = DynamicClient(client)

# Define pod manifest
pod_manifest = {
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {
        "name": "test-pod"
    },
    "spec": {
        "containers": [
            {
                "name": "test-container",
                "image": "nginx"
            }
        ]
    }
}

# Create the pod
v1_pod = dyn_client.resources.get(api_version='v1', kind='Pod')
created_pod = v1_pod.create(body=pod_manifest)

# Function to check pod status
def check_pod_status(pod_name):
    while True:
        pod = v1_pod.get(name=pod_name)
        if pod.status.phase != 'Pending':
            print("Pod Status:", pod.status.phase)
            break
        print("Pod is still pending...")
        time.sleep(5)

# Check pod status
check_pod_status("test-pod")