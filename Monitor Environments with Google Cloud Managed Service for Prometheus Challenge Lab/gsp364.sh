#!/bin/bash
# Script: gsp364.sh
# Resilient, crash-proof runner for GSP364

# Visual cues
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Starting GSP364 resilient setup...${NC}"

export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
export ZONE="europe-west1-c"
export REGION="europe-west1"

# 1. Identify or target the cluster
echo -e "${YELLOW}[Step 1] Locating GKE cluster...${NC}"
EXISTING_CLUSTER=$(gcloud container clusters list --filter="zone:$ZONE" --format="value(name)" 2>/dev/null | head -n 1)

if [ -n "$EXISTING_CLUSTER" ]; then
    export CLUSTER_NAME="$EXISTING_CLUSTER"
    echo -e "${GREEN}Found existing cluster:${NC} $CLUSTER_NAME"
    # Ensure Managed Prometheus is enabled
    gcloud container clusters update $CLUSTER_NAME --zone=$ZONE --enable-managed-prometheus --quiet 2>/dev/null || true
else
    export CLUSTER_NAME="gmp-cluster"
    echo -e "${YELLOW}No cluster found. Creating cluster $CLUSTER_NAME in $ZONE...${NC}"
    gcloud container clusters create $CLUSTER_NAME \
        --zone=$ZONE \
        --num-nodes=1 \
        --machine-type=e2-medium \
        --enable-managed-prometheus \
        --quiet
fi

# 2. Get cluster credentials
echo -e "${YELLOW}[Step 2] Authenticating kubectl...${NC}"
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID

# 3. Task 3 - Deploy example app
echo -e "${YELLOW}[Step 3] Deploying example Prometheus application...${NC}"
kubectl create ns gmp-test --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n gmp-test -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.2.3/examples/example-app.yaml

# 4. Task 4 - Create op-config.yaml & filter
echo -e "${YELLOW}[Step 4] Applying OperatorConfig filter...${NC}"
cat <<EOF > op-config.yaml
apiVersion: monitoring.googleapis.com/v1
kind: OperatorConfig
metadata:
  namespace: gmp-public
  name: config
collection:
  filter:
    matchOneOf:
    - '{job="prom-example"}'
    - '{__name__=~"job:.+"}'
EOF

# Apply operator config
kubectl apply -f op-config.yaml

# 5. Safe bucket creation and public upload
echo -e "${YELLOW}[Step 5] Uploading configuration to Cloud Storage...${NC}"
# Use standard gsutil to avoid gcloud storage container aborts
gsutil mb -p $PROJECT_ID -c standard -l $REGION gs://$PROJECT_ID/ 2>/dev/null || true
gsutil cp op-config.yaml gs://$PROJECT_ID/op-config.yaml
gsutil iam ch allUsers:objectViewer gs://$PROJECT_ID

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN} Lab execution complete without terminal termination! ${NC}"
echo -e "${GREEN} Go back to the lab window and click Check Progress.  ${NC}"
echo -e "${GREEN}======================================================${NC}"