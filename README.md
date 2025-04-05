# Complete build of Ahmia on Azure ACR all modules.

```bash
## Quick Deployment

Deploy Ahmia to Azure with a single command (you'll be prompted for subscription ID and resource group):

```bash
echo "Available Azure Subscriptions:" && \
az account list --query "[].{Name:name, ID:id}" -o table && \
read -p "Enter your Subscription ID: " SUBSCRIPTION_ID && \
read -p "Enter Resource Group name: " RESOURCE_GROUP && \
curl -s https://raw.githubusercontent.com/DataGuys/Ahmia-ACRversion/main/deploy_to_azure.sh | \
bash -s -- $SUBSCRIPTION_ID $RESOURCE_GROUP
```
