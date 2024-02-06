---
title: Entra ID user and group provisioning with Bitwarden
date: 2023-09-18T09:00:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Azure
tags:
  - Bitwarden
  - Azure AD
  - SCIM
  - Microsoft Graph
  - Azure Functions
  - PowerShell
---

[We](https://networg.com) have been using [Bitwarden](https://bitwarden.com) in our company as a primary password manager. Previously, we were using their [directory connector](https://bitwarden.com/help/directory-sync/) but we decided to switch to [SCIM](https://bitwarden.com/help/about-scim/) synced by Entra ID. This article will guide you through the setup we had to undergo.

<!--more-->

In order to enable SCIM in Bitwarden, you just need an Enterprise subscription (in case you are on an older Enterprise plan, like we were, just contact their support and have the plan upgraded). Then you configure provisioning in Entra ID and you should be good to go to start assigning groups and users to the Enterprise Application, however it is not so simple.

Our setup is following:

We have a lot of users in our tenant and we drive all permissions through group memberships (either security or M365 Groups). Users, which are entitled to access Bitwarden are members of a `License: Bitwarden` group. The intersection of respective groups and the license group is then used to provision users and configure memberships. This works very nicely with the Directory Connector. However with SCIM it won't work this way.

Whenever you assign a group of users to an application in Entra ID, SCIM is going to apply [scoping rules](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/define-conditional-rules-for-provisioning-user-accounts?pivots=app-provisioning) and then provision those users. The scoping rules however don't support checking membership in a group. This means that the membership requirement scope won't apply.

This resulted in literally all users from our tenant being provisioned in Bitwarden. This would have been a billing disaster (not to mention the explaining we would have to do to all the guests who would have recieved the invite e-mail), but luckily, we had the [seat limit](https://bitwarden.com/help/managing-users/#set-a-seat-limit) configured. So only about 12 unintended users were provisioned. We removed them right after it happened.

So since we can't scope users on group membership directly, what can we do about this? We can use [directory extensions](https://learn.microsoft.com/en-us/graph/api/application-post-extensionproperty?view=graph-rest-1.0&tabs=http) in Microsoft Graph to store the entitlement information and then create a scope to filter that property.

Assuming that you have registered the application for SCIM provisioning in your tenant ([docs](https://bitwarden.com/help/azure-ad-scim-integration/)), you can then go ahead and create the extension property via the following PowerShell script:

```powershell
$applicationId = "" # Application ID of the Bitwarden SCIM application
$params = @{
	name = "BitwardenLicense"
	dataType = "Boolean"
	targetObjects = @(
		"User"
	)
}

New-MgApplicationExtensionProperty -ApplicationId $applicationId -BodyParameter $params
```

This script uses the new [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0). You can also use it from [Azure Cloud Shell](https://learn.microsoft.com/en-us/azure/cloud-shell/overview).

The output is going to contain the property name like `extension_78b7ed6e43374407b6d7e376242bc31a_BitwardenLicense`. This is what we are going to use in our scoping filter. If you don't see the attribute in the dropdown, you have to [add it manually to the schema](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/customize-application-attributes#editing-the-list-of-supported-attributes). Simply open the Azure Portal with this [link](https://portal.azure.com/?Microsoft_AAD_Connect_Provisioning_forceSchemaEditorEnabled=true) navigate to the provisioning rules, and under *Advanced* you will be able to see *Edit attribute list for Azure Active Directory* where you will be able to add your newly created extension attribute.

The rest is just a matter of creating a rule with `IS TRUE` operator and you are done.

> **TIP:** Before you configure the SCIM sync, it may be better to change the mapping of `enternalId` property. Bitwarden's docs suggest to map it to `mailNickname` property, but as we all know, it is not immutable and administrator can change this value. Therefor, it is better to map `objectId` to `externalId`, since `objectId` never changes for the directory object.

# Automating attribute assignment

Once we have this filter done, we should also automate the assignment of the extension attribute, so any user which is added to the group will be provisioned to Bitwarden and the users removed will be deprovisioned. We are going to leverage PowerShell for this again in combination with Azure Functions.

Start with creating a new [PowerShell based Azure Function](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell?tabs=portal). We are using Consumption tier for this, since it will be running for free.

Once you create the Function app, navigate to *App Files*, open `requirements.psd1` and  add the `Microsoft.Graph` module, so the file will look like this:

```powershell
# This file enables modules to be automatically managed by the Functions service.
# See https://aka.ms/functionsmanageddependency for additional information.
#
@{
    # For latest supported version, go to 'https://www.powershellgallery.com/packages/Az'. 
    # To use the Az module in your function app, please uncomment the line below.
    # 'Az' = '10.*'
    'Microsoft.Graph' = '2.*'
}
```

Next, go to `profile.ps1` file and comment out the lines which are there (or make the file empty). This is due to the fact that when you enable Managed Identity within Functions, it automatically initialize the `Az` module for you, however, we are not including it in. This would result in an error.

Now, you need to [enable the Managed Identity](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity). You can also do this via your own App Registration, but I find MSI much easier and more secure.

Once you enable MSI, you need to grant the access to Microsoft Graph. You are not able to do this in UI, so PowerShell to the rescue:

```powershell
$MSI = Get-AzureADServicePrincipal -ObjectId "<your_msi_object_id>"
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$PermissionName = "Directory.Read.All" # Do this also for User.ReadWrite.All and AppRoleAssignment.ReadWrite.All, the permissions will be explained later
$GraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$GraphAppId'"
$AppRole = $GraphServicePrincipal.AppRoles | Where-Object { $_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application" }
New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $GraphServicePrincipal.ObjectId -Id $AppRole.Id
```

Now you can create the timer triggered function. You can go with the default 5 minute interval, however if you have many users in your tenant, you may want to have a longer interval. Next we use the following code in the Function:

```powershell
Connect-MgGraph -Identity -NoWelcome

$tobelicensedUsers = Get-MgGroupMember -GroupId "<your_license_group_id>" -All | Foreach-Object { ,$_.Id }
$bitwardenEnabledUsers = Get-MgUser -Filter "<your_extension_property_name> eq true" -All | Foreach-Object { ,$_.Id }
$remove = Compare-Object $tobelicensedUsers $bitwardenEnabledUsers | Where-Object { $_.SideIndicator -eq '=>' } | Foreach-Object { $_.InputObject }
$add = Compare-Object $tobelicensedUsers $bitwardenEnabledUsers | Where-Object { $_.SideIndicator -eq '<=' } | Foreach-Object { $_.InputObject }
$add | Foreach-Object `
{
    $json = '{ "<your_extension_property_name>": true }'
    Invoke-MgGraphRequest -Method PATCH "https://graph.microsoft.com/v1.0/users/$($_)" -Body $json -Debug
}
$remove | Foreach-Object `
{
    $json = '{ "<your_extension_property_name>": null }'
    Invoke-MgGraphRequest -Method PATCH "https://graph.microsoft.com/v1.0/users/$($_)" -Body $json
}
```

This will make sure that all users who have the property and are no longer in the group will be de-provisioned and those who are in the group and don't have the property will be provisioned. Note that we are using `Invoke-MgGraphRequest` since there is no cmdlet for updating the extension property yet.

The last step is to automate group assignment to the Enterprise Application so that the groups and their entitled users will be provisioned automatically into Bitwarden, this can be done via the following PowerShell:

```powershell
Connect-MgGraph -Identity -NoWelcome

$groups = Get-MgGroup -All
# Our groups have a strict naming convention, so we can filter those to be provisioned easily
$pctGroups = $groups | Where-Object { $_.DisplayName -like "PCT*" }
$agtGroups = $groups | Where-Object { $_.DisplayName -like "AGT*" }
$intGroups = $groups | Where-Object { $_.DisplayName -like "INT*" }
$pstGroups = $groups | Where-Object { $_.DisplayName -like "PST*" }
$filteredGroups = $pctGroups + $agtGroups + $intGroups + $pstGroups
$existingAssignments = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId <your_scim_app_id> -All | Where-Object { $_.PrincipalType -eq 'Group' } | Foreach-Object { ,$_.PrincipalId }
$toAssign = $filteredGroups | Where { $existingAssignments -notcontains $_.Id }
$toAssign | ForEach-Object { New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId <your_scim_app_id> -ResourceId <your_scim_app_id> -PrincipalId $_.Id -AppRoleId <role_id_from_scim_app> }
```

You can either put it all into a single function or create multiple functions and have them run independently.

# Conclusion

This is how we worked around Entra ID's provisioning limits with SCIM and moved to Bitwarden's SCIM protocol instead of running the directory connector.
