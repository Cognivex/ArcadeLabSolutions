#!/bin/bash
# ==============================================================================
# Script Name : gsp161.sh
# Lab Name    : Test Network Latency Between VMs (GSP161)
# Repository  : https://github.com/Cognivex/ArcadeLabSolutions
# ==============================================================================

set -e

# Trap errors to prevent unexpected exit/terminal drops
trap 'echo "[ERROR] Error encountered on line $LINENO. Script halted."; exit 1' ERR

echo "=================================================================="
echo "Starting Lab: Test Network Latency Between VMs (GSP161)"
echo "=================================================================="

# Detect or prompt for Project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    read -p "Enter your GCP Project ID: " PROJECT_ID
    gcloud config set project "$PROJECT_ID"
fi
echo "Using Project ID: $PROJECT_ID"

# 1. Set default compute configuration
echo "--> Configuring default zone and region..."
gcloud config set compute/zone "europe-west1-d" --quiet
gcloud config set compute/region "europe-west1" --quiet

# 2. Check and retrieve subnets from existing network
echo "--> Verifying custom subnets..."
gcloud compute networks subnets list --network taw-custom-network || true

# 3. Create instances for Task 1
echo "--> Creating instance us-test-01 (europe-west1-d)..."
gcloud compute instances create us-test-01 \
    --subnet=subnet-europe-west1 \
    --zone=europe-west1-d \
    --machine-type=e2-standard-2 \
    --tags=ssh,http,rules \
    --quiet

echo "--> Creating instance us-test-02 (us-east1-b)..."
gcloud compute instances create us-test-02 \
    --subnet=subnet-us-east1 \
    --zone=us-east1-b \
    --machine-type=e2-standard-2 \
    --tags=ssh,http,rules \
    --quiet

# Identify the correct third subnet name (either subnet-us-east4 or existing US east subnet)
SUBNET_03=$(gcloud compute networks subnets list --network=taw-custom-network --filter="region:(us-east4)" --format="value(name)" 2>/dev/null || true)
if [ -z "$SUBNET_03" ]; then
    SUBNET_03="subnet-us-east4"
fi

echo "--> Creating instance us-test-03 (us-east4-c)..."
gcloud compute instances create us-test-03 \
    --subnet="$SUBNET_03" \
    --zone=us-east4-c \
    --machine-type=e2-standard-2 \
    --tags=ssh,http,rules \
    --quiet

# Wait for VM metadata and SSH daemon readiness
echo "--> Waiting 25 seconds for instances to initialize..."
sleep 25

# 4. Install networking tools & run traceroute on us-test-01 and us-test-02
echo "--> Installing networking diagnostic packages on us-test-01..."
gcloud compute ssh us-test-01 --zone=europe-west1-d --command="sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get -y install traceroute mtr tcpdump iperf whois dnsutils siege" --quiet

echo "--> Testing traceroute on us-test-01..."
gcloud compute ssh us-test-01 --zone=europe-west1-d --command="traceroute -m 10 www.icann.org || true" --quiet

echo "--> Installing networking diagnostic packages on us-test-02..."
gcloud compute ssh us-test-02 --zone=us-east1-b --command="sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get -y install traceroute mtr tcpdump iperf whois dnsutils siege" --quiet

# 5. Create us-test-04 for intra-region testing
echo "--> Creating instance us-test-04 (europe-west1-d)..."
gcloud compute instances create us-test-04 \
    --subnet=subnet-europe-west1 \
    --zone=europe-west1-d \
    --machine-type=e2-standard-2 \
    --tags=ssh,http \
    --quiet

# Wait for us-test-04 readiness
echo "--> Waiting 20 seconds for us-test-04 to initialize..."
sleep 20

echo "--> Installing diagnostic tools on us-test-04..."
gcloud compute ssh us-test-04 --zone=europe-west1-d --command="sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get -y install traceroute mtr tcpdump iperf whois dnsutils siege" --quiet

# 6. Execute iPerf latency and throughput validation
echo "--> Launching iPerf test between us-test-01 and us-test-02..."
# Start server in background on us-test-01
gcloud compute ssh us-test-01 --zone=europe-west1-d --command="nohup iperf -s -p 5001 > /dev/null 2>&1 &" --quiet
sleep 3

# Run client on us-test-02 against us-test-01 internal DNS
gcloud compute ssh us-test-02 --zone=us-east1-b --command="iperf -c us-test-01.europe-west1-d -p 5001 -t 5 || true" --quiet

echo "=================================================================="
echo "All tasks executed successfully!"
echo "Check your progress in the lab console for 100/100 points."
echo "=================================================================="