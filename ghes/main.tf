###############################################################################
# GitHub Enterprise Server on Azure
#
# Provisions a single GHES instance (VM, networking, data disk) on Azure.
# Remote state is stored in the Storage Account created by
# ../azure-storage-blob-backend.
###############################################################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstateghes"
    storage_account_name = "sttfstategheshgb"
    container_name       = "content-tfstateghes"
    key                  = "terraform.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  # subscription_id is resolved from the ARM_SUBSCRIPTION_ID environment variable.
  # Set it explicitly here (or via var.subscription_id) for production use.
  subscription_id = var.subscription_id != "" ? var.subscription_id : null

  features {}
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID. Falls back to the ARM_SUBSCRIPTION_ID environment variable when empty."
  default     = ""
}

variable "prefix" {
  type        = string
  description = "Prefix used for all resource names."
  default     = "ghes"
}

variable "location" {
  type        = string
  description = "Azure region for the deployment."
  default     = "southeastasia"
}

variable "ghes_version" {
  type        = string
  description = "GitHub Enterprise Server marketplace image version."
  default     = "3.21.1"
}

variable "image_sku" {
  type        = string
  description = "GHES marketplace image SKU. Use 'github-enterprise-gen2' for Generation 2 VMs or 'GitHub-Enterprise' for Generation 1."
  default     = "github-enterprise-gen2"
}

variable "vm_size" {
  type        = string
  description = "Azure VM size. Must meet GHES 3.x minimums (>= 8 vCPU / 32 GiB). Gen2 image SKUs require a Gen2-capable size."
  default     = "Standard_D8s_v5"
  # default     = "Standard_D16s_v5" # 16 vCPU 64 GiB ram  
}

variable "admin_username" {
  type        = string
  description = "Administrator username for the GHES VM."
  default     = "ghadmin"
}

variable "os_disk_size_gb" {
  type        = number
  description = "Root OS disk size in GiB."
  default     = 200
}

variable "data_disk_size_gb" {
  type        = number
  description = "Attached data disk size in GiB for GHES user data."
  default     = 200
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR range allowed to reach the administrative SSH port (122). Restrict this in production."
  default     = "*"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key used for VM administrative access."
  default     = "<yoursshpublickey>"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default = {
    environment = "production"
    managed_by  = "terraform"
    component   = "github-enterprise-server"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.prefix}"
  address_space       = ["10.0.0.0/24"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "internal" {
  name                 = "snet-${var.prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/25"]
}

resource "azurerm_public_ip" "main" {
  name                = "pip-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "main" {
  name                = "nic-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "ip-config-${var.prefix}"
    subnet_id                     = azurerm_subnet.internal.id
    public_ip_address_id          = azurerm_public_ip.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "web" {
  name                        = "allow-web-${var.prefix}"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  destination_port_ranges     = ["22", "25", "80", "443", "8080", "8443", "9418"]
  source_port_range           = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_network_security_rule" "admin_ssh" {
  name                        = "allow-admin-ssh-${var.prefix}"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  destination_port_range      = "122"
  source_port_range           = "*"
  source_address_prefix       = var.allowed_ssh_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_linux_virtual_machine" "main" {
  name                            = "vm-${var.prefix}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.main.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = "GitHub"
    offer     = "GitHub-Enterprise"
    sku       = var.image_sku
    version   = var.ghes_version
  }

  os_disk {
    name                 = "os-disk-${var.prefix}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  tags = var.tags
}

resource "azurerm_managed_disk" "main" {
  name                 = "data-${var.prefix}"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "main" {
  managed_disk_id    = azurerm_managed_disk.main.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = 10
  caching            = "ReadWrite"
}

output "public_ip" {
  value       = azurerm_public_ip.main.ip_address
  description = "The IP address of the GitHub Enterprise Server instance"
}
