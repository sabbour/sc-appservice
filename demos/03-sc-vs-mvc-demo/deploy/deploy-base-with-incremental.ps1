#
# Deploy Sitecore xM1 infrastructure components on ASP in two stages:
# - a nodb version of the Sitecore xM1 webdeploy packages (using an ARM template)
# - then on top of this, incremental deployment of custom source code
#
# TODO make sure to replace the license file location on Storage with a valid SAS token

[CmdletBinding()]
Param(
  # Params required for provisioning into the exsiting Resource group:
  [Parameter(Mandatory=$True)]
  [string]$SubscriptionName,
  
  [Parameter(Mandatory=$True)]
  [string]$RGName,
  
#   [Parameter(Mandatory=$True)]
#   [string]$Location,

  # Params required for KeyVault
  [Parameter(Mandatory=$True)]
  [string]$KeyVaultName

)

# Select the subscription
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

# Inspect input params of previous Sitecore deployment in same resource group:
$sitecoreDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $RGName -Name sitecore
$sitecoreDeploymentInput = $sitecoreDeployment.Parameters
$sitecoreDeploymentOutput = $sitecoreDeployment.Outputs
$storageAcctNameForWebDeployPackages = $sitecoreDeploymentInput.webDeployStorageName.Value
$cmWebAppName = $sitecoreDeploymentOutput.cmWebAppNameTidy.Value
$cdWebAppName = $sitecoreDeploymentOutput.cdWebAppNameTidy.Value

Write-Output "Storage account to which to publish web deploy packages: $storageAcctNameForWebDeployPackages"

Pause

# Upload CM and CD baseline packages to Storage
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $RGName -Name $storageAcctNameForWebDeployPackages
$ctx = $storageAccount.Context

$containerName = "tempsitecore821"
$container = New-AzureStorageContainer -Name $containerName -Permission Off -Context $ctx -ErrorAction SilentlyContinue

Write-Output "uploading CM package to storage"
$cmBlobName = "xm1CMNoDb.scwd.zip"
$localFile = ".\packages\" + $cmBlobName
Set-AzureStorageBlobContent -Container $containerName -File $localFile -Blob $cmBlobName -Context $ctx -Force

Write-Output "uploading CD package to storage"
$cdBlobName = "xm1CDNoDb.scwd.zip"
$localCdFile = ".\packages\" + $cdBlobName
Set-AzureStorageBlobContent -Container $containerName -File $localCdFile -Blob $cdBlobName -Context $ctx -Force

$containerSas = New-AzureStorageContainerSASToken -Context $ctx -Name $containerName -Permission r -ExpiryTime (Get-Date).AddHours(4)
Write-Host "SAS: $containerSas"

$cmWebdeployBasePackageUri = (Get-AzureStorageBlob -Blob $cmBlobName -Container $containerName -Context $ctx).ICloudBlob.Uri.AbsoluteUri + $containerSas
$cdWebdeployBasePackageUri = (Get-AzureStorageBlob -Blob $cdBlobName -Container $containerName -Context $ctx).ICloudBlob.Uri.AbsoluteUri + $containerSas

# Deploy Sitecore baseline
Write-Host "Deploying Sitecore Base Package (without db)"
 . "./deploy-webdeploy-sitecore-xm.ps1" `
  -SubscriptionName "$SubscriptionName" `
  -RGName "$RGName" `
  -KeyVaultName "$KeyVaultName" `
  -CMPackageUrl "$cmWebdeployBasePackageUri" `
  -CDPackageUrl "$cdWebdeployBasePackageUri"

# Compile and Deploy Sitecore customization package
Write-Host "Deploying Sitecore Customization Package towards CM"
 . "./deploy-incremental-webdeploy-to-slot.ps1" `
  -SubscriptionName "$SubscriptionName" `
  -RGName "$RGName" `
  -WebAppName "$cmWebAppName" `
  -SlotName cm-preprod

Write-Host "Deploying Sitecore Customization Package towards CD"
   . "./deploy-incremental-webdeploy-to-slot.ps1" `
  -SubscriptionName "$SubscriptionName" `
  -RGName "$RGName" `
  -WebAppName "$cdWebAppName" `
  -SlotName cd-preprod