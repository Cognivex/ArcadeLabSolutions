#!/bin/bash

# Visual formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

echo -e "${BLUE}${BOLD}====================================================${RESET}"
echo -e "${BLUE}${BOLD}   Starting Resilient GSP1077 Lab Automation        ${RESET}"
echo -e "${BLUE}${BOLD}====================================================${RESET}"

# 1. Environment & Variable Initialization
echo -e "\n${YELLOW}Step 1: Setting up environment variables...${RESET}"
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)
export REGION="us-central1"
gcloud config set compute/region "$REGION" --quiet

echo -e "Retrieving Git server IP..."
export GIT_SERVER_IP=$(gcloud compute instances describe git-server --zone=us-central1-c --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)

if [ -z "$GIT_SERVER_IP" ]; then
    echo -e "${YELLOW}Could not automatically fetch GIT_SERVER_IP. Enter Git Server IP manually:${RESET}"
    read -r GIT_SERVER_IP
fi

echo -e "${GREEN}Project ID:${RESET} $PROJECT_ID"
echo -e "${GREEN}Project Number:${RESET} $PROJECT_NUMBER"
echo -e "${GREEN}Region:${RESET} $REGION"
echo -e "${GREEN}Git Server IP:${RESET} $GIT_SERVER_IP"

# Git config
git config --global user.name "giteaadmin"
git config --global user.email "student@qwiklabs.net"

# 2. Enable APIs & Create Core Resources
echo -e "\n${YELLOW}Step 2: Enabling APIs & creating Artifact Registry and GKE Cluster...${RESET}"
gcloud services enable container.googleapis.com \
    cloudbuild.googleapis.com \
    secretmanager.googleapis.com \
    containeranalysis.googleapis.com --quiet

gcloud artifacts repositories create my-repository \
    --repository-format=docker \
    --location="$REGION" 2>/dev/null || true

# Check if cluster already exists before creating
if ! gcloud container clusters describe hello-cloudbuild --region "$REGION" >/dev/null 2>&1; then
    echo -e "Creating GKE cluster (this will take 4-7 minutes, do not close the window)..."
    gcloud container clusters create hello-cloudbuild \
        --num-nodes 1 \
        --region "$REGION" \
        --async
    
    # Wait for cluster to become RUNNING without timing out
    until gcloud container clusters describe hello-cloudbuild --region "$REGION" --format="value(status)" 2>/dev/null | grep -q "RUNNING"; do
        echo -n "."
        sleep 10
    done
    echo -e "\n${GREEN}Cluster created successfully!${RESET}"
else
    echo -e "${GREEN}Cluster hello-cloudbuild already exists.${RESET}"
fi

# 3. Setup Application Repository
echo -e "\n${YELLOW}Step 3: Initializing and pushing hello-cloudbuild-app...${RESET}"
cd "$HOME" || exit
rm -rf hello-cloudbuild-app
mkdir -p hello-cloudbuild-app
gcloud storage cp -r gs://spls/gsp1077/gke-gitops-tutorial-cloudbuild/* hello-cloudbuild-app/

cd "$HOME/hello-cloudbuild-app" || exit
sed -i "s/us-central1/$REGION/g" cloudbuild.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-delivery.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-trigger-cd.yaml
sed -i "s/us-central1/$REGION/g" kubernetes.yaml.tpl

git init
git remote add origin "http://${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-app.git" 2>/dev/null || true
git branch -m main
git add .
git commit -m "initial commit" 2>/dev/null || true
git push -u "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-app.git" main -f

COMMIT_ID="$(git rev-parse --short=7 HEAD)"
gcloud builds submit --tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/my-repository/hello-cloudbuild:${COMMIT_ID}" .

git add .
git commit -m "Trigger CI pipeline" 2>/dev/null || true
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-app.git" main
gcloud builds submit --config=cloudbuild.yaml --substitutions=SHORT_SHA="$(git rev-parse --short=7 HEAD)" .

# 4. SSH Key Secret Setup
echo -e "\n${YELLOW}Step 4: Creating and storing SSH keys in Secret Manager...${RESET}"
mkdir -p "$HOME/workingdir" && cd "$HOME/workingdir" || exit
rm -f id_rsa id_rsa.pub
ssh-keygen -t rsa -b 4096 -N '' -f id_rsa -C "student@qwiklabs.net" <<< y >/dev/null 2>&1

gcloud secrets create ssh_key_secret --data-file="$HOME/workingdir/id_rsa" 2>/dev/null || \
gcloud secrets versions add ssh_key_secret --data-file="$HOME/workingdir/id_rsa" 2>/dev/null || true

gcloud projects add-iam-policy-binding "${PROJECT_NUMBER}" \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" --quiet

# 5. Setup Deployment Environment Repo & GKE Permissions
echo -e "\n${YELLOW}Step 5: Configuring hello-cloudbuild-env repository and IAM permissions...${RESET}"
gcloud projects add-iam-policy-binding "${PROJECT_NUMBER}" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/container.developer" --quiet

cd "$HOME" || exit
rm -rf hello-cloudbuild-env
mkdir -p ~/hello-cloudbuild-env
gcloud storage cp -r gs://spls/gsp1077/gke-gitops-tutorial-cloudbuild/* ~/hello-cloudbuild-env/
cd ~/hello-cloudbuild-env || exit
sed -i "s/us-central1/$REGION/g" cloudbuild.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-delivery.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-trigger-cd.yaml
sed -i "s/us-central1/$REGION/g" kubernetes.yaml.tpl

git init
git remote add origin "http://${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git" 2>/dev/null || true
git branch -m main
git add .
git commit -m "initial commit" 2>/dev/null || true
git push -u "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git" main -f

git checkout -b production 2>/dev/null || git checkout production
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git" production -f

git checkout -b candidate 2>/dev/null || git checkout candidate
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git" candidate -f

cat <<'EOF' > cloudbuild.yaml
substitutions:
  _COMMIT_SHA: 'v1.0'

steps:
- name: 'gcr.io/cloud-builders/kubectl'
  id: Deploy
  args:
  - 'apply'
  - '-f'
  - 'kubernetes.yaml'
  env:
  - 'CLOUDSDK_COMPUTE_REGION=us-central1'
  - 'CLOUDSDK_CONTAINER_CLUSTER=hello-cloudbuild'

- name: 'gcr.io/cloud-builders/gcloud'
  id: Copy to production branch
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    set -x && \
    git clone -b production http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git prod_repo && \
    cd prod_repo && \
    git config user.email "student@qwiklabs.net" && \
    git config user.name "Cloud Build" && \
    cp ../kubernetes.yaml kubernetes.yaml && \
    git add kubernetes.yaml && \
    git commit -m "Deployed manifest from commit $_COMMIT_SHA" && \
    git push origin production

options:
  logging: CLOUD_LOGGING_ONLY
EOF
sed -i "s/\${GIT_SERVER_IP}/$GIT_SERVER_IP/g" cloudbuild.yaml

git checkout candidate
git add cloudbuild.yaml
git commit -m "Create cloudbuild.yaml for deployment" 2>/dev/null || true
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git" candidate

# 6. Update App CI pipeline to trigger CD
echo -e "\n${YELLOW}Step 6: Updating CI pipeline in hello-cloudbuild-app to trigger CD...${RESET}"
cd "$HOME/hello-cloudbuild-app" || exit
cat <<'EOF' > cloudbuild.yaml
substitutions:
  _SHORT_SHA: 'v1.0'
  _COMMIT_SHA: 'v1.0'

steps:
- name: 'python:3.7-slim'
  id: Test
  entrypoint: /bin/sh
  args:
  - -c
  - 'pip install flask && python test_app.py -v'

- name: 'gcr.io/cloud-builders/docker'
  id: Build
  args:
  - 'build'
  - '-t'
  - 'us-central1-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$_SHORT_SHA'
  - '.'

- name: 'gcr.io/cloud-builders/docker'
  id: Push
  args:
  - 'push'
  - 'us-central1-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$_SHORT_SHA'

- name: 'gcr.io/cloud-builders/gcloud'
  id: Clone env repo
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    git clone http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git && \
    cd hello-cloudbuild-env && \
    git checkout candidate && \
    git config user.email "student@qwiklabs.net" && \
    git config user.name "Cloud Build"

- name: 'gcr.io/cloud-builders/gcloud'
  id: Generate manifest
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
     sed "s/GOOGLE_CLOUD_PROJECT/${PROJECT_ID}/g" kubernetes.yaml.tpl | \
     sed "s/COMMIT_SHA/${_SHORT_SHA}/g" > hello-cloudbuild-env/kubernetes.yaml

- name: 'gcr.io/cloud-builders/gcloud'
  id: Push manifest
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    set -x && \
    cd hello-cloudbuild-env && \
    git add kubernetes.yaml && \
    git commit -m "Deploying image us-central1-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:${_SHORT_SHA}
    Built from commit ${_COMMIT_SHA} of repository hello-cloudbuild-app
    Author: $(git log --format='%an <%ae>' -n 1 HEAD)" && \
    git push origin candidate

options:
  logging: CLOUD_LOGGING_ONLY
EOF
sed -i "s/\${GIT_SERVER_IP}/$GIT_SERVER_IP/g" cloudbuild.yaml

git add cloudbuild.yaml
git commit -m "Trigger CD pipeline" 2>/dev/null || true
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-app.git" main
gcloud builds submit --config=cloudbuild.yaml --substitutions=_SHORT_SHA="$(git rev-parse --short=7 HEAD)",_COMMIT_SHA="$(git rev-parse HEAD)" .

cd "$HOME/hello-cloudbuild-env" || exit
git pull "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git" candidate --no-edit
gcloud builds submit --config=cloudbuild.yaml --substitutions=_COMMIT_SHA="$(git rev-parse HEAD)" .

# 7. End-to-End Pipeline Update Test
echo -e "\n${YELLOW}Step 7: Testing application update (v2)...${RESET}"
cd "$HOME/hello-cloudbuild-app" || exit
sed -i 's/Hello World/Hello Cloud Build/g' app.py
sed -i 's/Hello World/Hello Cloud Build/g' test_app.py
git add app.py test_app.py
git commit -m "Hello Cloud Build" 2>/dev/null || true
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-app.git" main
gcloud builds submit --config=cloudbuild.yaml --substitutions=_SHORT_SHA="$(git rev-parse --short=7 HEAD)",_COMMIT_SHA="$(git rev-parse HEAD)" .

cd "$HOME/hello-cloudbuild-env" || exit
git pull "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/hello-cloudbuild-env.git" candidate --no-edit
gcloud builds submit --config=cloudbuild.yaml --substitutions=_COMMIT_SHA="$(git rev-parse HEAD)" .

echo -e "\n${GREEN}${BOLD}====================================================${RESET}"
echo -e "${GREEN}${BOLD}   Lab Pipeline Execution Completed Successfully!  ${RESET}"
echo -e "${GREEN}${BOLD}====================================================${RESET}"