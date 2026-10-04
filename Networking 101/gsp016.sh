#!/bin/bash
# Script: Networking 101 (GSP016)
# Author: Cognivex Arcade Lab Solutions

set -e

# Prevent Cloud Shell session from timing out or exiting abruptly
trap 'echo "Error encountered on line $LINENO. Exiting..."; exit 1' ERR

echo "=========================================="
echo "Starting Networking 101 (GSP016) Execution"
echo "=========================================="

# Auto-detect or prompt for Project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    read -p "Enter your GCP Project ID: " PROJECT_ID
    gcloud config set project "$PROJECT_ID"
fi
echo "Using Project ID: $PROJECT_ID"

# 1. Set Default Compute Region & Zone
echo "--> Configuring default zone and region..."
gcloud config set compute/zone "europe-west1-c" --quiet
gcloud config set compute/region "europe-west1" --quiet

# 2. Create Custom VPC Network
echo "--> Creating custom VPC network: taw-custom-network..."
gcloud compute networks create taw-custom-network \
    --subnet-mode=custom \
    --bgp-routing-mode=regional

# 3. Create Subnetworks
echo "--> Creating subnet-europe-west1 (10.0.0.0/16)..."
gcloud compute networks subnets create subnet-europe-west1 \
    --network=taw-custom-network \
    --region=europe-west1 \
    --range=10.0.0.0/16

echo "--> Creating subnet-us-east1 (10.1.0.0/16)..."
gcloud compute networks subnets create subnet-us-east1 \
    --network=taw-custom-network \
    --region=us-east1 \
    --range=10.1.0.0/16

echo "--> Creating subnet-us-central1 (10.2.0.0/16)..."
gcloud compute networks subnets create subnet-us-central1 \
    --network=taw-custom-network \
    --region=us-central1 \
    --range=10.2.0.0/16

# 4. Create Firewall Rules
echo "--> Creating firewall rule: nw101-allow-http..."
gcloud compute firewall-rules create nw101-allow-http \
    --network=taw-custom-network \
    --allow=tcp:80 \
    --target-tags=http \
    --source-ranges=0.0.0.0/0

echo "--> Creating firewall rule: nw101-allow-icmp..."
gcloud compute firewall-rules create nw101-allow-icmp \
    --network=taw-custom-network \
    --allow=icmp \
    --target-tags=rules \
    --source-ranges=0.0.0.0/0

echo "--> Creating firewall rule: nw101-allow-internal..."
gcloud compute firewall-rules create nw101-allow-internal \
    --network=taw-custom-network \
    --allow=tcp:0-65535,udp:0-65535,icmp \
    --source-ranges=10.0.0.0/16,10.1.0.0/16,10.2.0.0/16

echo "--> Creating firewall rule: nw101-allow-ssh..."
gcloud compute firewall-rules create nw101-allow-ssh \
    --network=taw-custom-network \
    --allow=tcp:22 \
    --target-tags=ssh \
    --source-ranges=0.0.0.0/0

echo "--> Creating firewall rule: nw101-allow-rdp..."
gcloud compute firewall-rules create nw101-allow-rdp \
    --network=taw-custom-network \
    --allow=tcp:3389 \
    --source-ranges=0.0.0.0/0

echo "=========================================="
echo "All tasks completed successfully!"
echo "Check your progress in the lab window."
echo "=========================================="