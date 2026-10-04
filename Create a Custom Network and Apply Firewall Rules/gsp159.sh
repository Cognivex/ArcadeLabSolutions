#!/bin/bash
# ==============================================================================
# Script Name : gsp159.sh
# Lab Name    : Create a Custom Network and Apply Firewall Rules (GSP159)
# Repository  : https://github.com/Cognivex/ArcadeLabSolutions
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# Error trap to prevent the shell from exiting silently or closing
trap 'echo "Error encountered on line $LINENO. Check the error message above."; exit 1' ERR

echo "=================================================================="
echo "Starting Lab: Create a Custom Network and Apply Firewall Rules"
echo "=================================================================="

# Ensure project ID is configured
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    read -p "Enter your Google Cloud Project ID: " PROJECT_ID
    gcloud config set project "$PROJECT_ID"
fi
echo "Using Project ID: $PROJECT_ID"

# 1. Configure default region and zone
echo "--> Configuring default zone and region..."
gcloud config set compute/zone "us-central1-a" --quiet
gcloud config set compute/region "us-central1" --quiet

# 2. Task 1: Create custom network and subnets
echo "--> Creating custom VPC network: taw-custom-network..."
gcloud compute networks create taw-custom-network --subnet-mode custom

echo "--> Creating subnetwork: subnet-us-central1..."
gcloud compute networks subnets create subnet-us-central1 \
   --network taw-custom-network \
   --region us-central1 \
   --range 10.0.0.0/16

echo "--> Creating subnetwork: subnet-europe-west1..."
gcloud compute networks subnets create subnet-europe-west1 \
   --network taw-custom-network \
   --region europe-west1 \
   --range 10.1.0.0/16

echo "--> Creating subnetwork: subnet-europe-west4..."
gcloud compute networks subnets create subnet-europe-west4 \
   --network taw-custom-network \
   --region europe-west4 \
   --range 10.2.0.0/16

echo "--> Verifying created subnets..."
gcloud compute networks subnets list --network taw-custom-network

# 3. Task 2: Create firewall rules
echo "--> Creating firewall rule: nw101-allow-http..."
gcloud compute firewall-rules create nw101-allow-http \
   --network taw-custom-network \
   --allow tcp:80 \
   --source-ranges 0.0.0.0/0 \
   --target-tags http

echo "--> Creating firewall rule: nw101-allow-icmp..."
gcloud compute firewall-rules create nw101-allow-icmp \
   --network taw-custom-network \
   --allow icmp \
   --target-tags rules

echo "--> Creating firewall rule: nw101-allow-internal..."
gcloud compute firewall-rules create nw101-allow-internal \
   --network taw-custom-network \
   --allow tcp:0-65535,udp:0-65535,icmp \
   --source-ranges 10.0.0.0/16,10.2.0.0/16,10.1.0.0/16

echo "--> Creating firewall rule: nw101-allow-ssh..."
gcloud compute firewall-rules create nw101-allow-ssh \
   --network taw-custom-network \
   --allow tcp:22 \
   --target-tags ssh

echo "--> Creating firewall rule: nw101-allow-rdp..."
gcloud compute firewall-rules create nw101-allow-rdp \
   --network taw-custom-network \
   --allow tcp:3389

echo "=================================================================="
echo "All tasks executed successfully!"
echo "Return to the lab page and click 'Check my progress' on all tasks."
echo "=================================================================="