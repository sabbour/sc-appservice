#
# deploy Sitecore xM1 webdeploy packages
# Note: Web Deploy 3.6 tooling can be downloaded through Web Platform Installer 5 (if not through Visual Studio itself)
#       after which it can be found in "C:\Program Files\IIS\Microsoft Web Deploy V3"
#

[CmdletBinding()]
Param(
  # Params required for provisioning into the exsiting Resource group:
  [Parameter(Mandatory=$True)]
  [string]$SubscriptionName,
  
  [Parameter(Mandatory=$True)]
  [string]$RGName,

  # Params required to find Key Vault instance in which secrets are stored:
  [Parameter(Mandatory=$True)]
  [string]$KeyVaultName,

  [Parameter(Mandatory=$false)]
  [string]$KeyVaultRGName = $RGName,  # If not specified, it is assumed KV resides in same RG

  # TODO: replace these URL's by valid SAS locations in your environment
  [Parameter(Mandatory=$false)]
  [string]$CMPackageUrl = "https://gbbcadwescwebdeploy.blob.core.windows.net/xm1/Sitecore%208.2%20rev.%20161115_cm.scwdp?st=2017-01-09T19%3A05%3A00Z&se=2017-02-28T19%3A05%3A00Z&sp=rl&sv=2015-12-11&sr=b&sig=DoYJoNUVbfDvIrk95bqUdX1nOYFkMk2GtKex6vlUhbA%3D",

  [Parameter(Mandatory=$false)]
  [string]$CDPackageUrl = "https://gbbcadwescwebdeploy.blob.core.windows.net/xm1/Sitecore%208.2%20rev.%20161115_cd.scwdp?st=2017-01-09T19%3A05%3A00Z&se=2017-02-28T19%3A05%3A00Z&sp=rl&sv=2015-12-11&sr=b&sig=%2Fj9FixO0cAeWwmFsks5TNAAJzBD7ZzvrK4BVyt4q1K4%3D",

  [Parameter(Mandatory=$false)]
  [switch]$LeaveTempFilesOnDisk
)

function ConvertPSObjectToHashtable
{
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process
    {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) { ConvertPSObjectToHashtable $object }
            )

            Write-Output -NoEnumerate $collection
        }
        elseif ($InputObject -is [psobject])
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = ConvertPSObjectToHashtable $property.Value
            }

            $hash
        }
        else
        {
            $InputObject
        }
    }
}

$cm_msdeploy_packageurl_secure = ConvertTo-SecureString $CMPackageUrl -AsPlainText -Force 
$cd_msdeploy_packageurl_secure = ConvertTo-SecureString $CDPackageUrl -AsPlainText -Force 

Select-AzureRmSubscription -SubscriptionName $SubscriptionName
Write-Host "Selected subscription: $SubscriptionName"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path 

# The only way to pass secure parameters, stored in Key Vault is through a parameters file.  
# See: https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-manager-keyvault-parameter
# Create params file temporary for pointing to the secrets in Key Vault (*.tmp.json is excluded in .gitignore):
$azureRmContext = Get-AzureRmContext
$subscriptionId = $azureRmContext.Subscription.SubscriptionId
$keyVaultId = "/subscriptions/$subscriptionId/resourceGroups/$KeyVaultRGName/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
$licenseFileContent = Get-Content -Raw -Encoding UTF8 -Path ".\license.xml" | Out-String;
$paramsFile = @{
    '$schema' = "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
       sqlserver_login = @{
         reference = @{
           keyVault = @{
             id = $keyVaultId
           }
           secretName = 'SqlServerLogin'
         }
       }
      sqlserver_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'SqlServerPassword'
        }
      }
      sitecore_admin_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'SitecoreAdminPassword'
        }
      }
      licenseXml = @{
        value = $licenseFileContent
      }
      web_sqlserver_login = @{
         reference = @{
           keyVault = @{
             id = $keyVaultId
           }
           secretName = 'WebSqlServerLogin'
         }
       }
      web_sqlserver_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'WebSqlServerPassword'
        }
      }
      cm_core_sqldatabase_username = @{
         reference = @{
           keyVault = @{
             id = $keyVaultId
           }
           secretName = 'CMCoreSqlDbUserName'
         }
       }
      cm_core_sqldatabase_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'CMCoreSqlDbPassword'
        }
      }
      cm_master_sqldatabase_username = @{
         reference = @{
           keyVault = @{
             id = $keyVaultId
           }
           secretName = 'CMMasterSqlDbUserName'
         }
       }
      cm_master_sqldatabase_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'CMMasterSqlDbPassword'
        }
      }
       cm_web_sqldatabase_username = @{
         reference = @{
           keyVault = @{
             id = $keyVaultId
           }
           secretName = 'CMWebSqlDbUserName'
         }
       }
      cm_web_sqldatabase_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'CMWebSqlDbPassword'
        }
      }
       cd_core_sqldatabase_username = @{
         reference = @{
           keyVault = @{
             id = $keyVaultId
           }
           secretName = 'CDCoreSqlDbUserName'
         }
       }
      cd_core_sqldatabase_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'CDCoreSqlDbPassword'
        }
      }
       cd_web_sqldatabase_username = @{
         reference = @{
           keyVault = @{
             id = $keyVaultId
           }
           secretName = 'CDWebSqlDbUserName'
         }
       }
      cd_web_sqldatabase_password =  @{
        reference = @{
          keyVault = @{
            id = $keyVaultId
          }
          secretName = 'CDWebSqlDbPassword'
        }
      }
    }
  }


$paramsFilePath = "$scriptDir\xm-asp-sitecore-webdeploy.parameters.tmp.json"
Write-Host "Temp params file to be written to: $paramsFilePath"
$paramsFile | ConvertTo-Json -Depth 5 | Out-File $paramsFilePath

# Fetch output parameters from Sitecore ARM deployment as authoritative source for the rest of web deploy params
$sitecoreDeployment = Get-AzureRmResourceGroupDeployment -ResourceGroupName $RGName -Name sitecore
$sitecoreDeploymentOutput = $sitecoreDeployment.Outputs
$sitecoreDeploymentOutputAsJson =  ConvertTo-Json $sitecoreDeploymentOutput -Depth 5
$sitecoreDeploymentOutputAsHashTable = ConvertPSObjectToHashtable $(ConvertFrom-Json $sitecoreDeploymentOutputAsJson)

# Deploy ARM template
New-AzureRmResourceGroupDeployment -Verbose -Force -ErrorAction Stop `
   -Name "sitecore-webdeploy" `
   -ResourceGroupName $RGName `
   -TemplateFile "$scriptDir/templates/xm-asp-sitecore-webdeploy.template.json" `
   -TemplateParameterFile $paramsFilePath `
   -cm_msdeploy_packageurl $cm_msdeploy_packageurl_secure `
   -cd_msdeploy_packageurl $cd_msdeploy_packageurl_secure `
   -sitecoreProvOutput $sitecoreDeploymentOutputAsHashTable

# Clean up temporary params file:
if($LeaveTempFilesOnDisk -eq $false) {
  # Remove-Item -Path $paramsFilePath
}
