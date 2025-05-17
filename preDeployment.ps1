param (
  [Parameter(Mandatory = $true)][string]$resourceGroupName,
  [Parameter(Mandatory = $true)][string]$location,
  [Parameter(Mandatory = $true)][string]$sqlAdminsGroupName,
  [Parameter(Mandatory = $true)][string]$storageAccountName,
  [Parameter(Mandatory = $true)][string]$githubSpName,
  [Parameter(Mandatory = $true)][string]$githubRepo,
  [Parameter(Mandatory = $true)][string]$mainBranch,
  [Parameter(Mandatory = $true)][string]$githubEnvName
)

$tenantId = az account show --query tenantId -o tsv
$subId = az account show --query id -o tsv

# Create Resource Group
Write-Host "Creating a Resource Group $resourceGroupName..."
az group create `
  --name $resourceGroupName `
  --location $location

if ($LASTEXITCODE -ne 0) {
  Write-Host "Failed to create Resource Group" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "Resource Group is created"
}

# Create Storage Account
Write-Host "Creating Storage Account $storageAccountName..."
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
  Write-Host "Failed to create Storage Account" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "Storage Account created"
}

# Enable blob versioning
Write-Host "Enabling versioning..."
az storage account blob-service-properties update `
  --account-name $storageAccountName `
  --enable-versioning true

# Enable soft delete
Write-Host "Enabling soft delete for blobs..."
az storage blob service-properties delete-policy update `
  --account-name $storageAccountName `
  --enable true `
  --days-retained 7

# Create container
Write-Host "Creating blob container $containerName..."
$accountKey = az storage account keys list `
  --account-name $storageAccountName `
  --resource-group $resourceGroupName `
  --query '[0].value' -o tsv

az storage container create `
  --name terraform-state `
  --account-name $storageAccountName `
  --account-key $accountKey `
  --public-access off

az storage container create `
  --name app-configs `
  --account-name $storageAccountName `
  --account-key $accountKey `
  --public-access off

if ($LASTEXITCODE -ne 0) {
  Write-Host "Failed to create container" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "Blob container created"
}

# Create Azure AD group
Write-Host "Creating Azure AD group: $sqlAdminsGroupName..."
az ad group create `
  --display-name $sqlAdminsGroupName `
  --mail-nickname $sqlAdminsGroupName

if ($LASTEXITCODE -ne 0) {
  Write-Host "Failed to create Azure AD group" -ForegroundColor Red
  exit 1
}
else {
  Write-Host "Azure AD group created"
}

# Retrieve group details
$group = az ad group show --group $sqlAdminsGroupName | ConvertFrom-Json

Write-Host "Group details ready:"
Write-Host "TF_VAR_sql_admin_group_display_name  = $($group.displayName)"
Write-Host "TF_VAR_sql_admin_group_object_id     = $($group.id)"
Write-Host "TF_VAR_sql_admin_group_tenant_id     = $tenantId"

# Create SP for GitHub OIDC login
Write-Host "Creating Azure AD App for GitHub OIDC..."
$app = az ad app create --display-name $githubSpName | ConvertFrom-Json
$appId = $app.appId
$appObjectId = $app.id

az ad sp create --id $appId | Out-Null
Write-Host "App registration created: App ID = $appId"

# Add federated credentials
Write-Host "Adding federated credentials for GitHub repo $githubRepo..."

$tempFile = New-TemporaryFile
@"
{
  "name": "github-oidc",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$($githubRepo):ref:refs/heads/$($mainBranch)",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Out-File -Encoding utf8 -FilePath $tempFile.FullName

az ad app federated-credential create `
  --id $appObjectId `
  --parameters "@$($tempFile.FullName)"

Remove-Item $tempFile.FullName -Force

$tempFile = New-TemporaryFile
@"
{
  "name": "github-oidc-for-environment",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$($githubRepo):environment:$($githubEnvName)",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Out-File -Encoding utf8 -FilePath $tempFile.FullName

az ad app federated-credential create `
  --id $appObjectId `
  --parameters "@$($tempFile.FullName)"

Remove-Item $tempFile.FullName -Force

# Assign Contributor role
Write-Host "Assigning Contributor role on $resourceGroupName..."
az role assignment create `
  --assignee $appId `
  --role "Contributor" `
  --scope "/subscriptions/$subId/resourceGroups/$resourceGroupName"

# Assign User Access Administrator role
Write-Host "Assigning User Access Administrator role on $resourceGroupName..."
az role assignment create `
  --assignee $appId `
  --role "User Access Administrator" `
  --scope "/subscriptions/$subId/resourceGroups/$resourceGroupName"

# Assign Storage Blob Data Contributor
Write-Host "Granting storage access to Terraform backend..."
az role assignment create `
  --assignee $appId `
  --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/$subId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName"

Write-Host "OIDC setup complete!"
Write-Host "AZURE_CLIENT_ID        = $appId"
Write-Host "AZURE_TENANT_ID        = $tenantId"
Write-Host "AZURE_SUBSCRIPTION_ID  = $subId"