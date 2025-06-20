---
title: Working with Exchange Online distribution groups via REST
date: 2025-06-20T10:00:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Office 365
tags:
  - PowerShell
  - Microsoft Graph
  - Exchange Online
---

For some time, we have been struggling with the way to programmatically manipulate distribution groups in Exchange Online. The only supported way is via [Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-online-powershell?view=exchange-ps) which makes it quite hard to integrate into your code or execute from Power Automate. I dove a little bit deeper into how the module works and figured out a way to do this.

<!-- more -->

Distribution groups are somewhat a special object in Microsoft Graph. You can read them, but you can't manipulate them (eg. add/remove members, rename etc.). This is because they are "Exchange mastered", meaning that the group's master data is stored in Exchange and only some part of it is replicated to Microsoft Graph, but there's no functionality to replicate it back (despites Exchange support for [dual-write](https://techcommunity.microsoft.com/blog/exchange/exchange-online-improvements-to-accelerate-replication-of-changes-to-azure-activ/837218)). I will not discuss whether you should be still using them or switching to M365 groups in this article.

So using [Fiddler](https://www.telerik.com/fiddler) and executing [New-DistributionGroup](https://learn.microsoft.com/en-us/powershell/module/exchange/new-distributiongroup?view=exchange-ps), I discovered that the Exchange Online PowerShell calls the following REST API endpoint: `https://outlook.office365.com/adminapi/beta/<tenantId>/InvokeCommand` with the documented parameters. This allows them to execute [any of the EXO PowerShell commands](https://learn.microsoft.com/en-us/powershell/module/exchange/?view=exchange-ps) and the API acts just like a PowerShell proxy.

So now I had to figure out authentication. I want to use the [client_credentials flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow), since in my case the service is operating by a daemon, however you can use delegated permissions in case the user is interacting with your app or [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-use-vm-token#get-a-token-using-powershell) if you are running in Azure (or Azure Arc). We start by creating a standard [app registration](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) (either single or multi-tenant) or you can make use of [managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview). Then you need to go to *API Permissions* and add *Office 365 Exchange Online* app with application scope `Exchange.ManageAsApp` or simply add the following to your [manifest's `requiredResourceAccess`](https://learn.microsoft.com/en-us/graph/api/resources/requiredresourceaccess?view=graph-rest-1.0):

```json
{
    "resourceAppId": "00000002-0000-0ff1-ce00-000000000000",
    "resourceAccess": [
        {
            "id": "dc50a0fb-09a3-484d-be87-e023b12c6440",
            "type": "Role"
        }
    ]
}
```

And then you need to give the application a role to manage Exchange. I [assigned](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/manage-roles-portal?tabs=admin-center) the application [*Exchange Recipient Administrator* role](https://learn.microsoft.com/en-us/exchange/permissions-exo/permissions-exo#microsoft-365-permissions-in-exchange-online).

The original setup was that we had a PowerShell Azure Function which used the `ExchangeOnlineManagement` module and executed the command, so the code below will be in PowerShell, but you can easily transform it to any language of your choice since those are just REST calls (or ask [Copilot](https://github.com/copilot)).

```powershell
$clientId     = "<client_id>"
$clientSecret = $env:EXO_CLIENT_SECRET # Your client_secret - retrieve it from ENV or Key Vault or somewhere
$tenantId     = "<tenant>.onmicrosoft.com"

$tokenBody = @{
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://outlook.office365.com/.default"
    grant_type    = "client_credentials"
}

try {
    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    $accessToken = $tokenResponse.access_token
}
catch {
    # Handle token retrieval failure (this code applies to Azure Function)
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body = "Failed to acquire token: $($_.Exception.Message)"
    })
    return
}
```

So with this token, you can then execute the `InvokeCommand` endpoint as follows:

```powershell
$groupOwner = "<alias>@<domain>"
$groupName = "<displayName>"
$emailAddress = "<alias>@<domain>"
$members = @("<alias1>@<domain>", "<alias2>@<domain>")
$anchorUpn = "<alias>@<domain>" # This should be a mailbox in the same GEO as the DG you are targeting (for single geo, just use admin user's UPN)

$payload = @{
    CmdletInput = @{
        CmdletName = "New-DistributionGroup"
        Parameters = @{
            RequireSenderAuthenticationEnabled = $false
            MemberJoinRestriction              = "Closed"
            Members                            = $members
            ManagedBy                          = $groupOwner
            ErrorAction                        = "Stop"
            MemberDepartRestriction            = "Closed"
            Name                               = $displayName
            PrimarySmtpAddress                 = $emailAddress
            DisplayName                        = $displayName
        }
    }
} | ConvertTo-Json -Depth 10

$headers = @{
    "Authorization"       = "Bearer $accessToken"
    "X-CmdletName"        = "New-DistributionGroup"
    "X-ResponseFormat"    = "json" # ExchangeOnlineManagement sends `clixml` but you can use `json` to have less hassle with the output
    "X-ClientApplication" = "ExoManagementModule"
    "X-AnchorMailbox"     = $anchorUpn
    "Content-Type"        = "application/json"
    "Accept"              = "application/json"
}

try {
    $webRequest = Invoke-WebRequest -Uri "https://outlook.office365.com/adminapi/beta/$tenantId/InvokeCommand" -Method POST -Headers $headers -Body $payload -ContentType 'application/json' -UseBasicParsing
    $responseJson = $webRequest.Content | ConvertFrom-Json

    # Success, return the command response to the caller as JSON
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $responseJson.value[0]
    })
    return
}
catch {
    # Handle the exception
}
```

This way, you can execute any supported command against EXO without the need of PowerShell and you can call it from Power Automate for example via HTTP actions.

Is this supported? I would say yes and no. Cince the `ExchangeOnlineManagement` module makes use of it (and the module itself IS supported), it shouldn't matter whether you call these endpoints via the PowerShell module or via REST (since that's what the module does anyways). If it breaks, just open Fiddler and adjust the commands accordingly (or use it in case you can't figure out the correct parameters).