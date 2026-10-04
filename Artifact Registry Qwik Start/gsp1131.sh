#!/bin/bash
# ==============================================================================
# Script Name : gsp1131.sh
# Description : Solution for "Artifact Registry: Qwik Start" (GSP1131)
# ==============================================================================

set -e

# Visual formatting
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

echo "${CYAN}${BOLD}Starting setup for Artifact Registry: Qwik Start (GSP1131)...${RESET}"

# Fetch project ID and set defaults
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export REPO_NAME="example-docker-repo"
export IMAGE_SOURCE="us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0"
export TARGET_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/sample-image:tag1"

echo "${YELLOW}Project ID: ${PROJECT_ID}${RESET}"
echo "${YELLOW}Region    : ${REGION}${RESET}"

# Task 1: Create a Docker repository
echo "${BOLD}Step 1: Creating Artifact Registry Docker repository...${RESET}"
gcloud artifacts repositories create "${REPO_NAME}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Docker repository" \
    --project="${PROJECT_ID}" --quiet || true

# Task 2: Configure authentication
echo "${BOLD}Step 2: Configuring Docker authentication...${RESET}"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Task 3: Obtain image
echo "${BOLD}Step 3: Pulling source Docker image...${RESET}"
docker pull "${IMAGE_SOURCE}"

# Task 4: Tag and push image
echo "${BOLD}Step 4: Tagging and pushing Docker image to Artifact Registry...${RESET}"
docker tag "${IMAGE_SOURCE}" "${TARGET_IMAGE}"
docker push "${TARGET_IMAGE}"

# Task 5: Pull the image from repository
echo "${BOLD}Step 5: Verifying image pull from private repository...${RESET}"
docker pull "${TARGET_IMAGE}"

echo "${GREEN}${BOLD}Lab completed successfully! You can now check your progress in Cloud Skills Boost.${RESET}"