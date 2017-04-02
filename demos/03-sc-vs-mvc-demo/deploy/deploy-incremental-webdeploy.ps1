#
# Builds ASP.NET apps, deploys code for the web app onto the prior-deployed Azure infrastructure on Appp Service
#

[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True)]
  [string]$SubscriptionName,
  
  [Parameter(Mandatory=$True)]
  [string]$RGName,
  
  [Parameter(Mandatory=$True)]
  [string]$WebAppName
)

# Determine current working directory:
$invocation = (Get-Variable MyInvocation).Value
$directorypath = Split-Path $invocation.MyCommand.Path
$parentDirectoryPath = (Get-Item $directorypath).Parent.FullName

# Constants:
$webAppPublishingProfileFileName = $directorypath + "\SitecoreDemo.publishsettings"
Write-Output "web publishing profile will be stored to: $webAppPublishingProfileFileName"

# Determine which directory to deploy:
$sourceDirToBuild = $parentDirectoryPath + "\SitecoreMVC"
Write-Output "source directory to build: $sourceDirToBuild"

# Build the web app:
Nuget.exe restore "$parentDirectoryPath\SitecoreMvc.sln"
& "$(Get-Content env:windir)\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe" `
 "$sourceDirToBuild\SitecoreMvc.csproj"  /p:DeployOnBuild=false /p:PublishProfile="SitecoreDemo" /p:VisualStudioVersion=14.0


# Select Subscription:
Get-AzureRmSubscription -SubscriptionName "$SubscriptionName" | Select-AzureRmSubscription
Write-Output "Selected Azure Subscription"

# Fetch publishing profile for web app:
Get-AzureRmWebAppPublishingProfile -Name $WebAppName -OutputFile $webAppPublishingProfileFileName -ResourceGroupName $RGName
Write-Output "Fetched Azure Web App Publishing Profile: SitecoreDemo.publishsettings"

# Parse values from .publishsettings file:
[Xml]$publishsettingsxml = Get-Content $webAppPublishingProfileFileName
$websiteName = $publishsettingsxml.publishData.publishProfile[0].msdeploySite
Write-Output "web site name: $websiteName"

$username = $publishsettingsxml.publishData.publishProfile[0].userName
Write-Output "user name: $username"

$password = $publishsettingsxml.publishData.publishProfile[0].userPWD
Write-Output "password: $password"

$computername = $publishsettingsxml.publishData.publishProfile[0].publishUrl
Write-Output "computer name: $computername"

# Incrementally deploy the web app, without deleting existing files on the target
$msdeploy = "C:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe"

# $msdeploycommand = $("`"{0}`" -verb:sync -enableRule:DoNotDeleteRule -source:contentPath=`"{1}`" -dest:contentPath=`"{2}`",computerName=https://{3}/msdeploy.axd?site={4},userName={5},password={6},authType=Basic "   -f $msdeploy, $sourceDirToBuild, $websiteName, $computername, $websiteName, $username, $password)

$declareParamUnicornPath = "-declareParam:name=unicornPath,kind=XmlFile,scope=`".*\.config`$`",match=`"//sitecore/unicorn/configurations/configuration/targetDataStore/@physicalRootPath`",defaultValue=`"D:\home\site\wwwroot\App_Data\unicorn`""

$packagename = $directorypath + "\SitecoreDemo.zip"
Remove-Item $packagename -ErrorAction SilentlyContinue

$msdeploycommandToCreatePackage = $("`"{0}`" -verb:sync -enableRule:DoNotDeleteRule -source:contentPath=`"{1}`" -dest:package=`"{2}`" {3}"   -f $msdeploy, $sourceDirToBuild, $packagename, $declareParamUnicornPath)

$msdeploycommandToDeployPackage = $("`"{0}`" -verb:sync -enableRule:DoNotDeleteRule -source:package=`"{1}`" -dest:contentPath=`"{2}`",computerName=https://{3}/msdeploy.axd?site={4},userName={5},password={6},authType=Basic"   -f $msdeploy, $packagename, $websiteName, $computername, $websiteName, $username, $password)


Write-Output "MS Deploy command about to be executed to create package: " $msdeploycommandToCreatePackage

cmd.exe /C "`"$msdeploycommandToCreatePackage`"";

Write-Output "MS Deploy command about to be executed to deploy package: " $msdeploycommandToDeployPackage

cmd.exe /C "`"$msdeploycommandToDeployPackage`"";