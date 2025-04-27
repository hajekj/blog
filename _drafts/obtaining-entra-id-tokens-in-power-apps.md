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

Following my last article about [obtaining tenant ID and UPN in Power Apps](https://hajekj.net/2025/04/17/all-the-ways-of-retrieving-user-id-tenant-id-upn-and-environment-id-in-power-apps/), we are going to look into obtaining Entra ID tokens for calling APIs from your controls (or client scripts). This can be used for various scenarios.

<!-- more-->

When interacting with Entra from client-side, you should make use of [`@azure/msal-browser`](https://www.npmjs.com/package/@azure/msal-browser) package (or eventually `@azure/msal-react` which you can use in React directly). For the purpose of this article, we are going to create two PCFs (two different app registrations) which obtain tokens and call Microsoft Graph (but it could be any other API).

# Single Sign On

* App Registration setup
* Redirect URLs

## Nested App Authentication (NAA)

* Mention

## Switching accounts, guests and multiple tenants

* Comparing tenant ID
* Ignoring other accounts

# Third party cookies

* Docs
* Edge work profile bypass

# Multiple app registrations / controls

# Advanced scenario with Token Broker

# Approach in client scripts

# Sample

https://github.com/NETWORG/sample-pcf-msal