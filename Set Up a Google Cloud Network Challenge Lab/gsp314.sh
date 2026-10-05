#!/bin/bash
# ==============================================================================
# Script: gsp314.sh
# Lab: Set Up a Google Cloud Network: Challenge Lab (GSP314)
# Description: Automates VPC, Subnets, Firewall rules, and Compute Instances setup.
# ==============================================================================

set -e

# Style formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=====================================================${NC}"
echo -e "${CYAN}${BOLD}   GSP314: Set Up a Google Cloud Network Lab Setup   ${NC}"
echo -e "${CYAN}${BOLD}=====================================================${NC}\n"

# Prevent Cloud Shell from timing out or closing during execution
trap 'echo -e "\n${RED}Script interrupted. Please re-run if not completed.${NC}"' INT TERM

# Ensure project ID is configured
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${YELLOW}Project ID not set in gcloud config. Detecting current environment...${NC}"
    PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
    gcloud config set project "$PROJECT_ID"
fi
echo -e "${GREEN}Using Project ID:${NC} ${BOLD}$PROJECT_ID${NC}\n"

# Variable configurations (Matched with Challenge Lab parameters)
VPC_NAME="vpc-network-w06i"
SUBNET_A="subnet-a-o2sc"
SUBNET_B="subnet-b-omr6"

REGION_A="us-east4"
ZONE_A="us-east4-c"
RANGE_A="10.10.10.0/24"

REGION_B="us-west1"
ZONE_B="us-west1-c"
RANGE_B="10.10.20.0/24"

FW_SSH="baqi-firewall-ssh"
FW_RDP="umhy-firewall-rdp"
FW_ICMP="kqae-firewall-icmp"

VM_1="us-test-01"
VM_2="us-test-02"
MACHINE_TYPE="e2-standard-2"

# ------------------------------------------------------------------------------
# Task 1: Create VPC and Subnets
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[1/4] Creating Custom VPC and Subnetworks...${NC}"

if ! gcloud compute networks describe "$VPC_NAME" --quiet >/dev/null 2>&1; then
    gcloud compute networks create "$VPC_NAME" \
        --subnet-mode=custom \
        --bgp-routing-mode=regional \
        --quiet
fi

if ! gcloud compute networks subnets describe "$SUBNET_A" --region="$REGION_A" --quiet >/dev/null 2>&1; then
    gcloud compute networks subnets create "$SUBNET_A" \
        --network="$VPC_NAME" \
        --region="$REGION_A" \
        --range="$RANGE_A" \
        --stack-type=IPV4_ONLY \
        --quiet
fi

if ! gcloud compute networks subnets describe "$SUBNET_B" --region="$REGION_B" --quiet >/dev/null 2>&1; then
    gcloud compute networks subnets create "$SUBNET_B" \
        --network="$VPC_NAME" \
        --region="$REGION_B" \
        --range="$RANGE_B" \
        --stack-type=IPV4_ONLY \
        --quiet
fi

echo -e "${GREEN}VPC and Subnetworks successfully created.${NC}\n"

# ------------------------------------------------------------------------------
# Task 2: Create Firewall Rules
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[2/4] Configuring Firewall Rules...${NC}"

# SSH Rule
if ! gcloud compute firewall-rules describe "$FW_SSH" --quiet >/dev/null 2>&1; then
    gcloud compute firewall-rules create "$FW_SSH" \
        --network="$VPC_NAME" \
        --priority=1000 \
        --direction=INGRESS \
        --action=ALLOW \
        --rules=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --quiet
fi

# RDP Rule
if ! gcloud compute firewall-rules describe "$FW_RDP" --quiet >/dev/null 2>&1; then
    gcloud compute firewall-rules create "$FW_RDP" \
        --network="$VPC_NAME" \
        --priority=65535 \
        --direction=INGRESS \
        --action=ALLOW \
        --rules=tcp:3389 \
        --source-ranges=0.0.0.0/24 \
        --quiet
fi

# ICMP Rule
if ! gcloud compute firewall-rules describe "$FW_ICMP" --quiet >/dev/null 2>&1; then
    gcloud compute firewall-rules create "$FW_ICMP" \
        --network="$VPC_NAME" \
        --priority=1000 \
        --direction=INGRESS \
        --action=ALLOW \
        --rules=icmp \
        --source-ranges="$RANGE_A,$RANGE_B" \
        --quiet
fi

echo -e "${GREEN}Firewall rules configured successfully.${NC}\n"

# ------------------------------------------------------------------------------
# Task 3: Create Compute Instances
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[3/4] Provisioning Compute Instances...${NC}"

if ! gcloud compute instances describe "$VM_1" --zone="$ZONE_A" --quiet >/dev/null 2>&1; then
    gcloud compute instances create "$VM_1" \
        --zone="$ZONE_A" \
        --machine-type="$MACHINE_TYPE" \
        --network="$VPC_NAME" \
        --subnet="$SUBNET_A" \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --quiet
fi

if ! gcloud compute instances describe "$VM_2" --zone="$ZONE_B" --quiet >/dev/null 2>&1; then
    gcloud compute instances create "$VM_2" \
        --zone="$ZONE_B" \
        --machine-type="$MACHINE_TYPE" \
        --network="$VPC_NAME" \
        --subnet="$SUBNET_B" \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --quiet
fi

echo -e "${GREEN}Instances created successfully.${NC}\n"

# ------------------------------------------------------------------------------
# Task 4: Connectivity Test via SSH
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[4/4] Verifying connectivity between VM instances...${NC}"

# Fetch internal IP of us-test-02
VM2_INTERNAL_IP=$(gcloud compute instances describe "$VM_2" --zone="$ZONE_B" --format='get(networkInterfaces[0].networkIP)')

echo -e "Waiting for instance SSH services to initialize..."
sleep 25

# Execute ping check from us-test-01 to us-test-02
echo -e "Pinging ${VM_2} (${VM2_INTERNAL_IP}) from ${VM_1}..."
gcloud compute ssh "$VM_1" --zone="$ZONE_A" --command="ping -c 3 $VM2_INTERNAL_IP" --quiet || true

echo -e "\nPinging via internal DNS (${VM_2}.${ZONE_B})..."
gcloud compute ssh "$VM_1" --zone="$ZONE_A" --command="ping -c 3 ${VM_2}.${ZONE_B}" --quiet || true

echo -e "\n${GREEN}${BOLD}All tasks completed successfully! You can now check your progress in the lab window.${NC}\n"