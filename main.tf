terraform {
  required_version = "1.11.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.26.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {}
variable "sql_admin_group_display_name" {}
variable "sql_admin_group_object_id" {}
variable "sql_admin_group_tenant_id" {}

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}
