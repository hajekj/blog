---
title: "Protecting 4th+ level domains with Cloudflare for free"
date: 2025-12-22T12:00:00+01:00
author: Jan Hajek
categories:
  - Cloudflare
tags:
---

I have been using Cloudflare since 2011 for DNS, caching and protection. In 2014 Cloudflare [introduced Universal SSL](https://blog.cloudflare.com/introducing-universal-ssl/) helping enable HTTPS for millions of free sites for free. Universal SSL however covers only [3rd level domains](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/#hostname-coverage) (eg. *\*.domain.com* and *domain.com*), and you need to purchase [Advanced Certificate Manager](https://developers.cloudflare.com/ssl/edge-certificates/advanced-certificate-manager/) or upgrade to Business plan to bring your own certificate. I recently discovered a third way to do this, which is completely free (let's hope it stays that way).

<!-- more -->

## My scenario

I accidentally stumbled upon this "feature" yesterday, while I was trying to expose [SSH browser rendering](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-browser-rendering/) for my Raspberry.

Basically, I wanted to expose it under `raspberry.ssh.hajekj.net`, however I ended up with *ERR_SSL_VERSION_OR_CIPHER_MISMATCH* in your browser (or similar), meaning that Cloudflare doesn't have the corresponding certificate.

> I am aware that I could publish it under `ssh-raspberry.hajekj.net` or something, but I just like the 4th level subdomain format better.

## Cloudflare for SaaS to the rescue!

I have been doing a lot of experiments with [Cloudflare for SaaS](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/) as an alternative to [Azure Front Door](https://learn.microsoft.com/en-us/azure/frontdoor/front-door-overview). Since I had it setup on my domain, I just thought, let's try to add the 4th level domain there (since Cloudflare for SaaS creates its own certificates) and see what happens.

I simply added the domain to DNS (via [Published application](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/) from Cloudflare Tunnel, but orange clouded DNS record will work too) and also added the domain to Cloudflare for SaaS (Dashboard > *SSL/TLS* > *Custom Hostnames*), 

After less than a minute, a certificate was issued and the host is published with a 4th level domain secured by Cloudflare's certificate withou ACM (I just hope nobody disables this on Cloudflare's side).

> Some people actually call this a 3rd level domain, so I am just mentioning it down here for visibility.
