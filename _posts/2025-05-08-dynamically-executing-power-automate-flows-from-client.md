---
title: Dynamically executing Power Automate flows from client
date: 2025-05-08T14:00:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Power Apps component framework
  - Power Automate
  - Authentication
  - Identity
  - Logic Apps
---

In the [previous post](https://hajekj.net/2025/04/28/using-entra-authentication-in-power-apps-pcfs-and-client-scripts/) we looked into using MSAL to obtain a token from Entra and use it to call an API (Microsoft Graph). This time, we will look into using this setup to authorize a call to Power Automate cloud flow.

<!-- more -->

One of the pre-requisites is to know how-to obtain a token in your client code, where you will be calling the flow from. You can find that in the [previous post](https://hajekj.net/2025/04/28/using-entra-authentication-in-power-apps-pcfs-and-client-scripts/).

# HTTP trigger authorization in Power Automate

When you used a [HTTP trigger]() in Power Automate, you received a long, unique URL containing a [Shared Access Signature (SAS)](https://learn.microsoft.com/en-us/rest/api/storageservices/create-service-sas). Due to the uniqueness of the URL it is safe to say that no one is any likely to guess it. This works well for as long as you don't have a need to pass it to the client-side. When you pass the URL to the client, it can be shared, leaked etc. which you definitely don't want to do. Additionally, when calling it from client-side, you don't get any kind of identity context of who called the Flow, so it is very hard to audit the access.

> If your SAS signed URL leaks, you can easily [regenerate the SAS key](https://learn.microsoft.com/en-us/power-automate/regenerate-sas-key) (this tutorial is funny, because instead of adding a button to easily reset it, Microsoft makes you use F12 Developer Tools).

When you want to have more control over who triggers the flow (and now a default in Power Automate), you can require a valid Entra bearer token to be present. While I have no official confirmation for this, I would say that this functionality is based off of [Logic Apps consumption authorization policies](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app?tabs=azure-portal#enable-oauth-20-with-microsoft-entra-id) (in the flow definition it looks different, but there is a lot of translation happening between moving the cloud flow and hosting it in Logic Apps runtime).

> Logic Apps standard make use of [EasyAuth](https://hajekj.net/tags/#easyauth).

The [configuration in Power Automate](https://learn.microsoft.com/en-us/power-automate/oauth-authentication?tabs=new-designer) is much simpler than with Logic Apps - you can choose between anonymous auth (eg. SAS), any user in your tenant or a set of specific users in your tenant.

When you enable this, the trigger URL will loose the SAS part and get much shorter: `https://prod-227.westeurope.logic.azure.com:443/workflows/c37453c9789f4b809f9b54a7cca587d8/triggers/manual/paths/invoke?api-version=2016-06-01` (in Logic Apps that you can still use both SAS or token to trigger it unless you explicitly [disable use of SAS in Logic Apps](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app?tabs=azure-portal#disable-shared-access-signature-sas-authentication-consumption-only)).

## Obtaining a token for calling the Cloud Flow

As per [docs](https://learn.microsoft.com/en-us/power-automate/oauth-authentication?tabs=new-designer#choose-the-claims-for-your-http-request), the provided token has **one important specific** - the audience claim (`aud`) must be of `https://service.flow.microsoft.com/` value (or a [respective audience for sovereign clouds](https://learn.microsoft.com/en-us/power-automate/oauth-authentication?tabs=new-designer#audience-values)).

You can easily enable your app registration to consume the Power Automate API by adding a delegated permission to your app registration ([step by step tutorial](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-configure-app-access-web-apis#add-permissions-to-access-your-web-api), just choose Power Automate from the list of APIs and the delegated User permission - the token will have the same permissions as user - *I will rant about this a little bit later*).

Once you have the token, you can then call the trigger URL with it and the flow will execute.

# The wrongs about this implementation

Unfortunately this feature is far from being actually useful.

**First** of all, when you trigger the flow with a token, you get neither the token nor the claims in the trigger, so you have no idea who called it (this can be [enabled in Logic Apps consumption](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app?tabs=azure-portal#include-authorization-header-in-request-or-http-webhook-trigger-outputs) and comes by default in Logic Apps standard [via EasyAuth headers](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-user-identities#access-user-claims-in-app-code)). For auditing purposes, you can still kind of rely on Entra sign-in logs, but you will never match a specific token to a trigger.

One way to work around this would be to also pass the token in as an input parameter, but then you would need to verify its signature which will require use of a custom connector, because doing the crypto operations to verify the signature is a quite complex (it might be possible with [custom code in connectors](https://learn.microsoft.com/en-us/connectors/custom-connectors/write-code) or you would need to run your own API like Azure Function). There is one more option which I will get to below.

**Second**, you are unable to provide your custom audience (like with Logic Apps), and if you try, you will end up with the following error:

```json
{
    "error": {
        "code": "MisMatchingOAuthClaims",
        "message": "One or more claims either missing or does not match with the open authentication access control policy."
    }
}
```

This means that even if you managed to access the token in the headers, you won't be able to use it any further - exchange it for something else, because you don't hold the secret for `https://service.flow.microsoft.com/` application (the audience).

To work around this, you could do the following, even though it is a bit obscure: Your client application would request two tokens - one for `https://service.flow.microsoft.com/` audience to pass as the bearer header, and another one for your backend app registration which you own, and thus can get the secret to perform the on-behalf-of flow, to pass in the body (or header) as a parameter.

The first thing you would then do with the received token is to attempt to exchange it for a token for another service (like Microsoft Graph or another backend API) via [On-Behalf-Of flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-on-behalf-of-flow) which effectively validates the token. If this operation succeeds, you can consider the token valid, and can then Base64 decode the payload part (middle part of the token split by `.`) and get the token claims (as JSON) without making a custom connector.

# "Discovery" of the trigger URL

> Please note that this requires [slightly elevated permission](#note-on-required-permissions) - read access to `workflow` table.

When you want to use a HTTP triggered flow, how do you obtain the trigger URL? Do you hardcode it in your code? What if the environment changes? Do you store it in an environment variable? What if you have many flows? It is a lot of work.

You can use the [Power Automate connector](https://learn.microsoft.com/en-us/connectors/flowmanagement/#list-callback-url) to list the callback URL for the flow and populate it into the environment variable or some configuration record to access later.

But you can also retrieve it yourself since we have obtained a token for `https://service.flow.microsoft.com/` and we can call the Power Automate API.

You need to start with resolving the flow's resource ID. When you create a flow in a solution, it has a standard `workflowid` which is the same across all environments. When the flow gets provisioned into Power Automate (and then Logic Apps), it gets its `resourceid` (don't ask me why Microsoft doesn't abstract this away from us), and in order to call the Power Automate API, you need this `resourceid`.

You can get it via calling `https://hajekj.crm4.dynamics.com/api/data/v9.1/workflows(<workflowid>)` (or `Xrm.WebApi.retrieveRecord` or PCF or other ways). The workflow ID is safe to be stored in a variable as it never changes across environments. The response will look like this:

```jsonc
{
  "@odata.context": "https://hajekj.crm4.dynamics.com/api/data/v9.1/$metadata#workflows/$entity",
  "@odata.etag": "W/\"121857354\"",
  "workflowid": "a09e4a0d-3a1c-f011-998a-7c1e5275cfe9",
  // ...
  "resourceid": "e4fbe032-6141-7aa0-91fc-d75d39b05a4f",
  // ...
  "name": "Entra Protected Http Trigger",
  // ...
}
```

You could also try searching via the Flow's name, but names are not unique, so stay away from that.

Next, you need to call the Power Automate API (there is also an emerging `https://2b7805523247473bba66e3681799d6.6f.environment.api.powerplatform.com` API but we will not use it this time). The request to Power Automate API looks like this (it is a `POST` request, [obtaining environment ID](https://hajekj.net/2025/04/17/all-the-ways-of-retrieving-user-id-tenant-id-upn-and-environment-id-in-power-apps/#obtaining-current-environment-id)):

```http
POST https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/<environment_id>/flows/<flow_resource_id>/triggers/manual/listCallbackUrl?api-version=1
Auhtorization: Bearer <token_for_service.flow.microsoft.com>
```

You will then get the response with the trigger URL which you can call (similar to [Logic Apps's `listCallbackUrl`](https://learn.microsoft.com/en-us/rest/api/logic/workflow-triggers/list-callback-url?view=rest-logic-2016-06-01&tabs=HTTP)).

```json
{
    "response": {
        "value": "https://prod-227.westeurope.logic.azure.com:443/workflows/c37453c9789f4b809f9b54a7cca587d8/triggers/manual/paths/invoke?api-version=2016-06-01",
        "method": "GET",
        "basePath": "https://prod-227.westeurope.logic.azure.com/workflows/c37453c9789f4b809f9b54a7cca587d8/triggers/manual/paths/invoke",
        "queries": {
            "api-version": "2016-06-01"
        }
    },
    "httpStatusCode": "OK"
}
```

> If you were using SAS auth (eg. Anyone can trigger the flow) you would get the full URL with SAS token.

## Note on required permissions

In order for the discovery to work, the user doing the discovery would need at least read permission on [`workflow`](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/workflow) entity. After that, you can perform the calls above.

> **Security warning:** If you give user permision to read `workflow` table, they will be able to see the definitions for all workflows. This means that if you are storing any secret in the workflow definition itself, the user will see it.
> So in most cases, use the guide above if you need to populate the URLs via some background job on deploy for example - either via Power Automate connector, package deployer or similar. Note, that the Power Automate API, at the time of writing, doesn't support service principal authentication for retrieving the callback URL, and you will end up with the following error when you try:
> ```json
> {
>     "error": {
>         "code": "ClientScopeAuthorizationFailed",
>         "message": "The x-ms-client-scope header must not be null or empty."
>     }
> }
> ```
> So you have to unfortunately go with delegated authentication in this case.

# Alternative way without using Entra tokens while still authenticated

Is there an easier way? Yes, there is. While triggering the flow via HTTP and getting the response is faster (because it runs synchronously and is not waiting for anything else), the hassle above with tokens and extra steps can be painful.

It also removes the need for "discovery" of the trigger URL.

What you can do instead is to leverage sort of an asynchronous pattern, which would look like following:

1. Create a table called `prefix_myasyncoperations` with some reasonable properties, you may want to have at least a property for the input, result, and some status (Pending, Running, Completed, Failed)
1. Create a flow which triggers on record created within that table, does the job and stores the result in one of the properties
1. From the client, create a record via Web API eg. [`const asyncRunId = await Xrm.WebApi.createRecord("prefix_myasyncoperation", { "prefix_input": "bawawa" });`](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/clientapi/reference/xrm-webapi/createrecord)
1. Poll the ID every X seconds until the flow run finishes (eg. status is either completed or failed) - `const progress = await Xrm.WebApi.retrieveRecord("prefix_myasyncoperation", asyncRunId.id);`

Some caveats to this approach are that usually the asynchronously triggered flow doesn't always start immediatelly, so it can take much longer to run (even if the operation performed is simpe). And second while you get the user's identity - via `createdby` property, you don't get the token to call any other service with user's identity.

You could pass the token as a parameter (like mentioned above), but then the table will contain super sensitive data, since tokens are very sensitive (so make sure to permission the table correctly), and also the tokens expire usually within an hour (or less). So it may not be the best idea to store them and use them in an asynchronous way.

> I always prefer using the user's identity end-to-end (as long as the APIs permit it) for traceability, logs and proper authorization - but if you make sure to for example avoid OData injection (more about that maybe in another article), be my guest.

# Conclusion

To me this OAuth authentication for request triggers in Power Automate seems really half-baked. Sort of as if the person implementing it didn't consider any end-to-end scenario with Entra ID in place - the OBO for example. And while it is better than using SAS signatures - because the tokens need to be [renewed every X minutes](https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes) it could use a lot more care.