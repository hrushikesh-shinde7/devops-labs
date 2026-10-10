#!/usr/bin/env bash
# Creates the Azure Storage backend that will hold Terraform state.
# Chicken-and-egg: the thing storing state can't be created by the Terraform that uses it.
set -euo pipefail

LOCATION="${LOCATION:-centralindia}"
RG="${RG:-rg-tfstate}"
CONTAINER="${CONTAINER:-tfstate}"
# storage account names: 3-24 chars, lowercase alphanumeric, globally unique
SA="${SA:-sttfstate$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')}"

echo "Resource group : $RG"
echo "Storage account: $SA"
echo "Container      : $CONTAINER"
echo "Location       : $LOCATION"
echo

command -v az >/dev/null || { echo "az CLI not found" >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "Run 'az login' first" >&2; exit 1; }

az group create --name "$RG" --location "$LOCATION" --output none
echo "✓ resource group"

az storage account create \
  --name "$SA" --resource-group "$RG" --location "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none
echo "✓ storage account"

# versioning lets you recover a corrupted state file
az storage account blob-service-properties update \
  --account-name "$SA" --resource-group "$RG" \
  --enable-versioning true --output none
echo "✓ blob versioning (state recovery)"

az storage container create \
  --name "$CONTAINER" --account-name "$SA" \
  --auth-mode login --output none
echo "✓ container"

cat <<EOF

────────────────────────────────────────────────────────
Put this in envs/dev/backend.tf:

terraform {
  backend "azurerm" {
    resource_group_name  = "$RG"
    storage_account_name = "$SA"
    container_name       = "$CONTAINER"
    key                  = "dev.tfstate"
  }
}
────────────────────────────────────────────────────────

Locking is automatic — the azurerm backend takes a blob lease.
EOF
