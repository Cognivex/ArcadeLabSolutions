#!/bin/bash
set -eo pipefail

echo "=========================================================="
echo " Starting GSP1025: Migrate Monitoring to Google Cloud GMP "
echo "=========================================================="

# 1. Auto-detect Project ID and Zone
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
  read -rp "Enter Google Cloud Project ID: " PROJECT_ID
  gcloud config set project "$PROJECT_ID"
fi

ZONE=$(gcloud config get-value compute/zone 2>/dev/null)
if [[ -z "$ZONE" ]]; then
  # Fallback to the default lab zone
  ZONE="us-east4-b"
fi

echo "Project ID : $PROJECT_ID"
echo "Zone       : $ZONE"

# 2. Task 1: Create GKE Cluster & Namespace
echo "[1/7] Creating GKE Cluster (gmp-cluster)... This may take ~3-4 minutes."
gcloud container clusters create gmp-cluster \
  --num-nodes=3 \
  --zone="$ZONE" \
  --quiet

echo "[2/7] Authenticating kubectl with cluster..."
gcloud container clusters get-credentials gmp-cluster --zone="$ZONE"

echo "[3/7] Creating namespace gmp-test..."
kubectl create ns gmp-test --dry-run=client -o yaml | kubectl apply -f -

# 3. Task 2: Deploy Example Application
echo "[4/7] Deploying sample metric-emitting application..."
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.4.3-gke.0/examples/example-app.yaml

# 4. Task 3: Deploy Prometheus Ingestion Pod
echo "[5/7] Deploying Prometheus collector pod..."
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.4.3-gke.0/examples/prometheus.yaml

# 5. Task 4: Deploy Frontend Service (Prometheus UI proxy)
echo "[6/7] Deploying frontend service with PROJECT_ID replacement..."
curl -sSL https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.4.3-gke.0/examples/frontend.yaml | \
  sed "s/\$PROJECT_ID/$PROJECT_ID/" | \
  kubectl apply -n gmp-test -f -

# 6. Task 5: Deploy Ephemeral Grafana Deployment
echo "[7/7] Deploying Grafana..."
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.4.3-gke.0/examples/grafana.yaml

# 7. Wait for Pods to be completely ready
echo "Waiting for all pods in gmp-test to be in Ready state..."
kubectl -n gmp-test wait --for=condition=ready pod --all --timeout=300s

# 8. Tasks 6, 7 & 8: Auto-Configure Grafana Data Source via REST API
echo "Configuring Grafana Prometheus Data Source automatically..."

# Start background port-forward to Grafana service
kubectl -n gmp-test port-forward svc/grafana 3000:3000 >/dev/null 2>&1 &
PF_PID=$!

# Ensure the background port-forward process is terminated on script exit
trap "kill $PF_PID 2>/dev/null || true" EXIT

# Wait briefly for port-forward socket to open
sleep 5

# Create Prometheus data source via Grafana REST API (using default admin:admin credentials)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u admin:admin \
  -X POST http://localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://frontend.gmp-test.svc:9090",
    "access": "proxy",
    "basicAuth": false,
    "isDefault": true,
    "jsonData": {
      "httpMethod": "GET"
    }
  }')

if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "409" ]]; then
  echo "Grafana Data Source configured successfully (HTTP $HTTP_STATUS)."
else
  echo "Grafana setup returned status: $HTTP_STATUS (Datasource might need a few extra seconds)."
fi

echo "=========================================================="
echo " All tasks completed! You can now click Check My Progress."
echo "=========================================================="
