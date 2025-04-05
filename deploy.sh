#!/usr/bin/env bash
set -e

# ------------------------------------------------------------------------------
# DEPLOY.SH
# ------------------------------------------------------------------------------
# Purpose:
#   - Prompt user for Azure subscription and set it
#   - Prompt user for Resource Group name
#   - Creates or reuses that Resource Group
#   - Creates or reuses an ACR with a random suffix
#   - Builds a Docker image from a GitHub repo and pushes it to ACR
#   - Deploys the container to Azure Container Instances (ACI) 
#     with ports 80 and 443 open (for potential SSL).
#
# Usage:
#   ./deploy.sh
#
# Notes:
#   - This script uses the ACR admin account for simplicity.
#   - For production, consider using managed identities or service principals 
#     instead of the admin account.
# ------------------------------------------------------------------------------

# 1) Prompt user to select a subscription
echo "Available Azure Subscriptions:"
az account list --query "[].{Name:name, ID:id, State:state}" -o table

echo ""
echo "Please enter the number of the subscription you want to use:"
readarray -t SUB_IDS < <(az account list --query "[].id" -o tsv)
readarray -t SUB_NAMES < <(az account list --query "[].name" -o tsv)

for i in "${!SUB_IDS[@]}"; do
    echo "[$i] ${SUB_NAMES[$i]} (${SUB_IDS[$i]})"
done

read -p "Subscription number: " SUB_NUM
SUBSCRIPTION="${SUB_IDS[$SUB_NUM]}"
SUBSCRIPTION_NAME="${SUB_NAMES[$SUB_NUM]}"

echo "Setting subscription to: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION})"
az account set --subscription "$SUBSCRIPTION"

# 2) Prompt for Resource Group name
read -p "Enter Resource Group name (e.g. 'AhmiaRG'): " RG
LOCATION="eastus"

echo "Creating/using resource group: $RG"
az group create --name "$RG" --location "$LOCATION" --output none

# 3) Generate random suffix to keep resource names unique
RANDOM_SUFFIX=$RANDOM
ACR="ahmiaregistry${RANDOM_SUFFIX}"
ACI="ahmiaContainer"
DNS_LABEL="ahmiademo${RANDOM_SUFFIX}"
GIT_URL="https://github.com/DataGuys/Ahmia-ACRversion.git"
IMAGE_NAME="ahmia:latest"   # or specify a different tag if you like

echo ""
echo "------------------------------------------------------------"
echo "Resource Group:    $RG"
echo "Location:          $LOCATION"
echo "ACR Name:          $ACR"
echo "ACI Container:     $ACI"
echo "DNS Label:         $DNS_LABEL"
echo "Docker Image Name: $IMAGE_NAME"
echo "GitHub URL:        $GIT_URL"
echo "------------------------------------------------------------"
echo ""

# 4) Create or reuse ACR
echo "Creating ACR: $ACR (SKU: Basic)"
az acr create \
  --resource-group "$RG" \
  --name "$ACR" \
  --sku Basic \
  --admin-enabled true \
  --output none

echo "ACR created (or already exists)."

# 5) Build & push Docker image to ACR using Azure's cloud build
echo "Building Docker image ($IMAGE_NAME) from $GIT_URL..."
az acr build \
  --registry "$ACR" \
  --image "$IMAGE_NAME" \
  "$GIT_URL"

# 6) Deploy to Azure Container Instances
echo "Deploying container to ACI: $ACI"
ACR_USERNAME=$(az acr credential show -n "$ACR" --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show -n "$ACR" --query "passwords[0].value" -o tsv)

# Expose ports 80 and 443 for an NGINX-based container. 
# If you want just port 8000, adjust accordingly.
az container create \
  --resource-group "$RG" \
  --name "$ACI" \
  --image "${ACR}.azurecr.io/${IMAGE_NAME}" \
  --registry-login-server "${ACR}.azurecr.io" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --dns-name-label "$DNS_LABEL" \
  --ports 80 443 \
  --restart-policy Always \
  --cpu 2 \
  --memory 4 \
  --location "$LOCATION" \
  --output none

echo ""
echo "========================================"
echo "Deployment complete!"
echo "You can check the container status with:"
echo "  az container show --resource-group $RG --name $ACI --output table"
echo ""
echo "Public FQDN is:   http://${DNS_LABEL}.${LOCATION}.azurecontainer.io"
echo "If SSL is configured and your container is listening on 443, try:"
echo "  https://${DNS_LABEL}.${LOCATION}.azurecontainer.io"
echo "========================================"
