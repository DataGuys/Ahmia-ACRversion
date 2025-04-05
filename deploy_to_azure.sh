#!/bin/bash
# Simplified deployment script that accepts parameters from the one-liner

set -e

# Accept subscription ID and resource group as parameters
SUBSCRIPTION="$1"
RG="$2"

# Show usage if parameters are missing
if [ -z "$SUBSCRIPTION" ] || [ -z "$RG" ]; then
    echo "Usage: $0 <subscription-id> <resource-group-name>"
    exit 1
fi

# Validate subscription ID
if ! az account show --subscription "$SUBSCRIPTION" &>/dev/null; then
    echo "Error: Invalid subscription ID. Please check and try again."
    exit 1
fi

echo "Setting subscription to: $SUBSCRIPTION"
az account set --subscription "$SUBSCRIPTION"

LOCATION="eastus"

echo "Creating/using resource group: $RG in $LOCATION"
az group create --name "$RG" --location "$LOCATION" --output none

# Generate random suffix to keep resource names unique
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

# Create or reuse ACR
echo "Creating ACR: $ACR (SKU: Basic)"
az acr create \
  --resource-group "$RG" \
  --name "$ACR" \
  --sku Basic \
  --admin-enabled true \
  --output none

echo "ACR created (or already exists)."

# Build & push Docker image to ACR
echo "Building Docker image from GitHub repo..."
az acr build \
  --registry "$ACR" \
  --image "ahmia:latest" \
  --file Dockerfile \
  "https://github.com/DataGuys/Ahmia-ACRversion.git"

# Deploy to Azure Container Instances
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
