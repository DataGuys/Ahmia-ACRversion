#!/usr/bin/env bash
set -e

# ------------------------------------------------------------------------------
# DEPLOY_TO_AZURE.SH
# ------------------------------------------------------------------------------
# Purpose:
#   - Deploy the Ahmia multi-container solution to Azure Container Apps/Instances
#   - Uses Azure Container Registry for storing Docker images
#   - Handles all the Ahmia components (site, index, crawler) as a unit
#
# Usage:
#   ./deploy_to_azure.sh
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
ACA="ahmiaApp"
DNS_LABEL="ahmia${RANDOM_SUFFIX}"

echo ""
echo "------------------------------------------------------------"
echo "Resource Group:   $RG"
echo "Location:         $LOCATION"
echo "ACR Name:         $ACR"
echo "Container App:    $ACA"
echo "DNS Label:        $DNS_LABEL"
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

# 5) Login to ACR
echo "Logging in to ACR..."
az acr login --name "$ACR"

# 6) Build and push the Docker images
echo "Building and pushing Docker images to ACR..."

# Make sure Docker Compose is installed
if ! command -v docker-compose &> /dev/null
then
    echo "Docker Compose could not be found. Please install it first."
    exit 1
fi

# Modify docker-compose.yml to use ACR
REPO="${ACR}.azurecr.io"
sed -i "s|build:|image: ${REPO}/ahmia-\${service}:latest\n    build:|g" docker-compose.yml

# Build and push images
docker-compose build
docker-compose push

# 7) Set up log analytics workspace for Container Apps
echo "Creating Log Analytics workspace..."
WORKSPACE="${ACA}-logs"

az monitor log-analytics workspace create \
  --resource-group "$RG" \
  --workspace-name "$WORKSPACE" \
  --output none

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" \
  --workspace-name "$WORKSPACE" \
  --query customerId \
  --output tsv)

WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RG" \
  --workspace-name "$WORKSPACE" \
  --query primarySharedKey \
  --output tsv)

# 8) Create Container App Environment
echo "Creating Container App Environment..."
az containerapp env create \
  --resource-group "$RG" \
  --name "${ACA}-env" \
  --location "$LOCATION" \
  --logs-workspace-id "$WORKSPACE_ID" \
  --logs-workspace-key "$WORKSPACE_KEY" \
  --output none

# 9) Get ACR credentials for Container Apps
echo "Getting ACR credentials..."
ACR_USERNAME=$(az acr credential show -n "$ACR" --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show -n "$ACR" --query "passwords[0].value" -o tsv)

# 10) Deploy Elasticsearch container
echo "Deploying Elasticsearch container..."
az containerapp create \
  --resource-group "$RG" \
  --name "${ACA}-elasticsearch" \
  --environment "${ACA}-env" \
  --image "docker.elastic.co/elasticsearch/elasticsearch:8.17.1" \
  --registry-server "${ACR}.azurecr.io" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --target-port 9200 \
  --ingress 'internal' \
  --env-vars "discovery.type=single-node" "ES_JAVA_OPTS=-Xms512m -Xmx512m" "xpack.security.enabled=true" "ELASTIC_PASSWORD=password12345" \
  --cpu 1 \
  --memory 2Gi \
  --min-replicas 1 \
  --max-replicas 1 \
  --output none

# 11) Deploy Ahmia Index container
echo "Deploying Ahmia Index container..."
az containerapp create \
  --resource-group "$RG" \
  --name "${ACA}-index" \
  --environment "${ACA}-env" \
  --image "${ACR}.azurecr.io/ahmia-index:latest" \
  --registry-server "${ACR}.azurecr.io" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --env-vars "ES_URL=https://${ACA}-elasticsearch:9200/" "ES_USERNAME=elastic" "ES_PASSWORD=password12345" "ES_CA_CERTS=/usr/local/share/ca-certificates/http_ca.crt" \
  --cpu 0.5 \
  --memory 1Gi \
  --min-replicas 1 \
  --max-replicas 1 \
  --output none

# 12) Deploy Tor Proxy container
echo "Deploying Tor Proxy container..."
az containerapp create \
  --resource-group "$RG" \
  --name "${ACA}-torproxy" \
  --environment "${ACA}-env" \
  --image "dperson/torproxy" \
  --registry-server "${ACR}.azurecr.io" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --target-port 9050 \
  --ingress 'internal' \
  --cpu 0.5 \
  --memory 1Gi \
  --min-replicas 1 \
  --max-replicas 1 \
  --output none

# 13) Deploy Ahmia Crawler container
echo "Deploying Ahmia Crawler container..."
az containerapp create \
  --resource-group "$RG" \
  --name "${ACA}-crawler" \
  --environment "${ACA}-env" \
  --image "${ACR}.azurecr.io/ahmia-crawler:latest" \
  --registry-server "${ACR}.azurecr.io" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --env-vars "ES_URL=https://${ACA}-elasticsearch:9200/" "ES_USERNAME=elastic" "ES_PASSWORD=password12345" "ES_CA_CERTS=/usr/local/share/ca-certificates/http_ca.crt" "HTTP_PROXY=socks5://${ACA}-torproxy:9050" \
  --cpu 1 \
  --memory 1.5Gi \
  --min-replicas 1 \
  --max-replicas 1 \
  --output none

# 14) Deploy Ahmia Site container
echo "Deploying Ahmia Site container..."
az containerapp create \
  --resource-group "$RG" \
  --name "${ACA}-site" \
  --environment "${ACA}-env" \
  --image "${ACR}.azurecr.io/ahmia-site:latest" \
  --registry-server "${ACR}.azurecr.io" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --target-port 80 \
  --ingress 'external' \
  --env-vars "ES_URL=https://${ACA}-elasticsearch:9200/" "ES_USERNAME=elastic" "ES_PASSWORD=password12345" "ES_CA_CERTS=/usr/local/share/ca-certificates/http_ca.crt" "ELASTICSEARCH_TIMEOUT=60" \
  --cpu 1 \
  --memory 1.5Gi \
  --min-replicas 1 \
  --max-replicas 3 \
  --output none

# 15) Get the FQDN of the application
FQDN=$(az containerapp show \
  --resource-group "$RG" \
  --name "${ACA}-site" \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

echo ""
echo "========================================"
echo "Deployment complete!"
echo "Your Ahmia application is available at: https://$FQDN"
echo "========================================"
