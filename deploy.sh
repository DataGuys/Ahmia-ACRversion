#!/usr/bin/env bash
set -e

# List available subscriptions
echo "Available Azure Subscriptions:"
az account list --query "[].{Name:name, ID:id, State:state}" -o table

# Prompt for subscription selection
echo ""
echo "Please enter the number of the subscription you want to use:"
readarray -t SUB_IDS < <(az account list --query "[].id" -o tsv)
readarray -t SUB_NAMES < <(az account list --query "[].name" -o tsv)

for i in "${!SUB_IDS[@]}"; do
    echo "[$i] ${SUB_NAMES[$i]} (${SUB_IDS[$i]})"
done

read -p "Subscription number: " SUB_NUM
SUBSCRIPTION="${SUB_IDS[$SUB_NUM]}"

# Set the selected subscription
echo "Setting subscription to: ${SUB_NAMES[$SUB_NUM]}"
az account set --subscription "$SUBSCRIPTION"

# Prompt for Resource Group name
read -p "Enter Resource Group name: " RG

# Generate random values for unique resource names
RANDOM_SUFFIX=$RANDOM
ACR="ahmiaregistry$RANDOM_SUFFIX"
ACI="ahmiaContainer"
DNS_LABEL="ahmiademo$RANDOM_SUFFIX"
GIT_URL="https://github.com/DataGuys/Ahmia-ACRversion.git"

echo "Creating resource group: $RG"
az group create --name $RG --location eastus

echo "Creating ACR: $ACR"
az acr create --resource-group $RG --name $ACR --sku Basic --admin-enabled true

echo "Building Docker image from $GIT_URL..."
az acr build --registry $ACR --image ahmia:latest $GIT_URL

echo "Deploying container to ACI: $ACI"
az container create --resource-group $RG --name $ACI \
    --image $ACR.azurecr.io/ahmia:latest \
    --registry-login-server $ACR.azurecr.io \
    --registry-username $(az acr credential show -n $ACR --query "username" -o tsv) \
    --registry-password $(az acr credential show -n $ACR --query "passwords[0].value" -o tsv) \
    --dns-name-label $DNS_LABEL \
    --ports 8000

echo "Deployment complete! You can check your container status using:"
echo "az container show --resource-group $RG --name $ACI --output table"
echo "Your application will be available at: http://$DNS_LABEL.eastus.azurecontainer.io:8000"
