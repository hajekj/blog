---
title: "Running a Remote Desktop Gateway"
date: 2026-01-27T22:20:00+01:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Azure
  - Open Source
tags:
  - Docker
  - Azure AD
  - Remote Desktop
---

I am a heavy user of Remote Desktop. I connect to my work computer from my MacBook for coding, debugging, doing demos, sometimes even gaming. In some cases, I connect even from my phone. For remote access, I am using a combination of either [Apache Guacamole](https://guacamole.apache.org/) in the browser (it's amazing, but there are some frustrating things like copying images to session or some shortcuts - Windows X MacOS), [Cloudflare Access](https://www.cloudflare.com/zero-trust/products/access/) in combination with a native RDP application (either MSTSC or the [Windows app](https://learn.microsoft.com/en-us/windows-app/get-started-connect-devices-desktops-apps?tabs=windows-avd%2Cwindows-w365%2Cwindows-devbox%2Cmacos-rds%2Cmacos-pc&pivots=remote-pc)) or sometimes [cloudflared](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/rdp/rdp-cloudflared-authentication/) in combination with Bastion setup. Recently, I was looking into hosting my own [Remote Desktop Gateway](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remote-desktop-gateway-role) to be able to connect to a machine behind a firewall without the need to be in a VPN (Remote Desktop Gateway masks the RDP traffic as [HTTPS connection](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/rds-roles#remote-desktop-gateway)).

<!-- more --->

In the past I have done many [Remote Desktop Service](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/overview) deployments, some of which are still running to date. The first requirement however is, I don't want to host a Windows Server. Second, I don't want to manage an Active Directory either (it is a [requirement](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/rds-plan-build-anywhere)). Third, I preferably want to deploy this on my existing server and preferrably as a Docker container.

So I started searching around and found out that there are a few (not really well known) implementations of the Remote Desktop Gateway and its protocol:
* [https://github.com/mKenfenheuer/rdpgw.net/](https://github.com/mKenfenheuer/rdpgw.net/) (C#, also has a [working sample](https://github.com/mKenfenheuer/ksol-rdpgw))
* [https://github.com/bolkedebruin/rdpgw](https://github.com/bolkedebruin/rdpgw) (Go)
* [https://github.com/gabriel-sztejnworcel/pyrdgw](https://github.com/gabriel-sztejnworcel/pyrdgw) (Python)

All of these libraries seem to implement it in a similar fashion, however I found the RDPGW in Go the most complete - it also ships as a Docker container, which you can just use - the only issue is that the documentation is somewhat not complete and some things are not really working - yet.

With this implementation, you can [choose between](https://github.com/bolkedebruin/rdpgw?tab=readme-ov-file#authentication) *openid*, *local* (Basic authentication), *ntlm*, *headers* (when behind Cloudflare Access or Azure App Proxy) and *kerberos*. Initially I wanted to go with NTLM authentication, because you can easily configure it from each of the clients as gateway credentials, however I have hit two issues - [Cloudflare doesn't support proxying NTLM authentication](https://developers.cloudflare.com/dns/proxy-status/limitations/#windows-authentication) (and I want it published through [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)) and NGINX doesn't support NTLM either (only as part of [commercial subscription](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#ntlm), there is a [free and OSS module](https://github.com/gabihodoroaga/nginx-ntlm-module) but I haven't tried it, since I want it behind Cloudflare anyways) - I use NGINX as an ingress proxy for all containers and services I host. The next choice was the basic authentication option - and while this would be pretty much suitable for me, [it doesn't work with native MSTSC client](https://github.com/bolkedebruin/rdpgw/blob/master/docs/pam-authentication.md#compatible-clients) (documentation says that [RDCMan](https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman) works, but I didn't manage to get it working either - RDCMan is just a GUI on top of MSTSC anyways), despites even explicitly setting [`gatewaycredentialssource`](https://learn.microsoft.com/en-us/azure/virtual-desktop/rdp-properties#gatewaycredentialssource) to `3`. Next, I configured it for header authentication, which is however [crashing due to a little bug](https://github.com/bolkedebruin/rdpgw/issues/164).

The last option was to go with [OpenID Connect setup](https://github.com/bolkedebruin/rdpgw/blob/master/docs/openid-authentication.md). This method worked across all platforms, and let me go a little bit into how it works: First, you have to visit `https://rdgateway.domain.com/connect?host=xxx.corp.domain.com:3389` and authenticate, which in return will give you a `.rdp` file preauthenticated to the gateway. You then open the file in MSTSC or Windows (on MacOS or iOS) apps, and authenticate to the target computer. The authentication token to the gateway is shortlived, so in case you need to reconnect, you have to download the file again.

The authentication token is stored in `gatewayaccesstoken` property in the `.rdp` file itself (it is a shortlived - 5 minutes - JWT token), which the gateway verifies and let's you connect. It is also refered to as the [*PAA Cookie*](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-tsgu/dff3285e-05de-483b-950b-8c6388e55713). So thanks to this, you can easily connect to your machine from native client, from anywhere without the need for a VPN or running cloudflared.

The only disappointing thing is, that there's no interactive way to continuously obtain the `gatewayaccesstoken` from an IdP in some modern way (so you could skip the entire download a RDP file thing).

I am currently looking into ways to either contribute to the RDGW in Go to fix some of the quirks with the header authentication or leveraging the C# implementation to make my own gateway server in the future.

I also have eyes on [Azure Virtual Desktop hybrid deployment](https://techcommunity.microsoft.com/blog/azurevirtualdesktopblog/announcing-new-hybrid-deployment-options-for-azure-virtual-desktop/4468781). It appears to be in private preview (and the form is already closed). It could remove the need for hosting the gateway completely, since the Arc-enabled machine could be acessibly from AVD directly. I hope to learn more about it soon.