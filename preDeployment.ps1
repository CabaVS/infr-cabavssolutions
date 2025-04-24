param (
  [Parameter(Mandatory = $true)][string]$resourceGroupName,
  [Parameter(Mandatory = $true)][string]$location,
  [Parameter(Mandatory = $true)][string]$sqlAdminsGroupName,
  [Parameter(Mandatory = $true)][string]$storageAccountName,
  [Parameter(Mandatory = $true)][string]$containerName
)

# Create Resource Group
Write-Host "📦 Creating a Resource Group $resourceGroupName..."
az group create `
  --name $resourceGroupName `
  --location $location

if ($LASTEXITCODE -ne 0) {
  Write-Host "❌ Failed to create Resource Group" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "✅ Resource Group is created"
}

# Create Azure AD group
Write-Host "👥 Creating Azure AD group: $sqlAdminsGroupName..."
az ad group create `
  --display-name $sqlAdminsGroupName `
  --mail-nickname $sqlAdminsGroupName

if ($LASTEXITCODE -ne 0) {
  Write-Host "❌ Failed to create Azure AD group" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "✅ Azure AD group created"
}

# Retrieve group details
$group = az ad group show --group $sqlAdminsGroupName | ConvertFrom-Json
$tenantId = az account show --query tenantId -o tsv

Write-Host "🔍 Group details ready:"
Write-Host "TF_VAR_sql_admin_group_display_name  = $($group.displayName)"
Write-Host "TF_VAR_sql_admin_group_object_id     = $($group.id)"
Write-Host "TF_VAR_sql_admin_group_tenant_id     = $tenantId"

Write-Host "💾 Creating Storage Account $storageAccountName..."
az storage account create `
  --name $storageAccountName `
  --resource-group $resourceGroupName `
  --location $location `
  --sku Standard_LRS `
  --kind StorageV2 `
  --enable-hierarchical-namespace false `
  --allow-blob-public-access false `
  --min-tls-version TLS1_2

if ($LASTEXITCODE -ne 0) {
  Write-Host "❌ Failed to create Storage Account" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "✅ Storage Account created"
}

# Enable blob versioning
Write-Host "🔄 Enabling versioning..."
az storage account blob-service-properties update `
  --account-name $storageAccountName `
  --enable-versioning true

# Enable soft delete
Write-Host "🧯 Enabling soft delete for blobs..."
az storage blob service-properties delete-policy update `
  --account-name $storageAccountName `
  --enable true `
  --days-retained 7

# Create container
Write-Host "📁 Creating blob container $containerName..."
$accountKey = az storage account keys list `
  --account-name $storageAccountName `
  --resource-group $resourceGroupName `
  --query '[0].value' -o tsv

az storage container create `
  --name $containerName `
  --account-name $storageAccountName `
  --account-key $accountKey `
  --public-access off

if ($LASTEXITCODE -ne 0) {
  Write-Host "❌ Failed to create container" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "✅ Blob container created"
}