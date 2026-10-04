#!/bin/bash
set -e

echo "============================================================"
echo " Starting Implement DevOps Workflows in Google Cloud (GSP330)"
echo "============================================================"

# Ensure terminal doesn't exit prematurely on subshell traps
trap 'echo "An error occurred, but keeping shell alive. Review logs above.";' ERR

# -------------------------------------------------------------
# 1. Setup Environment Variables and Defaults
# -------------------------------------------------------------
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
export REGION="${REGION:-us-east4}"
export ZONE="${ZONE:-us-east4-c}"
export CLUSTER_NAME="hello-cluster"
export REPO_NAME="my-repository"

gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# Fetch Git Server Internal/External NAT IP dynamically
echo "Fetching Git Server IP..."
export GIT_SERVER_IP=$(gcloud compute instances describe git-server --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
if [ -z "$GIT_SERVER_IP" ]; then
  echo "Retrying internal network interface for Git Server IP..."
  export GIT_SERVER_IP=$(gcloud compute instances describe git-server --zone="$ZONE" --format='get(networkInterfaces[0].networkIP)')
fi
echo "Git Server IP: ${GIT_SERVER_IP}"

# -------------------------------------------------------------
# 2. Enable APIs & Configure Service Accounts
# -------------------------------------------------------------
echo "Enabling Services..."
gcloud services enable container.googleapis.com cloudbuild.googleapis.com

echo "Granting roles/container.developer to Cloud Build Service Account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/container.developer" --condition=None

git config --global user.name "Student"
git config --global user.email "student@qwiklabs.net"

# -------------------------------------------------------------
# 3. Create Artifact Registry & GKE Cluster (Task 1)
# -------------------------------------------------------------
echo "Creating Artifact Registry..."
gcloud artifacts repositories create "$REPO_NAME" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker repository for sample app" || echo "Repository already exists."

echo "Creating GKE Cluster: ${CLUSTER_NAME}..."
gcloud container clusters create "$CLUSTER_NAME" \
  --zone="$ZONE" \
  --release-channel="regular" \
  --num-nodes=3 \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=6 \
  --quiet

gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE"

kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

# -------------------------------------------------------------
# 4. Clone Sample App & Setup Git Server (Task 2)
# -------------------------------------------------------------
echo "Setting up sample application..."
cd ~
rm -rf sample-app
mkdir -p sample-app
gcloud storage cp -r gs://spls/gsp330/sample-app/* sample-app/

for file in sample-app/cloudbuild-dev.yaml sample-app/cloudbuild.yaml; do
  sed -i "s/<your-region>/${REGION}/g" "$file"
  sed -i "s/<your-zone>/${ZONE}/g" "$file"
  sed -i "s/<version>/v1.0/g" "$file"
done

cd ~/sample-app
git init
git remote add origin "http://${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git" || true
git branch -m master
git add .
git commit -m "initial commit"
git push -u "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git" master --force

git checkout -b dev
git push -u "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git" dev --force

# -------------------------------------------------------------
# 5. Create Cloud Build Triggers (Task 3)
# -------------------------------------------------------------
echo "Creating Cloud Build Triggers..."
gcloud builds triggers create manual \
   --name="sample-app-prod-deploy" \
   --inline-config="cloudbuild.yaml" \
   --service-account="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
   --region="$REGION" || true

gcloud builds triggers create manual \
   --name="sample-app-dev-deploy" \
   --inline-config="cloudbuild-dev.yaml" \
   --service-account="projects/${PROJECT_ID}/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
   --region="$REGION" || true

# -------------------------------------------------------------
# 6. Deploy First Versions (v1.0) on dev and prod (Task 4)
# -------------------------------------------------------------
echo "Updating dev deployment spec (v1.0)..."
cd ~/sample-app
git checkout dev
sed -i "s|<todo>|${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/dev-sample-app:v1.0|g" dev/deployment.yaml
git add .
git commit -m "Deploy v1.0 on dev"
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git" dev --force

echo "Submitting dev build..."
gcloud builds submit --config=cloudbuild-dev.yaml .

echo "Exposing dev LoadBalancer service..."
kubectl expose deployment development-deployment --name=dev-deployment-service --type=LoadBalancer --port=8080 --target-port=8080 -n dev || true

echo "Updating prod deployment spec (v1.0)..."
git checkout master
sed -i "s|<todo>|${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/prod-sample-app:v1.0|g" prod/deployment.yaml
git add .
git commit -m "Deploy v1.0 on master"
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git" master --force

echo "Submitting prod build..."
gcloud builds submit --config=cloudbuild.yaml .

echo "Exposing prod LoadBalancer service..."
kubectl expose deployment production-deployment --name=prod-deployment-service --type=LoadBalancer --port=8080 --target-port=8080 -n prod || true

# -------------------------------------------------------------
# 7. Deploy Second Versions (v2.0) on dev and prod (Task 5)
# -------------------------------------------------------------
update_main_go() {
  cat <<'EOF' > main.go
package main

import (
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"net/http"
)

func main() {
	http.HandleFunc("/blue", blueHandler)
	http.HandleFunc("/red", redHandler)
	http.ListenAndServe(":8080", nil)
}

func blueHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{0, 0, 255, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}

func redHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}
EOF
}

echo "Updating code for dev (v2.0)..."
cd ~/sample-app
git checkout dev
update_main_go
sed -i 's/:v1.0/:v2.0/g' cloudbuild-dev.yaml
sed -i 's/:v1.0/:v2.0/g' dev/deployment.yaml
git add .
git commit -m "Deploy v2.0 on dev"
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git" dev --force

echo "Submitting dev v2.0 build..."
gcloud builds submit --config=cloudbuild-dev.yaml .

echo "Updating code for prod (v2.0)..."
git checkout master
update_main_go
sed -i 's/:v1.0/:v2.0/g' cloudbuild.yaml
sed -i 's/:v1.0/:v2.0/g' prod/deployment.yaml
git add .
git commit -m "Deploy v2.0 on master"
git push "http://giteaadmin:GiteaPassword123@${GIT_SERVER_IP}:3000/giteaadmin/sample-app.git" master --force

echo "Submitting prod v2.0 build..."
gcloud builds submit --config=cloudbuild.yaml .

# -------------------------------------------------------------
# 8. Roll Back Production Deployment (Task 6)
# -------------------------------------------------------------
echo "Rolling back production deployment to v1.0..."
kubectl rollout undo deployment/production-deployment -n prod

echo "Waiting for rollout rollback to finish..."
kubectl rollout status deployment/production-deployment -n prod

echo "============================================================"
echo " All lab tasks finished successfully!"
echo " Check all score progress buttons on the Qwiklabs console."
echo "============================================================"