#
# Deploy Sitecore xM1 infrastructure components on ASP - leverage original ARM as shared on
# https://github.com/Sitecore/Sitecore-Azure-Quickstart-Templates/tree/master/Sitecore%208.2.1
#
# TODO make sure to replace the license file location on Storage with a valid SAS token

[CmdletBinding()]
Param(
  # Params required for provisioning into the exsiting Resource group:
  [Parameter(Mandatory=$True)]
  [string]$SubscriptionName,
  
  [Parameter(Mandatory=$True)]
  [string]$RGName,
  
  [Parameter(Mandatory=$True)]
  [string]$Location,

  # Params required for Sitecore infra deployment:
  [Parameter(Mandatory=$True)]
  [string]$ResourcePrefix,

  [Parameter(Mandatory=$True)]
  [string]$SitecorePwd,

  [Parameter(Mandatory=$True)]
  [string]$SqlServerLogin,

  [Parameter(Mandatory=$True)]
  [string]$SqlServerPwd,

  [Parameter(Mandatory=$True)]
  [string]$StorageAccountNameDeploy,

  [Parameter(Mandatory=$False)]
  [string]$PathToSitecoreLicenseFile = ".\license.xml",

  [Parameter(Mandatory=$false)]
  [switch]$OnlyGenerateParamsFile,

  [Parameter(Mandatory=$false)]
  [switch]$LeaveTempFilesOnDisk
)


$ErrorActionPreference = "Stop"

Select-AzureRmSubscription -SubscriptionName $SubscriptionName
Write-Host "Selected subscription: $SubscriptionName"

# Check if given license file exists
if ( ! (test-path -pathtype leaf $PathToSitecoreLicenseFile)) {
  throw "LICENSE FILE DOES NOT EXIST - PLEASE SPECIFY VALID LICENSE FILE"
}

# Find existing or deploy new Resource Group:
$rg = Get-AzureRmResourceGroup -Name $RGName -ErrorAction SilentlyContinue
if (-not $rg)
{
    New-AzureRmResourceGroup -Name "$RGName" -Location "$Location"
    Write-Host "New resource group deployed: $RGName"   
}
else{ Write-Host "Resource group found: $RGName"}



$scriptDir = Split-Path $MyInvocation.MyCommand.Path 

#============================
#Create a new container, upload the Webdeploy Sitecore packages and save the new URLs to variables

# Create Storage Account if not exists yet
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $RGName -Name $StorageAccountNameDeploy -ErrorAction SilentlyContinue
if(!$storageAccount)
{
  $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $RGName -Name $StorageAccountNameDeploy -Location $Location -SkuName "Standard_LRS"
  Write-Host "New storage account created: $StorageAccountNameDeploy"
}
else{ Write-Host "Storage account found: $StorageAccountNameDeploy"}

$ctx = $storageAccount.Context

# Create container to upload packages towards
$containerName = "tempsitecore821"
$container = New-AzureStorageContainer -Name $containerName -Permission Off -Context $ctx -ErrorAction SilentlyContinue

# Upload XM1 package to container, so it is available for ARM deployment
$cmBlobName = "Sitecore 8.2 rev. 161115_cm.scwdp"
$localFile = ".\packages\xM1\" + $cmBlobName
Set-AzureStorageBlobContent -Container $containerName -File $localFile -Blob $cmBlobName -Context $ctx -Force

$cdBlobName = "Sitecore 8.2 rev. 161115_cd.scwdp"
$localCdFile = ".\packages\xM1\" + $cdBlobName
Set-AzureStorageBlobContent -Container $containerName -File $localCdFile -Blob $cdBlobName -Context $ctx -Force

# Create SAS token for the container
$containerSas = New-AzureStorageContainerSASToken -Context $ctx -Name $containerName -Permission r -ExpiryTime (Get-Date).AddHours(4)

Write-Host "Sas s$containerSas"

$cmWebdeployPackageUri = (Get-AzureStorageBlob -Blob $cmBlobName -Container $containerName -Context $ctx).ICloudBlob.Uri.AbsoluteUri + $containerSas
$cdWebdeployPackageUri = (Get-AzureStorageBlob -Blob $cdBlobName -Container $containerName -Context $ctx).ICloudBlob.Uri.AbsoluteUri + $containerSas

#============================

Write-Output "Blob URL and SAS - $cdWebdeployPackageUri"

#NOTE - License file should be copied locally in the same folder as this script
$licenseFileContent = Get-Content -Raw -Encoding UTF8 -Path $PathToSitecoreLicenseFile | Out-String;

#============================
#Generate the parameters Json file dynamically to allow for . dots in naming
$paramsFile = @{
    '$schema' = "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        deploymentId = @{
           value = "$ResourcePrefix"
        }
        'sitecore.admin.password' =  @{
            value = "$SitecorePwd"
            }
       'sqlserver.login' =  @{
            value = "$SqlServerLogin"
        }
        'sqlserver.password' =  @{
          value ="$SqlServerPwd"
        }
        'cm.msdeploy.packageurl' =  @{
          value = "$cmWebdeployPackageUri"
        }
        'cd.msdeploy.packageurl' =  @{
          value = "$cdWebdeployPackageUri"
        }
        'cm.hostingplan.skuname' =  @{
          value = "S3"
        }
        'cd.hostingplan.skuname' =  @{
          value = "S3"
        }       
        licenseXml =  @{
          value = "$licenseFileContent"
        } 
    }       
}
  
$paramsFilePath = "$scriptDir\xm-asp-sitecore.parameters.tmp.json"
Write-Host "Temp params file to be written to: $paramsFilePath"
$paramsFile | ConvertTo-Json -Depth 5 | Out-File $paramsFilePath

#============================
# Deploy ARM template
if($OnlyGenerateParamsFile -eq $false){
  New-AzureRmResourceGroupDeployment -Verbose -Force -ErrorAction Stop `
    -Name "sitecore" `
    -ResourceGroupName $RGName `
    -TemplateFile "$scriptDir/templates/xm/azuredeploy.json" `
    -TemplateParameterFile $paramsFilePath 
}

# Clean up temporary params file:
if($LeaveTempFilesOnDisk -eq $false) {
  Remove-Item -Path $paramsFilePath
}

#============================
#Generate XML parameter files - first load some param values needed further - this is a step to streamline hackathon step 4

$dbServerFullyQualified = "$ResourcePrefix-sql.database.windows.net"
$webDbServerFullyQualified = "$ResourcePrefix-web-sql.database.windows.net"
$searchApiKey = ""
$aiInstrumentationKey = ""
$cmHostname = "$ResourcePrefix-cm.azurewebsits.net"
$cdHostname = "$ResourcePrefix-cd.azurewebsits.net"
$redisKey = ""
$redisConnString = ""
$licenseEncoded = [System.Security.SecurityElement]::Escape($licenseFileContent)

# Search stuff
$searchResource = Get-AzureRmResource `
    -ResourceType "Microsoft.Search/searchServices" `
    -ResourceGroupName $RGName `
    -ResourceName "$ResourcePrefix-as" `
    -ApiVersion 2015-08-19

# Get the primary search API key
$searchApiKey = (Invoke-AzureRmResourceAction `
    -Action listAdminKeys -Force `
    -ResourceId $searchResource.ResourceId `
    -ApiVersion 2015-08-19).PrimaryKey

#AI stuff
$aiResource = Get-AzureRmResource `
    -ResourceType "Microsoft.Insights/Components" `
    -ResourceGroupName $RGName `
    -ResourceName "$ResourcePrefix-ai" `
    -ApiVersion 2014-08-01

$aiInstrumentationKey = $aiResource.Properties.InstrumentationKey


#Redis stuff
$redis = Get-AzureRmRedisCache -Name "$ResourcePrefix-redis" -ResourceGroupName $RGName
$redisKey =  Get-AzureRmRedisCacheKey -Name "$ResourcePrefix-redis" -ResourceGroupName $RGName
$redisKey = $redisKey.PrimaryKey
$redisConnString = $redis.HostName + ":" + $redis.SslPort + ",password=" + $redisKey + ",ssl=True,abortConnect=False"


# Declare and then create the XML files on disk
$setParams = @"
<parameters>
  <setParameter name="IIS Web Application Name" value="$ResourcePrefix-cm" />
  <setParameter name="Application Path" value="$ResourcePrefix-cm__cm-preprod"/>
  <setParameter name="Sitecore Admin New Password" value="$SitecorePwd"/>
  <setParameter name="Core DB User Name" value="$SqlServerLogin"/>
  <setParameter name="Core DB Password" value="$SqlServerPwd"/>
  <setParameter name="Core Admin Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$dbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-core-db;User Id=$SqlServerLogin;Password=$SqlServerPwd" />
  <setParameter name="Master DB User Name" value="$SqlServerLogin"/>
  <setParameter name="Master DB Password" value="$SqlServerPwd"/>
  <setParameter name="Core Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$dbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-core-db;User Id=$SqlServerLogin;Password=$SqlServerPwd" />
  <setParameter name="Master Admin Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$dbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-master-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Web DB User Name" value="$SqlServerLogin"/>
  <setParameter name="Web DB Password" value="$SqlServerPwd"/>
  <setParameter name="Master Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$dbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-master-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Web Admin Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$webDbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-web-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Web Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$webDbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-web-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Cloud Search Connection String" value="serviceUrl=https://$ResourcePrefix-as.search.windows.net;apiVersion=2015-02-28;apiKey=$searchApiKey"/>
  <setParameter name="Application Insights Instrumentation Key" value="$aiInstrumentationKey"/>
  <setParameter name="Application Insights Role" value="CM"/>
  <setParameter name="KeepAlive Url" value="https://$cmHostname/sitecore/service/keepalive.aspx"/>
  <setParameter name="License Xml" value="$licenseEncoded"/>
  <setParameter name="IP Security Client IP" value="0.0.0.0" />
  <setParameter name="IP Security Client IP Mask" value="0.0.0.0" />
</parameters>
"@



$setParamsCD = @"
<parameters>
  <setParameter name="IIS Web Application Name" value="$ResourcePrefix-cd" />
  <setParameter name="Application Path" value="$ResourcePrefix-cd__cd-preprod"/>
  <setParameter name="Sitecore Admin New Password" value="$SitecorePwd"/>
  <setParameter name="Core DB User Name" value="$SqlServerLogin"/>
  <setParameter name="Core DB Password" value="$SqlServerPwd"/>
  <setParameter name="Core Admin Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$dbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-core-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Core Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$dbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-core-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Web DB User Name" value="$SqlServerLogin"/>
  <setParameter name="Web DB Password" value="$SqlServerPwd"/>
  <setParameter name="Web Admin Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$webDbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-web-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Web Connection String" value="Encrypt=True;TrustServerCertificate=False;Data Source=$webDbServerFullyQualified,1433;Initial Catalog=$ResourcePrefix-web-db;User Id=$SqlServerLogin;Password=$SqlServerPwd"/>
  <setParameter name="Cloud Search Connection String" value="serviceUrl=https://$ResourcePrefix-as.search.windows.net;apiVersion=2015-02-28;apiKey=$searchApiKey"/>
  <setParameter name="Application Insights Instrumentation Key" value="$aiInstrumentationKey"/>
  <setParameter name="Application Insights Role" value="CD"/>
  <setParameter name="KeepAlive Url" value="https://$cdHostname/sitecore/service/keepalive.aspx"/>
  <setParameter name="Redis Connection String" value="$redisConnString"/>
  <setParameter name="License Xml" value="$licenseEncoded"/>
</parameters>
"@


$setParamsFilePath = "$scriptDir\CM.parameters.tmp.xml"
$setParamsCdFilePath = "$scriptDir\CD.parameters.tmp.xml"

$setParams | Out-File $setParamsFilePath
$setParamsCD | Out-File $setParamsCdFilePath
Write-Host "XML file created"



