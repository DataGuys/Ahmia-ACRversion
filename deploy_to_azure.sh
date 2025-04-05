#!/bin/bash
# Fixed deployment script for Azure Cloud Shell compatibility

set -e

# ------------------------------------------------------------------------------
# DEPLOY_TO_AZURE.SH
# ------------------------------------------------------------------------------
# Purpose:
#   - Deploy the Ahmia multi-container solution to Azure
#   - Uses Azure Container Registry for Docker images
#
# Usage:
#   ./deploy_to_azure.sh
# ------------------------------------------------------------------------------

# 1) List subscriptions and let user choose one
echo "Available Azure Subscriptions:"
az account list --query "[].{Name:name, ID:id}" -o table

echo ""
echo "Please enter the Subscription ID you want to use:"
read SUBSCRIPTION

# Validate subscription ID
if ! az account show --subscription "$SUBSCRIPTION" &>/dev/null; then
    echo "Error: Invalid subscription ID. Please check and try again."
    exit 1
fi

echo "Setting subscription to: $SUBSCRIPTION"
az account set --subscription "$SUBSCRIPTION"

# 2) Prompt for Resource Group name
read -p "Enter Resource Group name (e.g. 'AhmiaRG'): " RG
LOCATION="eastus"

echo "Creating/using resource group: $RG in $LOCATION"
az group create --name "$RG" --location "$LOCATION" --output none

# 3) Generate random suffix to keep resource names unique
RANDOM_SUFFIX=$(date +%s)
ACR="ahmiareg${RANDOM_SUFFIX}"
ACI="ahmiaContainer"
DNS_LABEL="ahmia${RANDOM_SUFFIX}"

echo ""
echo "------------------------------------------------------------"
echo "Resource Group:    $RG"
echo "Location:          $LOCATION"
echo "ACR Name:          $ACR"
echo "ACI Container:     $ACI"
echo "DNS Label:         $DNS_LABEL"
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

# 5) Build & push Docker image to ACR
echo "Building Docker image from GitHub repo..."
az acr build \
  --registry "$ACR" \
  --image "ahmia:latest" \
  --file Dockerfile \
  "https://github.com/DataGuys/Ahmia-ACRversion.git"

# 6) Deploy to Azure Container Instances
echo "Deploying container to ACI: $ACI"
ACR_USERNAME=$(az acr credential show -n "$ACR" --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show -n "$ACR" --query "passwords[0].value" -o tsv)

az container create \
  --resource-group "$RG" \
  --name "$ACI" \
  --image "${ACR}.azurecr.io/ahmia:latest" \
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
echo ""
echo "Public FQDN is:   http://${DNS_LABEL}.${LOCATION}.azurecontainer.io"
echo ""
echo "========================================"
