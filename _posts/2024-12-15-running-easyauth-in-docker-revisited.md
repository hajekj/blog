---
title: Running EasyAuth in Docker revisited
date: 2024-12-15T09:00:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Azure
  - Open Source
tags:
  - EasyAuth
  - Docker
  - SSO
---

Some time ago ([1](https://hajekj.net/2019/01/21/exploring-app-service-authentication-on-linux/), [2](https://hajekj.net/2020/05/01/running-easyauth-locally/)) I wrote about [App Service's Easy Auth](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization) - which is used to easily enable Authnetication and Authorization for App Service, Azure Functions and more. Time has passed and some things have changed. This time, I decided to revisit this topic, to provide up to date information.

<!-- more -->

EasyAuth still [runs in the same model](https://hajekj.net/2019/01/21/exploring-app-service-authentication-on-linux/) - provisioned in an [ambassador pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/ambassador). If you however explore [appsvc/middleware](https://hub.docker.com/r/appsvc/middleware/tags) image on Docker Hub, you will see that it hasn't been updated in over 4 years. The reason is that Microsoft switched to its own container registry located at [mcr.microsoft.com](https://mcr.microsoft.com/).

In there however, you won't be able to find the `appsvc/middleware` image directly, because it is hidden. When you [enable logging in App Service on Linux](https://learn.microsoft.com/en-us/azure/app-service/troubleshoot-diagnostic-logs), you will be able to actually see where is the image being pulled from:

```
2024-12-10T15:21:38.541Z INFO  - Pulling image: mcr.microsoft.com/appsvc/middleware:stage6
```

Since this is publicly accessible, you can then pull the image yourself via:

```
docker pull mcr.microsoft.com/appsvc/middleware:stage6
```

*Note that `stage6` appears to be the current "latest" version of the image as there is no actual `latest` tag published.*

From the logs obtained above, you can also see the startup command used to run the container:

```
2024-12-10T15:31:14.876Z INFO  - docker run -d -p 4877:8181 --name hajekj-nginx-php_0_6238f33a_middleware
  -e WEBSITE_SITE_NAME=hajekj-nginx-php 
  -e WEBSITE_AUTH_ENABLED=True 
  -e WEBSITE_ROLE_INSTANCE_ID=0 
  -e WEBSITE_HOSTNAME=hajekj-nginx-php.azurewebsites.net 
  -e WEBSITE_INSTANCE_ID=04aab412e7a99a6e1b3af86515decd0d8715983cee2eb3ec73de530401a080ef 
  -e HTTP_LOGGING_ENABLED=1
  mcr.microsoft.com/appsvc/middleware:stage5
  /Host.ListenUrl=http://0.0.0.0:8181
  /Host.DestinationHostUrl=http://172.16.0.3:8080
  /Host.UseFileLogging=true
```

You can see that the startup command has changed compared to how it ran previously. One of the cool things you can now make use of is [file-based configuration](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-file-based) which makes the things much easier to manage.

So in order to run this locally, you first should create your config file, eg. `config.json` (use the [docs](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-file-based) to configure this the way you need):

```json
{
  "platform": {
    "enabled": true,
    "runtimeVersion": "~1"
  },
  "globalValidation": {
    "requireAuthentication": true,
    "unauthenticatedClientAction": 0,
    "redirectToProvider": "azureactivedirectory"
  },
  "identityProviders": {
    "azureActiveDirectory": {
      "enabled": true,
      "registration": {
        "openIdIssuer": "https://sts.windows.net/<your tenant id>/v2.0",
        "clientId": "<your app id>>",
        "clientSecretSettingName": "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"
      },
      "login": {
        "loginParameters": [
          "scope=openid profile email offline_access"
        ],
        "disableWWWAuthenticate": false
      },
      "validation": {
        "allowedAudiences": [
          "api://<your app id>>"
        ]
      },
      "isAutoProvisioned": true
    },
    "facebook": {
      "enabled": true
    },
    "gitHub": {
      "enabled": true
    },
    "google": {
      "enabled": true
    },
    "twitter": {
      "enabled": true
    },
    "legacyMicrosoftAccount": {
      "enabled": true
    },
    "apple": {
      "enabled": true
    }
  },
  "login": {
    "tokenStore": {
      "enabled": true,
      "tokenRefreshExtensionHours": 72
    },
    "preserveUrlFragmentsForLogins": false,
    "cookieExpiration": {
      "convention": 0,
      "timeToExpiration": "08:00:00"
    },
    "nonce": {
      "validateNonce": true,
      "nonceExpirationInterval": "00:05:00"
    }
  },
  "httpSettings": {
    "requireHttps": true,
    "routes": {
      "apiPrefix": "/.auth"
    },
    "forwardProxy": {
      "convention": 0
    }
  },
  "legacyProperties": {
    "configVersion": "v2",
    "legacyVersion": "V2"
  }
}
```

Next, you want to create `compose.yml` (or transform it to `docker run ...` command):

```yml
services:
  middleware:
    image: "mcr.microsoft.com/appsvc/middleware:stage6"
    ports:
      - "5050:5050"
    environment:
      - WEBSITE_AUTH_FROM_FILE=1
      - WEBSITE_AUTH_FILE_PATH=/home/config.json
      - HTTP_LOGGING_ENABLED=1
      - Host.DestinationHostUrl=https://<your destination>/
      - Host.AutoHealingMiddlewareEnabled=0
      - Host.ListenUrl=http://0.0.0.0:5050
      - Host.UseConsoleLogging=true
      - Host.UseFileLogging=true
      - Host.RewriteHostHeader=true
      - MICROSOFT_PROVIDER_AUTHENTICATION_SECRET=<your secret>
      - WEBSITE_AUTH_ENCRYPTION_KEY=<encryption key>
      - WEBSITE_AUTH_SIGNING_KEY=<signing key>
    volumes:
      - ./config.json:/home/config.json
```

Simply running `docker compose up` will then get you up and running. For signing and encryption key, generate a random 64 digit long hex number.

## Why would you ever need to run this?

One of the two use cases is local development. While Microsoft provides you with [a somewhat limited](https://learn.microsoft.com/en-us/azure/static-web-apps/add-authentication#add-authentication) emulator for running this locally - for Static Web Apps at least, it is not available for App Service or Functions, and doesn't do any work with tokens whatsoever. So thanks to this, you can have end-to-end developer experience with EasyAuth.

Second use case would be to easily setup your application with pre-authentication. For example, if you want to make an internet-facing [Pi-hole](https://pi-hole.net/) installation, you want to protect the admin page with more than just a password. Running this container in an ambassador pattern with the Pi-hole container will ensure, that the admin UI will require Entra ID preauthentication (alternatively, you could publish it to the internet via [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) - which is free and can also handle Entra out of the box, or use [Entra  application proxy](https://learn.microsoft.com/en-us/entra/identity/app-proxy/overview-what-is-app-proxy), but that requires additional licenses and is not as easy to configure).