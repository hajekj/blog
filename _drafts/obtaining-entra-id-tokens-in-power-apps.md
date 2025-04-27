---
title: Obtaining Entra ID tokens in Power Apps
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Power Apps component framework
  - XRM
  - Authentication
  - Identity
  - MSAL
  - Single Sign On
  - Microsoft Graph
---

Following my last article about [obtaining tenant ID and UPN in Power Apps](https://hajekj.net/2025/04/17/all-the-ways-of-retrieving-user-id-tenant-id-upn-and-environment-id-in-power-apps/), we are going to look into obtaining Entra ID tokens for calling APIs from your controls (or client scripts). This can be used for various scenarios - calling Microsoft Graph, your own API or even Azure Management one.

<!-- more-->

When interacting with Entra from client-side, you should make use of [`@azure/msal-browser`](https://www.npmjs.com/package/@azure/msal-browser) package (or eventually `@azure/msal-react` which you can use in React directly). For the purpose of this article, we are going to create two PCFs (two different app registrations) which obtain tokens and call Microsoft Graph (but it could be any other API).

I suggest you start with the **[SAMPLE](https://github.com/NETWORG/sample-pcf-msal)** before going further, as this article is going to discuss only some of the specifics of the implementation.

# Setting up the app registrations

In order to start with the PCF, you need to create an [app registration](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app). You should always consider using a separate app registration per PCF, and you shouldn't re-use app registrations across different PCFs. It might seem easier in the beginning, because the SSO is going to be able to share and re-use the tokens, but when your controls start requiring different permissions (scopes), it is best to have it separate.

Once you setup your app registration, you need to enable it for authentication by [adding a redirect URI](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-redirect-uri). If you are building a single-tenant PCF which will be used within your organization, the easiest way might be to simply add your instance's URI, eg. `https://hajekj.crm4.dynamics.com/webresources/cc_hajekj.PCF.Msal1/popup.html` and update it when necessary (an app registration can have many redirect URIs). If you are building a multi-tenant application, this is not a viable option.

What you can do instead is use [wildcard URIs](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url#restrictions-on-wildcards-in-redirect-uris). Basically, it looks like this `https://*.crm4.dynamics.com/webresources/cc_hajekj.PCF.Msal1/popup.html`. You obviously should create one for [each of the supported regions](https://learn.microsoft.com/en-us/power-platform/admin/new-datacenter-regions). Alternatively, if you want to follow the spec and aim for better security, you can build sort of a SSO redirector - this is a pattern used when signing in to Model Driven Apps, Azure App Service and more. Basically, you can build a service, say `https://sso-redirect.contoso.com`, use it as a redirect URI in the app registration, and then when initiating authentication via MSAL, [add your own state](https://learn.microsoft.com/en-us/entra/identity-platform/msal-js-pass-custom-state-authentication-request) containing the actual instance where you want to end up. Once the user gets to the SSO redictor, it looks into the state, verifies that the target is within your registered instances and if it is, redirect the request to its destination - but this is an advanced topic, and you shouldn't need to do this for most scenarios.

In this case, we are shipping an empty HTML page which we use as the destination of the request. There are two reasons for that - origin - in order for MSAL to be able to get the result of the authentication it needs to be on the same origin - whether it is popup or hidden iframe, and performance - if you would redirect to `/main.aspx` or just `/`, the model driven app would start loading and there is a chance that the information passed in the redirect would get lost (MSAL periodically checks the iframe or popup for result), because when the Model Driven App starts loading, it manipulates `window.location`. If you don't want to ship your own "dummy" page, you could use the `/uclient/blank.html` path which is used for Model Driven Apps iframes in script isolation (maybe more on that in another article), but the safest option is with your own page.

# Single Sign On

The target result is that the PCF can easily authenticate the user without any harassment - eg. entering their password, and ideally in a silent way, so that the user won't even notice anything.

## Third party cookies

While the above target sounds really wonderful, due to the requirement of [third party cookies](https://learn.microsoft.com/en-us/entra/identity-platform/reference-third-party-cookies-spas), the seamless experience may not always work in all browsers (this is fairly [live and discussed topic](https://www.msn.com/en-us/news/technology/google-chrome-won-t-phase-out-third-party-cookies-after-all/ar-AA1DyrIG), so this article may not have the latest info).

So what you [should do](https://github.com/AzureAD/microsoft-authentication-library-for-js/blob/ca8cb7dc08b26ba10998a67ce07968f40de700ee/lib/msal-browser/docs/images/msaljs-boot-flow.png) (and the sample does it) is always try the silent auth ([`ssoSilent`](https://github.com/AzureAD/microsoft-authentication-library-for-js/blob/dev/lib/msal-browser/docs/login-user.md#silent-login-with-ssosilent)) and if it fails fallback to another method.

In Model Driven Apps (or generally all embedded scenarios - where you are running inside someone's runtime), you should fallback to [popup method](https://learn.microsoft.com/en-us/entra/identity-platform/scenario-spa-sign-in?tabs=javascript2#choosing-between-a-pop-up-or-redirect-experience). The reason for that is that if you used redirect, the user could loose context of the window, it could result in an unsaved changes prompt etc. And in order to avoid the popup blocker, you should render a button (you can use [`openAlertDialog`](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/clientapi/reference/xrm-navigation/openalertdialog)) which the user clicks and therefor avoids the popup blocker.

Additionally if your users are using Microsoft Edge with work account signed-in (tested on Windows only), it allows the use even with third party cookies blocked, because the authentication broker within Edge adds your users tokens into the header of the SSO request, which replaces the need for relying on third party cookies.

### Nested App Authentication (NAA)

One solution to this would be the use of freshly added [Nested App Authentication](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/authentication/nested-authentication) which was invented to specifically handle these scnearios. It allows the host app to broker tokens for the child apps rendered within. Unfortunately, this is only available in Microsoft Teams and some Office apps only.

## Switching accounts, guests and multiple tenants

* Comparing tenant ID
* Ignoring other accounts

https://github.com/AzureAD/microsoft-authentication-library-for-js/blob/ca8cb7dc08b26ba10998a67ce07968f40de700ee/lib/msal-browser/docs/images/msaljs-boot-flow.png

## Multipel controls on the same page with auth

# Advanced scenario with Token Broker

# React alternative - Microsoft Graph Toolkit (MGT)

# Approach in client scripts

# Sample

https://github.com/NETWORG/sample-pcf-msal