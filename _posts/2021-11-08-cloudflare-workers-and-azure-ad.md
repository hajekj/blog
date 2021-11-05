---
title: OpenAPI and Azure Functions Out-of-Process
date: 2021-11-08T09:45:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Azure
  - Cloudflare
tags:
  - Serverless
  - Cloudflare Workers
  - Azure AD
  - Authentication
  - TypeScript
---

Hey Friends! I have been gone for longer than I should, but I am back! This time, with a really cool sample for using [Cloudflare's serverless Workers](https://workers.cloudflare.com/) platform with [Azure Active Directory](https://azure.microsoft.com/en-us/services/active-directory/?cdn=disable)! Let's dive in!

Cloudflare Workers is essentially a distributed serverless platform which runs your code in their [edge locations](https://www.cloudflare.com/network/) around the world. Thanks to it, the latency is super low (I am currently at 5ms). Cloudflare Workers support multiple languages - from JavaScript to anything which can be compiled to WebAssembly. I chose to build this one with TypeScript, but you can choose from [bunch of others](https://developers.cloudflare.com/workers/platform/languages).

# Why using Cloudflare Workers?
Because I can! And I really wanted to try it out from quite a long time. I have used it few times for very simple things like hosting [`microsoft-identity-association.json`](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-configure-publisher-domain#to-verify-a-new-domain-for-your-app) file (more about that [here](https://hajekj.net/2020/11/26/cross-tenant-publisher-verification/)), but never really used it for any API or anything. Also Troy Hunt wrote a really [awesome article](https://www.troyhunt.com/serverless-to-the-max-doing-big-things-for-small-dollars-with-cloudflare-workers-and-azure-functions/) about using Workers for his [Have I Been Pwned](https://haveibeenpwned.com/) service. So thought I would give it a shot. And what would be the purpose of the article if I didn't include some Azure stuff in as well! Obviously, Azure AD authentication was my first pick!

# Runtime - V8 and limits
> For full details, visit [How Workers work](https://developers.cloudflare.com/workers/learning/how-workers-works) on Cloudflare's docs.

Cloudflare is using [V8](https://www.cloudflare.com/learning/serverless/glossary/what-is-chrome-v8/) engine for executing your code - it's the engine which runs JavaScript in your browser (assuming you are using Chroimum-based one like Microsoft Edge).

# Validating tokens

# On-Behalf-Of Flow and caching

# Summary

https://github.com/hajekj/cloudflare-workers-aad