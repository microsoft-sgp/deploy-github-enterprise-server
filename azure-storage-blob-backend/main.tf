###############################################################################
# Terraform backend bootstrap
#
# Provisions the Azure Storage Account used to store the remote Terraform state
# for the GitHub Enterprise Server deployment in ../ghes.
#
# Run this once (with a *local* state) before initializing the ghes/ workspace.
###############################################################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  # subscription_id is resolved from the ARM_SUBSCRIPTION_ID environment variable.
  # Set it explicitly here (or via var.subscription_id) for production use.
  subscription_id = var.subscription_id != "" ? var.subscription_id : null

  # Use Microsoft Entra ID (Azure AD) for Storage data-plane operations.
  # Required because the subscription policy disables shared-key authentication.
  storage_use_azuread = true

  features {}
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID. Falls back to the ARM_SUBSCRIPTION_ID environment variable when empty."
  default     = ""
}

variable "prefix" {
  type        = string
  description = "Prefix used for all backend resource names."
  default     = "tfstateghes"
}

variable "location" {
  type        = string
  description = "Azure region for the backend resources."
  default     = "southeastasia"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all backend resources."
  default = {
    environment = "shared"
    managed_by  = "terraform"
    component   = "tfstate-backend"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "main" {
  name                            = "st${var.prefix}hgb"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "main" {
  name                  = "content-${var.prefix}"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "Resource group holding the Terraform state backend."
}

output "storage_account_name" {
  value       = azurerm_storage_account.main.name
  description = "Storage account used as the Terraform backend."
}

output "container_name" {
  value       = azurerm_storage_container.main.name
  description = "Blob container used to store the Terraform state file."
}
