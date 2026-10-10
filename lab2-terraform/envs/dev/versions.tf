terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # allows 4.x, never 5.0 — always pin
    }
  }
}

provider "azurerm" {
  features {}
}
