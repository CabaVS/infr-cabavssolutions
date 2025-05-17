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
variable "storage_account_name" {}
variable "sql_admin_group_display_name" {}
variable "sql_admin_group_object_id" {}
variable "sql_admin_group_tenant_id" {}

# Existing Resource Group
data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

# Existing Storage Account
data "azurerm_storage_account" "existing" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-cabavssolutions"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Container App Environment
resource "azurerm_container_app_environment" "ace" {
  name                       = "ace-cabavssolutions"
  location                   = data.azurerm_resource_group.existing.location
  resource_group_name        = data.azurerm_resource_group.existing.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# Container App for Expense Tracker API
resource "azurerm_container_app" "aca_expensetrackerapi" {
  name                         = "aca-expensetrackerapi"
  container_app_environment_id = azurerm_container_app_environment.ace.id
  resource_group_name          = data.azurerm_resource_group.existing.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uai_acr_pull.id, azurerm_user_assigned_identity.sa_blob_reader.id]
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      label           = "primary"
      latest_revision = true
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].container[0].image
    ]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.uai_acr_pull.id
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "expensetrackerapi"
      image  = "mcr.microsoft.com/dotnet/samples:aspnetapp"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }
}

# SQL Server
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

# SQL Database for Expense Tracker API
resource "azurerm_mssql_database" "db_expensetracker" {
  name      = "sqldb-expensetracker"
  server_id = azurerm_mssql_server.mssql_server.id

  sku_name             = "GP_S_Gen5_1"
  storage_account_type = "Local"

  auto_pause_delay_in_minutes = 15
  max_size_gb                 = 2
  min_capacity                = 0.5
  read_replica_count          = 0
  read_scale                  = false
  zone_redundant              = false

  lifecycle {
    prevent_destroy = true
  }
}

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "crcabavssolutions"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  sku                 = "Basic"
  admin_enabled       = false
}

# User-Assigned Managed Identity
resource "azurerm_user_assigned_identity" "uai_acr_pull" {
  name                = "uai-acr-pull"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
}

resource "azurerm_user_assigned_identity" "sa_blob_reader" {
  name                = "sa-blob-reader"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
}

# Role assignments
resource "azurerm_role_assignment" "acr_pull_assignment" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.uai_acr_pull.principal_id
}

resource "azurerm_role_assignment" "sa_blob_reader_assignment" {
  scope                = data.azurerm_storage_account.existing.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.sa_blob_reader.principal_id
}