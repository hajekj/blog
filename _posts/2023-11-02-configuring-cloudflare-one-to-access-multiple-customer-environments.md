---
title: Configuring Cloudflare One to access multiple customer environments
date: 2023-11-02T13:15:00+02:00
author: Jan Hajek
categories:
  - Cloudflare
  - Microsoft
tags:
  - Cloudflare One
  - Azure AD
  - Single Sign On
  - Networking
  - VPN
---

In our company, we have been heavily utilising [SoftEther VPN](https://www.softether.org/) which is a truly amazing, and unique project. Recently, we started shifting towards a more modern approach to VPN - [Cloudflare One](https://www.cloudflare.com/cloudflare-one/), which offers zero-trust access, direct integration with Azure AD and more.

<!--more-->

# Current situation and our needs
In our company, we have multiple needs - reach our office networks for two cases - RDP into our workstations for remote work, and access customer's services which have our office IP address whitelisted (I will not discuss this practice, but it's what it is). Second need is to be able to access customer's network. We have multiple customers, and each of them has their own VPN solution, many of which are incompatible with one another, and the VPN software is sometimes really hard to deal with (obscure drivers, networking configuration etc.). Some of us, and other companies make use of jump-boxes, basically a shared, dedicated virtual machine, which contains the VPN software to connect so it doesn't interfere with the network.

One of the needs is also to be able to properly authenticate and authorize the user accessing the VPN (based on group membership, so it works with JIT), audit the access and be able to revoke it. Ideally from a single place - Azure AD.

How we approach customer networks is simple - we usually get a virtual machine in the network, and install the [SoftEther bridge](https://www.softether.org/4-docs/1-manual/5._SoftEther_VPN_Bridge_Manual) which we then connect to our VPN server as a hub (so no need for exposing ports on customer side), and then configure authorization. The authentication in SoftEther is handled via our [Radius365](https://radius365.edulog.in) service ([FreeRADIUS](https://freeradius.org/) deployment with custom API handling the incoming attributes and returning the user and password), which allows us to authenticate with user principal name, configure a separate VPN password, and handles authorization based on group memberships. The service itself is a great thing, but it has certain security downsides - like storing passwords in plaintext, or to be more specific reversibly encrypted, due to the way RADIUS as a protocol works.

In special cases, we have our customers access their network via our VPN server as well, Radius365 supports B2B identities (in Cloudflare One, we are using B2B access in Azure AD).

This has been working reliably for years.

# Moving to Cloudflare One
We started evaluating Cloudflare One about half a year ago. Previously, we played with it when it got released, but never got to deploy it.

Cloudflare One is free for 50 users, which is amazing for small companies. In its [free tier](https://www.cloudflare.com/plans/zero-trust-services/), it has almost all features, except for long-term log retention (24 hours only) and community support.

## Authentication
We started with configuring the authentication - [connecting to Azure AD](https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/azuread). This is super easy - simply create an app registration, configure redirect URL and create a secret. From here, you can also configure conditional access in AAD and move on.

## SCIM Provisioning
To my surprise, Cloudflare One also supports SCIM group provisioning and support for user-deprovisioning. You can [limit the session length](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/configure-warp/warp-sessions/#configure-session-timeout) and effectively force re-authentication of users. Also revoke user's session based on their Azure AD status or group membership change. This is really awesome for added security (in Radius365, this was handled in a similar way).

## Provisioning network access
Connecting networks is easy. You start by installing [Cloudflare Tunnel (cloudflared)](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) on a server in the network (you can also install multiple for high-availability) and provisioning it in the portal. Then you create a [virtual network](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/private-net/cloudflared/tunnel-virtual-networks/) and pointing the tunnel's address space to it.

You can either point a specific subnet, like `10.0.0.0/16` or `192.168.0.0/24` or have all the traffic routed through the tunnel via using `0.0.0.0/0` - this is what we use to connect to our office, to end up with the correct public IP address.

### Tunnel Authorization
Next, you definitely want to configure authorization - specify who can access resources in which tunnel. This is where things got slightly confusing for me. I would expect that you configure the authorization on a virtual network level, but you have to configure the permissions in the gateway's [network policies](https://developers.cloudflare.com/cloudflare-one/policies/gateway/network-policies/) (thanks _cscharff_ for [pointing me](https://community.cloudflare.com/t/virtual-network-permissions/574755) in the right direction).

So we create a block policy for each virtual network, which is like - _reject all access if network is <our virtual network> and user is not member of <aad group id>_. This will ensure, that only users who are members of specific AAD group can access the virtual network. Awesome!

## Accessing workstations in the office
In our office, we are using [Turris Omnia](https://www.turris.com/en/omnia/overview/) as a router. This router can run [LXC containers](https://wiki.turris.cz/en/howto/lxc), so we simply setup the `armhf` version of cloudflared in the Ubuntu container like above and we are good to connect to the office.

Once connecting, we can RDP to the workstation and work remotely (we plan to move to the [native RDP support in Cloudflare](https://blog.cloudflare.com/cloudflare-access-now-supports-rdp/) in future). However, the issue is, that when the machine you are remoted in, connects to a virtual network on its own (to access customer environment), the RDP connection drops!

This is caused by [split tunneling configuration](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/configure-warp/route-traffic/split-tunnels/), where we removed the split tunnel configuration for some of the local ranges like `192.168.*` and `10.*`. However, when Cloudflare WARP connects, it [overrides the routing table](https://superuser.com/questions/1704256/vpn-traffic-routing-and-rdp) of the computer, which locks you out of the RDP session.

Luckily, there's a solution for it - currently in beta - [managed networks](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/configure-warp/managed-networks/) and [device profiles](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/configure-warp/device-profiles/). Managed networks simply identify where the device is, by attempting to open a TLS session to a specific IP:Port combination and comparing the fingerprint of the presented certificate. This way, we can setup the split tunnel for devices sitting in the office and let the RDP session continue even when they connect to a tunnel.

### iOS troubles
The above worked great, until I tried to connect via my iPhone. The iPhone just refused to connect to the office network and [kept reconneting](https://community.cloudflare.com/t/iphone-keeps-reconnecting-and-is-unable-to-connect/575168). I have analysed the logs of iPhone, and found out, that the device does managed network discovery, connects to the office network (from LTE for example), and since the network changes, and does managed network discovery again - since the device is present in the network, it decides that the location has changed and reconnects again. And this keeps repeating.

After a few days, I finally found a working solution for this. It involves blocking the managed network discovery endpoint, when the request is sent from within the container running cloudflared. This could be done by configuring a firewall rule (which had no effect for me in Turris), so I installed a [HAProxy](https://www.haproxy.org/) and set the following configuration:

```
global
        maxconn 32000
        ulimit-n 65535
        uid 0
        gid 0
        daemon
        nosplice
defaults
        timeout connect 5000ms
        timeout client 50000ms
        timeout server 50000ms
listen my_http_proxy
        bind :4434 ssl crt /root/cloudflared/example.pem
        # Block managed network discovery from cloudflared
        tcp-request connection reject if { src 10.183.0.3/32 }
        mode http
        http-request return status 200 content-type "text/plain" lf-string "Hello cloudflared!"
```

This allows iPhones (it doesn't happen on Windows, Android, Linux or Mac) to connect to the office network, and office workstations to work as expected. The only limitation is that you are not able to connect to customer networks from iPhone when on office Wi-Fi, but generally the iOS access is not a high priority, and is usually used in emergency situations when without a computer.

# Other honorable mentions
Besides Cloudflare, we were considering [Microsoft Entra Global Secure Access](https://learn.microsoft.com/en-us/entra/global-secure-access/overview-what-is-global-secure-access), but the remote network connection is in private preview at the moment. It is also limited to Windows only clients, which is a big downside and the moment (also doesn't support BYOD Windows scenarios). One more solution which we evaluated was [Shieldoo](https://www.shieldoo.io/), which was created by an ex-Microsoftie. It is [opensource](https://github.com/shieldoo), but doesn't meet our needs like a full remote network access.