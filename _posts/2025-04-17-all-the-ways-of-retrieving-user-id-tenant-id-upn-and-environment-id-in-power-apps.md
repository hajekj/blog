---
title: All the ways of retrieving user ID, tenant ID, UPN and environment ID in Power Apps
date: 2025-04-17T12:30:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Power Apps component framework
  - XRM
  - Authentication
toc: true
---

Whether you're trying to handle authentication or doing something else, you might need to obtain the current tenant ID or user's object ID in Entra. There are a few ways of doing this from the client and not all of them are well known (or even possible).

<!-- more -->

The motivation behind this is that people seem to do a lot of unnecessary API calls which then slow down the application and add unnecessary complexity to the code. You should always try to pull the data from memory rather than making an asynchronous API call.

As some of these properties are not documented (or included in types), it may be a challenge to access them.

I am not really happy from the inconsistencies between XRM and PCF APIs. I can imagine some reasons behind it - like it unifies Canvas, Model driven and Power Pages, but that's not really what's behind the scenes. We will take a deeper look into PCFs in Power Pages another time.

Before we get into the specifics, you might ask - what is any of this good for? Well, for example, if you want to call a 3rd party Entra protected API (or even Microsoft Graph) from within your PCF, you need to authenticate. For authentication, you should use [MSAL](https://learn.microsoft.com/en-us/javascript/api/overview/msal-overview?view=msal-js-latest) (or any other OAuth2/OIDC compliant client) and for constructing the correct authority URL (and accessing metadata) you need the tenant ID (like `https://login.microsoftonline.com/<tenant-id>/`). For silent SSO to provide `login_hint` parameter, you need the user principal name. We will go deeper into authentication topic later.

# Obtaining user's ID (systemuserid)

This is probably the most straightfroward operation since this identifier is exposed everywhere. You can use it to resolve the current user via an API call

## XRM

```typescript
const systemuserid = Xrm.Utility.getGlobalContext().userSettings.userId;
// {B71109E2-3BB7-4A62-AAD1-072214FAC31C}
```

## PCF

```typescript
const systemuserid = context.userSettings.userId;
// {B71109E2-3BB7-4A62-AAD1-072214FAC31C}
```

## Web API

Either execute this either via `Xrm.WebApi.execute`, in cookie-authenticated session or with a Bearer token. [WhoAmI reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/whoami?view=dataverse-latest)
```http
GET https://<instance>.crm4.dynamics.com/api/data/v9.1/WhoAmI
```
Response:
```jsonc
{
  "@odata.context": "https://<instance>.crm4.dynamics.com/api/data/v9.1/$metadata#Microsoft.Dynamics.CRM.WhoAmIResponse",
  // ...
  "UserId": "b71109e2-3bb7-4a62-aad1-072214fac31c",
  // ...
}
```

# Obtaining Entra tenant ID

## XRM

```typescript
const tenantId = Xrm.Utility.getGlobalContext().organizationSettings.organizationTenant;
// 67266d43-8de7-494d-9ed8-3d1bd3b3a764
```

## PCF

```typescript
const tenantId = context.orgSettings.tenantId;
// 67266d43-8de7-494d-9ed8-3d1bd3b3a764
```

## Web API

[RetrieveCurrentOrganization reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrievecurrentorganization?view=dataverse-latest)
```http
GET https://<instance>.crm4.dynamics.com/api/data/v9.1/RetrieveCurrentOrganization(AccessType=Microsoft.Dynamics.CRM.EndpointAccessType'Default')
```
Response:
```jsonc
{
  "@odata.context": "https://hajekj.crm4.dynamics.com/api/data/v9.1/$metadata#Microsoft.Dynamics.CRM.RetrieveCurrentOrganizationResponse",
  "Detail": {
    // ...
    "TenantId": "67266d43-8de7-494d-9ed8-3d1bd3b3a764",
    // ...
  }
}
```

# Obtaining Entra user's object ID

## XRM

At the moment, there doesn't seem to be a way to pull user's object ID from XRM directly.

```typescript
// Unsupported way, you can check this value and fallback to the Web API call below for backup
const aadObjectId = window.__preload.aadObjectId;
// d8b828cf-6af7-4673-b11e-7de2dc05236f
```

## PCF

```typescript
const aadObjectId = context.userSettings.aadObjectId;
// d8b828cf-6af7-4673-b11e-7de2dc05236f
```

## Web API

```http
GET https://<instance>.crm4.dynamics.com/api/data/v9.1/systemusers(<systemuserid>)?$select=azureactivedirectoryobjectid
```
Response:
```jsonc
{
  "@odata.context": "https://hajekj.crm4.dynamics.com/api/data/v9.1/$metadata#systemusers(azureactivedirectoryobjectid)/$entity",
  // ...
  "azureactivedirectoryobjectid": "d8b828cf-6af7-4673-b11e-7de2dc05236f"
}
```

# Obtaining Entra user's User Principal Name

You need this for example when doing SSO and want to provide [`login_hint`](https://learn.microsoft.com/en-us/entra/identity-platform/msal-js-sso#with-user-hint) for silent login.

## XRM

Unsprisingly, just like with Entra user's object ID, this is not directly supported. This value contains the correct information even in B2B scenarios (see Web API for more on B2B UPNs).

```typescript
// Unsupported way, you can check this value and fallback to the Web API call below for backup
const loginHint = window.__preload.aadLoginHint;
// jan.hajek@thenetw.org
```

## PCF

Unfortunately, it is not available either, so you have to use the method mentioned above in XRM or call the Web API.

## Web API

You should be using `windowsliveid` which corresponds to the UPN, whereas `internalemailaddress` is user's primary e-mail address. Retrieving both is necessary for B2B guest scenarios, where `windowsliveid` will contain [`#EXT#`](https://learn.microsoft.com/en-us/entra/external-id/user-properties#user-principal-name) which won't work for `loginHint` and you will have to try with `internalemailaddress` (which will work in most cases). With organizations whose UPN doesn't match primary email address (for whatever reason), you will want to use `windowsliveid`.

```http
GET https://<instance>.crm4.dynamics.com/api/data/v9.1/systemusers(<systemuserid>)?$select=internalemailaddress,windowsliveid
```
Response:
```jsonc
{
  "@odata.context": "https://hajekj.crm4.dynamics.com/api/data/v9.1/$metadata#systemusers(internalemailaddress,windowsliveid)/$entity",
  // ...
  "windowsliveid": "jan.hajek@thenetw.org",
  "internalemailaddress": "jan.hajek@thenetw.org"
}
```

# Obtaining current environment ID

This corresponds to the ID you use in calling the [BAP API](https://learn.microsoft.com/en-us/power-platform/admin/powerplatform-api-getting-started) for example.

## XRM

```typescript
const tenantId = Xrm.Utility.getGlobalContext().organizationSettings.bapEnvironmentId;
// 2b780552-3247-473b-ba66-e3681799d66f
```

## PCF

You cannot retrieve this information through PCF's context, use the XRM way.

## Web API

[RetrieveCurrentOrganization reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrievecurrentorganization?view=dataverse-latest)
```http
GET https://<instance>.crm4.dynamics.com/api/data/v9.1/RetrieveCurrentOrganization(AccessType=Microsoft.Dynamics.CRM.EndpointAccessType'Default')
```
Response:
```jsonc
{
  "@odata.context": "https://hajekj.crm4.dynamics.com/api/data/v9.1/$metadata#Microsoft.Dynamics.CRM.RetrieveCurrentOrganizationResponse",
  "Detail": {
    // ...
    "EnvironmentId": "2b780552-3247-473b-ba66-e3681799d66f",
    // ...
  }
}
```

# Have I missed a way?

Let me know! I am curious about any other ways you might use to obtain these values.