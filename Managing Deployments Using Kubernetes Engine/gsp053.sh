#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${YELLOW}Starting GSP053: Managing Deployments Using Kubernetes Engine${NC}"
echo -e "${BLUE}====================================================${NC}"

# Detect Zone or prompt user
ZONE=$(gcloud config get-value compute/zone 2>/dev/null)
if [ -z "$ZONE" ] || [ "$ZONE" = "(unset)" ]; then
    ZONE="us-west1-a"
fi

echo -e "${GREEN}Configuring default compute zone to: ${ZONE}...${NC}"
gcloud config set compute/zone "$ZONE"

# Fetch sample manifests
echo -e "${GREEN}Fetching lab sample files...${NC}"
rm -rf kubernetes
gcloud storage cp -r gs://spls/gsp053/kubernetes .
cd kubernetes || exit 1

# Check if cluster already exists to prevent duplicate cluster error
CLUSTER_EXISTS=$(gcloud container clusters list --filter="name=bootcamp" --format="value(name)")

if [ -z "$CLUSTER_EXISTS" ]; then
    echo -e "${GREEN}Creating GKE cluster 'bootcamp' (this will take 3-5 minutes)...${NC}"
    gcloud container clusters create bootcamp \
      --machine-type e2-small \
      --num-nodes 3 \
      --scopes "https://www.googleapis.com/auth/projecthosting,storage-rw" \
      --async

    echo -e "${YELLOW}Waiting for cluster to become RUNNING...${NC}"
    while true; do
        STATUS=$(gcloud container clusters list --filter="name=bootcamp" --format="value(status)")
        if [ "$STATUS" = "RUNNING" ]; then
            echo -e "\n${GREEN}Cluster is READY.${NC}"
            break
        fi
        echo -n "."
        sleep 10
    done
else
    echo -e "${YELLOW}Cluster 'bootcamp' already exists. Skipping creation.${NC}"
fi

# Configure kubectl credentials
echo -e "${GREEN}Getting cluster credentials...${NC}"
gcloud container clusters get-credentials bootcamp --zone "$ZONE"

# Task 1 & 2: Deploy fortune-app-blue and Service
echo -e "${GREEN}Deploying fortune-app-blue and exposing service...${NC}"
kubectl apply -f deployments/fortune-app-blue.yaml
kubectl apply -f services/fortune-app.yaml

echo -e "${YELLOW}Waiting for fortune-app-blue rollout...${NC}"
kubectl rollout status deployment/fortune-app-blue --timeout=180s

# Scale Deployment
echo -e "${GREEN}Scaling deployment up to 5 replicas...${NC}"
kubectl scale deployment fortune-app-blue --replicas=5
kubectl rollout status deployment/fortune-app-blue --timeout=180s

echo -e "${GREEN}Scaling deployment back down to 3 replicas...${NC}"
kubectl scale deployment fortune-app-blue --replicas=3
kubectl rollout status deployment/fortune-app-blue --timeout=180s

# Task 3: Rolling Update and Rollback
echo -e "${GREEN}Performing rolling update to version 2.0.0...${NC}"
kubectl set image deployment/fortune-app-blue fortune-app="us-central1-docker.pkg.dev/qwiklabs-resources/spl-lab-apps/fortune-service:2.0.0"
kubectl set env deployment/fortune-app-blue APP_VERSION="2.0.0"
kubectl rollout status deployment/fortune-app-blue --timeout=180s

echo -e "${GREEN}Simulating rollback to version 1.0.0...${NC}"
kubectl rollout undo deployment/fortune-app-blue
kubectl rollout status deployment/fortune-app-blue --timeout=180s

# Task 4: Canary Deployment
echo -e "${GREEN}Deploying Canary deployment...${NC}"
kubectl apply -f deployments/fortune-app-canary.yaml
kubectl rollout status deployment/fortune-app-canary --timeout=180s

# Task 5: Blue-Green Deployment
echo -e "${GREEN}Setting up Blue-Green deployments...${NC}"
kubectl apply -f services/fortune-app-blue-service.yaml
kubectl apply -f deployments/fortune-app-green.yaml
kubectl rollout status deployment/fortune-app-green --timeout=180s

kubectl apply -f services/fortune-app-green-service.yaml
kubectl apply -f services/fortune-app-blue-service.yaml

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}All tasks completed successfully! Check your progress on Qwiklabs.${NC}"
echo -e "${BLUE}====================================================${NC}"