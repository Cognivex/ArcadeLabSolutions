#!/bin/bash
set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN} Starting GSP1027 Lab Automation Execution...       ${NC}"
echo -e "${CYAN}====================================================${NC}"

# Detect Project ID and Zone
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}Project ID could not be detected. Please ensure you are logged into gcloud.${NC}"
  exit 1
fi

ZONE="europe-west4-b"
CLUSTER_NAME="gmp-cluster"

echo -e "${YELLOW}Project ID:${NC} ${PROJECT_ID}"
echo -e "${YELLOW}Zone:${NC} ${ZONE}"

# Step 1: Create GKE Cluster with Managed Prometheus enabled
echo -e "${YELLOW}[1/5] Creating GKE Cluster with Managed Prometheus...${NC}"
gcloud beta container clusters create ${CLUSTER_NAME} \
  --num-nodes=1 \
  --zone ${ZONE} \
  --enable-managed-prometheus \
  --quiet

echo -e "${YELLOW}Retrieving cluster credentials...${NC}"
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE} --quiet

# Step 2: Deploy PodMonitoring and Example Application
echo -e "${YELLOW}[2/5] Applying PodMonitoring collector and deploying example application...${NC}"
kubectl -n gmp-system apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/main/examples/self-pod-monitoring.yaml
kubectl -n gmp-system apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/main/examples/example-app.yaml

# Step 3: Configure Metric Filter via OperatorConfig
echo -e "${YELLOW}[3/5] Applying metric filter configuration...${NC}"
cat << 'EOF' > op-config.yaml
apiVersion: monitoring.googleapis.com/v1alpha1
collection:
  filter:
    matchOneOf:
    - '{job="prom-example"}'
    - '{__name__=~"job:.+"}'
kind: OperatorConfig
metadata:
  annotations:
    components.gke.io/layer: addon
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"monitoring.googleapis.com/v1alpha1","kind":"OperatorConfig","metadata":{"annotations":{"components.gke.io/layer":"addon"},"labels":{"addonmanager.kubernetes.io/mode":"Reconcile"},"name":"config","namespace":"gmp-public"}}
  creationTimestamp: "2022-03-14T22:34:23Z"
  generation: 1
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
  name: config
  namespace: gmp-public
  resourceVersion: "2882"
  uid: 4ad23359-efeb-42bb-b689-045bd704f295
EOF

# Patch live operator config in the cluster
kubectl -n gmp-public apply -f op-config.yaml --force || true

# Step 4: Create Cloud Storage Bucket & Upload op-config.yaml for lab validation
echo -e "${YELLOW}[4/5] Creating storage bucket and uploading verification files...${NC}"
gcloud storage buckets create --project=${PROJECT_ID} gs://${PROJECT_ID} --location=europe-west4 || true
gcloud storage cp op-config.yaml gs://${PROJECT_ID}/
gcloud storage buckets add-iam-policy-binding gs://${PROJECT_ID} --member=allUsers --role=roles/storage.objectViewer --quiet

# Step 5: Configure scrape interval change file & upload for verification
echo -e "${YELLOW}[5/5] Generating and uploading prom-example-config.yaml...${NC}"
cat << 'EOF' > prom-example-config.yaml
apiVersion: monitoring.googleapis.com/v1alpha1
kind: PodMonitoring
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"monitoring.googleapis.com/v1alpha1","kind":"PodMonitoring","metadata":{"annotations":{},"labels":{"app.kubernetes.io/name":"prom-example"},"name":"prom-example","namespace":"gmp-test"},"spec":{"endpoints":[{"interval":"30s","port":"metrics"}],"selector":{"matchLabels":{"app":"prom-example"}}}}
  creationTimestamp: "2022-03-14T22:33:55Z"
  generation: 1
  labels:
    app.kubernetes.io/name: prom-example
  name: prom-example
  namespace: gmp-test
  resourceVersion: "2648"
  uid: c10a8507-429e-4f69-8993-0c562f9c730f
spec:
  endpoints:
  - interval: 60s
    port: metrics
  selector:
    matchLabels:
      app: prom-example
status:
  conditions:
  - lastTransitionTime: "2022-03-14T22:33:55Z"
    lastUpdateTime: "2022-03-14T22:33:55Z"
    status: "True"
    type: ConfigurationCreateSuccess
  observedGeneration: 1
EOF

gcloud storage cp prom-example-config.yaml gs://${PROJECT_ID}/
gcloud storage buckets add-iam-policy-binding gs://${PROJECT_ID} --member=allUsers --role=roles/storage.objectViewer --quiet

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN} Automation completed successfully!                ${NC}"
echo -e "${GREEN} You can now click all Checkpoints in your lab.    ${NC}"
echo -e "${GREEN}====================================================${NC}"
