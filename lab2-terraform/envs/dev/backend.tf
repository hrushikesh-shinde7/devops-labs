# ⚠️ Run ../../bootstrap/bootstrap.sh FIRST, then paste the storage account
#    name it prints into storage_account_name below and uncomment this block.
#
# Backend config cannot use variables — it must be literal.

# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-tfstate"
#     storage_account_name = "REPLACE_ME"
#     container_name       = "tfstate"
#     key                  = "dev.tfstate"
#   }
# }
