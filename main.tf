terraform {
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

resource "azurerm_service_plan" "asp" {
  name                = "asp-cabavssolutions"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "webapp_expensetrackerapi" {
  name                = "app-expensetrackerapi"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = azurerm_service_plan.asp.location
  service_plan_id     = azurerm_service_plan.asp.id

  ftp_publish_basic_authentication_enabled       = false
  https_only                                     = true
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    always_on = true
  }
}

resource "azurerm_mssql_server" "mssql_server" {
  name                = "sql-cabavssolutions"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  version             = "12.0"

  azuread_administrator {
    login_username              = var.sql_admin_group_display_name
    object_id                   = var.sql_admin_group_object_id
    tenant_id                   = var.sql_admin_group_tenant_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "db_expensetracker" {
  name        = "sqldb-expensetracker"
  server_id   = azurerm_mssql_server.mssql_server.id
  max_size_gb = 2
  sku_name    = "Basic"

  lifecycle {
    prevent_destroy = true
  }
}