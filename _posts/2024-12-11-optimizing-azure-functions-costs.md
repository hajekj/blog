---
title: Optimizing Azure Functions costs
date: 2024-12-11T17:30:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Azure
tags:
  - Azure Functions
  - PowerShell
---

Recently, I have been focused on optimizing costs of our [company's](https://www.networg.com) Azure costs. Besides consolidating some App Services and creating [reservations](https://learn.microsoft.com/en-us/azure/cost-management-billing/reservations/save-compute-costs-reservations) I noticed some unusual spend with a few Azure Functions resource groups.

I specified resource groups above, because the costs weren't charged to *Functions* meter category nor the *Standard Execution Time* meter. The meter was **LRS Write Operations** for *Storage*.

These functions should definitely fit within the [free grant](https://azure.microsoft.com/en-us/pricing/details/functions/) based on what they are doing - mostly some DevOps related PowerShell code, like maintenance tasks or some tiny pieces of code, [created in the portal](https://learn.microsoft.com/en-us/azure/azure-functions/functions-create-function-app-portal?pivots=programming-language-powershell) - all running on the consumption plan.

Unfortunately, Azure bills resources separately. When you create an Azure Function on consumption plan, it creates a storage account along with a file share defined by `WEBSITE_CONTENTSHARE` and `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` environment variables. When I drilled down to the [storage account metrics](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/microsoft-storage-storageaccounts-metrics), especially the transactions for Azure Files, I could see huge spikes every time the Function triggered. So despites you get a free allocation for Azure Functions, you are still going to be [billed for the storage](https://azure.microsoft.com/en-us/pricing/free-services).

Initially I was blaming [managed dependencies](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell?tabs=portal#dependency-management) in PowerShell for this. But when I started logging all the transactions (and especially the write / create operations), I noticed that the issue is quite general. It aggressively tries to access `site/wwwroot/ApplicationInsightsDiagnostics.json` file which doesn't exist and other various parts of the path. And even more - and all those are *Create* operations. When I was hunting for the cause, I also noticed an issue with reading trace logs in consumptions Functions - [Azure/azure-functions-powershell-worker#1101](https://github.com/Azure/azure-functions-powershell-worker/issues/1101), which slowed me down with troubleshooting.

I started with source controlling the affected Functions into Azure DevOps. I wanted to completely remove the use of managed dependencies, and eventually reliance on Azure Files.

Managed dependencies take the contents of `requirements.psd1` file and automatically download it. It is really smart system, since it can keep it up to date automatically etc. An example is below:

```powershell
@{
    'Microsoft.Graph.Authentication' = '2.*'
    'Microsoft.Graph.Applications' = '2.*'
    'Microsoft.Graph.Groups' = '2.*'
    'Microsoft.Graph.Users' = '2.*'
}
```

I downloaded the content of `wwwroot` by [mounting](https://learn.microsoft.com/en-us/azure/storage/files/storage-how-to-use-files-windows) the Azure File Share via SMB to my machine. Next, I modified the `host.json` to disable `managedDependency` and specified full versions of the packages in `requirements.psd1`, so instead of wildcards (`*`), I placed a full version number there, eg. `2.25.0`.

Next I made a tiny script, which can be run by a user locally or the agent "building" the code, `install-dependencies.ps1`:

```powershell
$modules = Import-PowerShellDataFile .\requirements.psd1

foreach ($module in $modules.GetEnumerator()) {
    Write-Host "$($module.Name) $($module.Value)"
    Save-Module -Name $module.Name -RequiredVersion $module.Value -Path .\Modules -Force
}
```

What the code above does is that it looks at all the defined modules and downloads them into the [`./Modules` folder](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell?tabs=portal#function-app-level-modules-folder).

Then the pipeline zips the ready Function and deploys it - via [Run from package](https://learn.microsoft.com/en-us/azure/azure-functions/run-functions-from-deployment-package). Which effectively uploads the zip file into blob storage and stores the SAS URL of the package into `WEBSITE_RUN_FROM_PACKAGE` variable. This is going to make the function read-only, so you won't be able to make any changes to the code in the Azure Portal.

After doing this, the storage was incurring charges (not that much anymore, but still). So I wanted to remove the the dependency on the Azure File Share fully, since there is no reason why these Functions would need persistent storage. Luckily it is [supported](https://learn.microsoft.com/en-us/azure/azure-functions/storage-considerations?tabs=azure-cli#create-an-app-without-azure-files) but doesn't really seem to be too endorsed. I simply removed the `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` and `WEBSITE_CONTENTSHARE` variables and restarted the up. The Azure Files transactions then went to 0. Mission accomplished.

There might be a more elegant solution but I wasn't able to find anything better than getting rid of the File Share completely. There are some discussions/issues - [1](https://dev.to/peterlindholm/the-case-of-the-mysterious-azure-storage-spikes-13n2), [2](https://github.com/Azure/Azure-Functions/issues/1307), [3](https://learn.microsoft.com/en-au/answers/questions/2125320/azure-file-share-attached-to-an-azure-app-serviceg), but none seem to be pointing at ditching the storage account completely for Functions.

It's also important to note that this issue doesn't affected Azure Functions on Windows hosted on the Standard plan, where the file system is shared, but not based on Azure Files (thus you're not getting billed extra for it). So if you want to control your costs, make sure to drill down into all the costs thoroughly.
