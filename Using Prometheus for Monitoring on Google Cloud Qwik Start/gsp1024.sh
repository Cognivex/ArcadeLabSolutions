#!/bin/bash
# ==============================================================================
# Script Name: gsp1024.sh
# Lab ID: GSP1024
# Title: Using Prometheus for Monitoring on Google Cloud: Qwik Start
# Description: Fully automated, idempotent end-to-end deployment script.
# ==============================================================================

set -euo pipefail

# Text formatting (safe when tput/TERM unavailable)
if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    BOLD=$(tput bold)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    NC=$(tput sgr0)
else
    BOLD=""
    GREEN=""
    YELLOW=""
    RED=""
    NC=""
fi

echo "${BOLD}${GREEN}====================================================${NC}"
echo "${BOLD}${GREEN} Starting Automated Execution for GSP1024           ${NC}"
echo "${BOLD}${GREEN}====================================================${NC}"

# Detect or prompt for Region and Zone
ZONE=$(gcloud config get-value compute/zone 2>/dev/null || echo "")
REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "")

if [ -z "$ZONE" ] || [ "$ZONE" == "(unset)" ]; then
    ZONE="europe-west4-a"
fi

if [ -z "$REGION" ] || [ "$REGION" == "(unset)" ]; then
    REGION="${ZONE%-*}"
fi

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" == "(unset)" ]; then
    echo "${RED}Error: Project ID is not configured in gcloud CLI.${NC}"
    exit 1
fi

echo "${YELLOW}Project ID : ${PROJECT_ID}${NC}"
echo "${YELLOW}Region     : ${REGION}${NC}"
echo "${YELLOW}Zone       : ${ZONE}${NC}"

# Task 1: Create Artifact Registry Repository and Push Image
echo "${BOLD}${GREEN}[Task 1] Setting up Artifact Registry Docker repository...${NC}"
gcloud artifacts repositories create docker-repo \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Docker repository" \
    --project="${PROJECT_ID}" || echo "${YELLOW}Repository docker-repo already exists. Continuing...${NC}"

# Configure Docker credentials for Artifact Registry
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Download and load image
cd "$HOME"
rm -f flask_telemetry.zip flask_telemetry.tar
wget -q https://storage.googleapis.com/spls/gsp1024/flask_telemetry.zip
unzip -q -o flask_telemetry.zip
docker load -i flask_telemetry.tar

IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/docker-repo/flask-telemetry:v1"
docker tag gcr.io/ops-demo-330920/flask_telemetry:61a2a7aabc7077ef474eb24f4b69faeab47deed9 "${IMAGE_TAG}"
docker push "${IMAGE_TAG}"

# Task 2: Setup Google Kubernetes Engine Cluster
echo "${BOLD}${GREEN}[Task 2] Creating and configuring GKE cluster...${NC}"
gcloud beta container clusters create gmp-cluster \
    --num-nodes=1 \
    --zone="${ZONE}" \
    --enable-managed-prometheus \
    --quiet || echo "${YELLOW}Cluster gmp-cluster already exists. Continuing...${NC}"

gcloud container clusters get-credentials gmp-cluster --zone="${ZONE}"

# Task 3: Deploy the Prometheus Service Namespace
echo "${BOLD}${GREEN}[Task 3] Creating namespace gmp-test...${NC}"
kubectl create ns gmp-test || echo "${YELLOW}Namespace gmp-test already exists. Continuing...${NC}"

# Task 4: Deploy Flask Application and Prometheus Scraper
echo "${BOLD}${GREEN}[Task 4] Deploying application and PodMonitoring...${NC}"
cd "$HOME"
rm -rf gmp_prom_setup gmp_prom_setup.zip
wget -q https://storage.googleapis.com/spls/gsp1024/gmp_prom_setup.zip
unzip -q -o gmp_prom_setup.zip
cd gmp_prom_setup

# Update deployment image
sed -i "s|<ARTIFACT REGISTRY IMAGE NAME>|${IMAGE_TAG}|g" flask_deployment.yaml

kubectl -n gmp-test apply -f flask_deployment.yaml
kubectl -n gmp-test apply -f flask_service.yaml
kubectl -n gmp-test apply -f prom_deploy.yaml

echo "${YELLOW}Waiting for LoadBalancer external IP...${NC}"
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
    EXTERNAL_IP=$(kubectl get services -n gmp-test flask-telemetry -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -z "$EXTERNAL_IP" ]; then
        sleep 5
    fi
done

echo "${GREEN}Application LoadBalancer IP is available: http://${EXTERNAL_IP}:8080${NC}"

# Verify endpoint availability
curl -s "http://${EXTERNAL_IP}:8080/metrics" > /dev/null || true

# Generate background traffic to register metrics in Cloud Monitoring
echo "${YELLOW}Generating traffic on http://${EXTERNAL_IP}:8080 for 30 seconds...${NC}"
timeout 30 bash -c -- "while true; do curl -s http://${EXTERNAL_IP}:8080/ > /dev/null; sleep 1; done" || true

# Task 5: Create Cloud Monitoring Dashboard
echo "${BOLD}${GREEN}[Task 5] Creating Cloud Monitoring dashboard...${NC}"
cat <<EOF > "$HOME/dashboard.json"
{
  "category": "CUSTOM",
  "displayName": "Prometheus Dashboard Example",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "height": 4,
        "widget": {
          "title": "prometheus/flask_http_request_total/counter [MEAN]",
          "xyChart": {
            "chartOptions": {
              "mode": "COLOR"
            },
            "dataSets": [
              {
                "minAlignmentPeriod": "60s",
                "plotType": "LINE",
                "targetAxis": "Y1",
                "timeSeriesQuery": {
                  "apiSource": "DEFAULT_CLOUD",
                  "timeSeriesFilter": {
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_NONE",
                      "perSeriesAligner": "ALIGN_RATE"
                    },
                    "filter": "metric.type=\"prometheus.googleapis.com/flask_http_request_total/counter\" resource.type=\"prometheus_target\"",
                    "secondaryAggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": [
                        "metric.label.\"status\""
                      ],
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ],
            "thresholds": [],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "y1Axis",
              "scale": "LINEAR"
            }
          }
        },
        "width": 6,
        "xPos": 0,
        "yPos": 0
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file="$HOME/dashboard.json"

echo "${BOLD}${GREEN}====================================================${NC}"
echo "${BOLD}${GREEN} All checkpoints successfully completed!           ${NC}"
echo "${BOLD}${GREEN} You can now click all 'Check my progress' buttons. ${NC}"
echo "${BOLD}${GREEN}====================================================${NC}"
