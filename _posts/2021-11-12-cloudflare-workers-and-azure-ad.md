---
title: Cloudflare Workers and Azure AD
date: 2021-11-12T15:00:00+02:00
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

Cloudflare Workers is essentially a distributed serverless platform which runs your code in their [edge locations](https://www.cloudflare.com/network/) around the world. Thanks to it, the latency is super low (I am currently at 5 ms). Cloudflare Workers support multiple languages - from JavaScript to anything which can be compiled to WebAssembly. I chose to build this one with TypeScript, but you can choose from [bunch of others](https://developers.cloudflare.com/workers/platform/languages).

# Why using Cloudflare Workers?
Because I can! And I really wanted to try it out from quite a long time. I have used it few times for very simple things like hosting [`microsoft-identity-association.json`](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-configure-publisher-domain#to-verify-a-new-domain-for-your-app) file (more about that [here](https://hajekj.net/2020/11/26/cross-tenant-publisher-verification/)), but never really used it for any API or anything. Also Troy Hunt wrote a really [awesome article](https://www.troyhunt.com/serverless-to-the-max-doing-big-things-for-small-dollars-with-cloudflare-workers-and-azure-functions/) about using Workers for his [Have I Been Pwned](https://haveibeenpwned.com/) service. So thought I would give it a shot. And what would be the purpose of the article if I didn't include some Azure stuff in as well! Obviously, Azure AD authentication was my first pick!

# Runtime - V8 and limits
> For full details, visit [How Workers work](https://developers.cloudflare.com/workers/learning/how-workers-works) on Cloudflare's docs.

Cloudflare is using [V8](https://www.cloudflare.com/learning/serverless/glossary/what-is-chrome-v8/) engine for executing your code - it's the engine which runs JavaScript in your browser (assuming you are using Chroimum-based one like Microsoft Edge).

The important thing to remember about it, is that it isn't Node.js. You don't have the full extent of Node.js core modules available - like `buffer`, `os`, ... This creates the need to use [polyfills](https://webpack.js.org/configuration/resolve/#resolvefallback) which somewhat emulate the functionality. Personally I found modules with dependency on `process` not to work at all.

That's one of the reason why you can't just go ahead with [passport-azure-ad](https://www.npmjs.com/package/passport-azure-ad) module or [MSAL for Node.js](https://www.npmjs.com/package/@azure/msal-node).

I decided to go with building my own sample because the samples which I could find didn't really handle the API flow - eg. validating the Bearer token. The [official tutorial for Auth0](https://developers.cloudflare.com/workers/tutorials/authorize-users-with-auth0) is a regular [authorization code flow](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow) which is not really any useful for an API (there is also an example of [modded Auth0 to work with AAD](https://github.com/bradyjoslin/workers-azuread-example)).

# Validating tokens
The first thing we need to do when we receive a new request, is to validate the token. I found a handy library called [@cfworker/jwt](https://www.npmjs.com/package/@cfworker/jwt) which has native support for Cloudflare Workers. However I had to make a few changes to it.

First the library expect to find the JSON Web Key Set (JWKS, the set of public keys which you validate the token's signature with) at a fixed URL at `<authority>/.well-known/jwks.json`. This is an issue with Azure AD, since JWKS is not available on that URL. In fact, you should obtain the JWKS URL from the `<authority>/.well-known/openid-configuration` endpoint under `jwks_uri` property.

So I implemented [`getOidcMetadata`](https://github.com/hajekj/cloudflare-workers-aad/blob/master/src/utils/jwt/jwks.ts#L13) method which accepts the issuer value from the received token and does a lookup to the [OpenID Connect metadata](https://openid.net/specs/openid-connect-discovery-1_0.html) endpoint. From there, `jwks_uri` is taken and lookup to proper JWKS endpoint is done.

> Loading JWKS and OIDC metadata should be properly cached. In the sample, the JWKS are cached in-memory. You can use [Worker's cache](https://developers.cloudflare.com/workers/runtime-apis/cache) to cache for longer periods of time, more on that later.

The entire validation logic is then hidden in [`isTokenValid`](https://github.com/hajekj/cloudflare-workers-aad/blob/master/src/authentication/isTokenValid.ts) method. Mind the `TODO` part. You should always validate the issuer of the token, so you know which authority (tenant) has it been issued from (this is how you setup multi-tenancy by the way). Last modification I had to make was to the token validation within `@cfworker/jwt` library. I took out [the issuer validation](https://github.com/cfworker/cfworker/blob/main/packages/jwt/src/parse.ts#L53) and moved it to `isTokenValid` so you would be able to get multi-tenant support.

> I tested it with both [V1 and V2](https://docs.microsoft.com/en-us/azure/active-directory/develop/access-tokens#v10-and-v20) tokens and also B2C tokens. It also works with a token issued to a service principal (eg. via `client_credentials` flow). So you should be good to use it in most scenarios.

So now you can validate tokens on the edge!

# On-Behalf-Of Flow and caching
So since we now have a valid token, let's not stop there. We can use my favorite [on-behalf-of](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow) (OBO) flow to retrieve a token for [Microsoft Graph](https://graph.microsoft.com) API and retrieve data from it!

Because you can't run MSAL in Cloudflare Workers (upload was crashing for me, even with all the polyfills added in Webpack), I implemented my own simple method called [`getOboTokenCached`](https://github.com/hajekj/cloudflare-workers-aad/blob/master/src/authentication/getOboTokenCached.ts). It requires the tenant ID (you can get it from the token), the token (from `Authorization` header) and the event context (so we can access [Cache](https://developers.cloudflare.com/workers/runtime-apis/cache)). Calling the OBO endpoint with information above is quite simple, but it adds about 400 ms to each request. Also, why request a new token every time you receive a request? In MSAL, the [Token Cache](https://docs.microsoft.com/en-us/azure/active-directory/develop/msal-acquire-cache-tokens) handles things for you. Here, you have to deal with it yourself. The easiest way for me was to use the built-in [cache](https://developers.cloudflare.com/workers/runtime-apis/cache). However, you can't just pass it the request and response, the cache API (since it is the same one as in browser) allows you to cache only [GET requests](https://developers.cloudflare.com/workers/runtime-apis/cache#invalid-parameters).

So the first thing we have to do is create a proper cache key, which is an equivalent of a GET request. In order to do it, we use the token endpoint's URL `https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token` and suffix it with SHA256 hash of the request's body (contaning the token, client ID and secret). Thanks to this, we get a unique key for the combination above. If client's token changes (due to refresh for example), we bypass the cache and retrieve a new token. Besides, we cache the token response only for 60 seconds (you would use more in production, depending on your token's lifetime). The result is, that you make the request once every 60 seconds.

The last step is to call the Graph API with the received token and return back the response (or do whatever you need to do with it).

# Summary

Fully working sample: **https://github.com/hajekj/cloudflare-workers-aad**

* Make sure to generate your frontend and backend applications
* Backend application needs to have its `Application ID URI` set along with some default scope you plan to use for OBO flow.
* Set `OBO_CLIENT_ID` and `OBO_CLIENT_SECRET` to your application's values (the secret can be set as an encrypted value in the Worker's dashboard)
* You can call the address `https://xxxx.yyyy.workers.dev/graph/me` to try out the OBO flow, any other path will result in just token validation and claims being output