---
title: Hosting PHP in Azure Container Apps
date: 2023-12-15T10:00:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Azure
  - Open Source
tags:
  - Azure Container Apps
  - Docker
  - PHP
  - MySQL
  - Shared Hosting
---

This is a continuation of my endeavor to host a few of my side projects. In the [previous post](https://hajekj.net/2018/07/02/hosting-small-sites-in-microsoft-azure/) from 2018, I explained how I moved from a local webhost to an Azure VM. This post follows-up on that and explores other options for easy PHP hosting in Azure.

> You can skip the few top paragraphs if you are not interested in the background.

After being in Azure VM with my site for 3 years, I decided to move it back to WEDOS (less maintenance required) - over time, they enabled Let's Encrypt certificates for free, so I was no longer needing Cloudflare for that. Last week, they [released a new blog post](https://blog.wedos.com/cs/wedos-2024-rostouci-naklady-zmena-cen-co-za-to-ziskate) about increasing prices - ~US$0.45 raise per month, which was perfectly fine, however, to my surprise they also announced a "domain fee" of ~US$44 per month for not using their DNS servers while pointing to their hosting. This kind of enraged me. I understand the need for raising prices, but such a fee is completely unacceptable in my opinion.

To give a little context, WEDOS created a new service called [WEDOS Global](https://www.wedos.com/global/) which appears to do compete with Cloudflare - DDOS protection, CDN, DNS and more in the future. And I suppose they are trying to push more people into the service so they can have higher MAU - I really hate such practices and prefer to have a choice what and how to configure my things - and one thing is for sure - I am sticking with Cloudflare for DNS. I e-mailed WEDOS, and got a reply from their CEO - Josef Grill, explaining that the reasoning behind it is DDOS attacks on their infrastructure and that with 3rd party DNS setup, they cannot [fight the attacks](https://blog.wedos.com/cs/otestovali-jsme-na-sobe-novou-ochranu-proti-l7-ddos-utokum) efficiently. To that, I replied that while I am using my DNS pointing to their hosting, the [records point to their hosting via their DNS via CNAME](https://www.dnswatch.info/dns/dnslookup?la=en&host=www.d1mtg.net&type=A&submit=Resolve), so technically, their DNS is still being used - except for A record, which I am willing to happily host at Cloudflare Pages since it is just redirect to www. Unfortunately, I haven't got a reply to that message, yet.

> Also at [NETWORG](https://networg.com) we are using WEDOS for a few of our customers and they would be affected the same way.

So I started scratching my head a little and looking at other options for hosting the site, in case they would force me to start paying the extra cost. I am always trying to aim for PaaS-like services where I don't have to bother with maintenance too much, especially with legacy projects. So I got back to the idea [having my own Docker runtime container](https://hub.docker.com/r/hajekj/hajekjnet-php) with PHP, another container with MySQL and having it run together. During the past years I upgraded from PHP 7.4 to 8.1 (with only a couple of changes), so the container needed a bit of refreshing.

Since I am using `.htaccess`, I decided to stick with Apache, as I don't want to make any big breaking changes which would consume more of my time maintaining the projects. I initially tried to ugprade my original image to PHP 8.1, but it brought more and more errors (package deprecations, requirements and so on). So I decided to start from blank Dockerfile in [hajekj/php-runtime](https://github.com/hajekj/php-runtime). I love the way the App Service runtime containers work, so I took inspiration there.

> Update from MAY2024: I have since archived the image of my own, because it was very complex to maintain them and instead switched to using [serversideup/php](https://github.com/serversideup/docker-php/) which are pre-built images with easy extensibility and awesome documentation. The only caveat with the latest images is that you need to make your own off of theirs if you want to run it in Azure Container Apps or in some managed service ([reference](https://github.com/serversideup/docker-php/issues/360#issuecomment-2113346972)), and configure the container user to be root, since the `s6-overlay-suexec` is going to keep failing, because the containers in Azure start with `no_new_priv` parameter and therefor the `s6-overlay-suexec` fails to configure permissions on the `/run` folder. Currently tracking possible mitigation in [serversideup/docker-php#372](https://github.com/serversideup/docker-php/issues/372).

# Oryx and App Service Images
I started with the familiar repo of [App Service images](https://github.com/Azure-App-Service/ImageBuilder/). For some reason, Microsoft [stopped using Apache](https://techcommunity.microsoft.com/t5/apps-on-azure-blog/configure-nginx-for-php-8-linux-azure-app-service/ba-p/3069373) for PHP 8 in App Service, and just switched everything to NGINX, without [giving people much choice](https://github.com/MicrosoftDocs/azure-docs/issues/87538). Luckily, in the images, there is still an [Apache](https://github.com/microsoft/Oryx/blob/01392f90eeeb9dbeb9c78c14b0ef443ed274abb6/images/runtime/php/template.base.Dockerfile) image, and it is still being built and can be technically used, but probably without any support. So the starting point got much simpler.

The App Service image relies on [Oryx](https://github.com/microsoft/Oryx) which are the underlying builder images used in Kudu - turns out, they are also used for running the containers. The [Oryx PHP image](https://github.com/microsoft/Oryx/blob/01392f90eeeb9dbeb9c78c14b0ef443ed274abb6/images/runtime/php/) consists of couple of layers - the base dependencies, PHP + Apache, extension installation and runtime modifications for Apache. This is then further customized by App Service's Image Builder later.

The Oryx base images are similar to the [docker-library's PHP](https://github.com/docker-library/php/blob/2af934c6dd18d0ccbacb2cd8efb8f0b6f81be5b2/8.1/bullseye/apache/Dockerfile). I didn't want to depend on Microsoft's internal packages, so I went with the community image as the base one. I then added all [the extensions needed](https://github.com/hajekj/php-runtime/blob/9fc4f6c4286f5ee8d369ac22d2aa94c1f719a0f8/Dockerfile#L24) and also to match the App Service config. I did a couple of modifications in the config - like support for [`RemoteIPHeader`](https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html) to resolve `X-Forwarded-For` correctly from reverse proxies and some other configs done in Oryx and Image Builder. I [removed dependency on Oryx's startup script](https://github.com/hajekj/php-runtime/blob/master/init_container.sh#L63) and replaced it with the pre-generated script.

After couple of attempts and toying with the dependency install and layers, I ended up with a decent PHP 8.1 image.

The next question was, where to host it when needed for cheap?

> **Short note on PHP-FPM**
>
> I managed to have the [previous image of PHP 7.4](https://github.com/hajekj/php-runtime/blob/5a9c0e822a04a2105f6b3dd3875574721619972c/Dockerfile) run in the PHP-FPM mode, which is much more efficient than spawning processes via Apache's mod_php, which is even [discouraged to use by Apache](https://cwiki.apache.org/confluence/display/httpd/PHP). So if I were to switch to the new hosting, I will probably upgrade the image to use FPM as well, for performance.

# Hosting the image
I could go with a custom VM again - either in Azure, DigitalOcean or others - but I wanted to just stop having to care about the underlying VM - Let's Encrypt certificates, updates, security etc. My project is the standard LAMP stack - PHP + MySQL, so I needed a database as well. I could go with Azure Database for MySQL but the cost of the cheapest one is US$6.32 per month, which costs more than the entire WEDOS hosting (yes, I am trying to get the cheapest variant).

After some research, I discovered [Fly.io](https://fly.io/) which allows you to host Docker containers. They have quite a powerful free tier with up to 3x shared CPU and 256MB RAM machines, 3x 1GB persistent volume storage and 160GB bandwidth. I did some experiments there and just couldn't get the container to run and serve content, and after half a day of trying to get it to work - I gave up. I am sure it is possible, but I just didn't want to spend more time on it. I also got a little spooked about their [shared volumes redundancy](https://fly.io/docs/reference/volumes/#volume-redundancy) - they don't seem to run in some high-availability or redundancy, which is quite crucial for things hosted this way (may it be the PHP code, or the database).

After that, I got to look at [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview). I have been so focused on Functions, App Service and such offerings, that Container Apps kind of slipped through. Container Apps are the serverless way of hosting Docker containers - in a consumption plan, with a huge [free tier](https://azure.microsoft.com/en-us/pricing/details/container-apps/) - or at least enough for hobby apps and side projects.

# Azure Container Apps
You simply tell it to run your container, mount some volumes, in how many instances and you are good to go! You can then easily configure things like [custom domains](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates?pivots=azure-portal), eventually [authentication via Easy Auth](https://learn.microsoft.com/en-us/azure/container-apps/authentication), and much more! So having my PHP container running there, with an Azure Files mounted volume for the code, logs, PHP sessions and such, I started lookin into the ways to run a database there.

You can also connect to the containers via a shell, which is quite handy for debugging and such. You can manage the storage by [mounting the Azure File Share](https://learn.microsoft.com/en-us/azure/storage/files/storage-how-to-use-files-windows) to your machine.

# MySQL in Azure Container Apps
I require a standard MySQL compatible database to which I can connect either with `mysqli` or `pdo_mysql`. Container Apps offer a way to add [add-ons](https://learn.microsoft.com/en-us/azure/container-apps/services) to your containers, which basically means spinning up another container app and connecting it with your container - and you can spin up a MariaDB instance. Unfortunately - you don't have any control over the scale, size or the storage. Microsoft says that the [storage is persistent](https://learn.microsoft.com/en-us/azure/container-apps/services#features) and should survive across restarts, but they don't give any [guarantees](https://learn.microsoft.com/en-us/azure/container-apps/services#limitations) since it is to be used for development purporses only.

So spin up a MySQL as a container app, shall we? [MySQL container](https://hub.docker.com/_/mysql) is available and since I previously used it, I am going to stick with it. You simply pass in the `MYSQL_ROOT_PASSWORD` environment variable, mount the Azure Files volume to `/var/lib/mysql` for data persistence and you should be good to go, except the container won't start and will keep crashing.

When you examine the logs, you will see a lot of errors like these:

```
[ERROR] [MY-012960] [InnoDB] Cannot create redo log files because data files are corrupt or the database was not shut down cleanly after creating the data files.
[ERROR] [MY-012930] [InnoDB] Plugin initialization aborted with error Generic error.
[ERROR] [MY-010334] [Server] Failed to initialize DD Storage Engine
[ERROR] [MY-010020] [Server] Data Dictionary initialization failed.
```

While it looks really scary, it simply means that the MySQL failed to initialize. Where is the problem? It's the Azure Files mount permissions. The MySQL container runs as `mysql` user, but the Azure Files mount is owned by `root` user. The container cannot write to the mount, so it fails to run.

I managed to find some hints in [Stack Overflow](https://stackoverflow.com/questions/71283063/mysql-database-in-azure-cluster-using-azure-files-as-pv-wont-start) where they basically say, that you need to mount the File Share with a few specific parameters. Luckily, providing custom `mountOptions` is [already supported](https://github.com/microsoft/azure-container-apps/issues/520) (yet not exposed in the UI) in Container Apps.

I provided the following configuration to `mountOptions`:

```json
"mountOptions": "dir_mode=0777,file_mode=0777,uid=999,gid=999,mfsymlinks,cache=strict,nobrl"
```

Which resulted in the container to boot and run the database. Also verified by connecting to it via Adminer. Attempting to test the data persistence, I have hit another issue - when restarting the container, or deploying a new revision, the container won't start. In logs, you will end up with something like this:

```
[ERROR] [MY-012592] [InnoDB] Operating system error number 2 in a file operation.
[ERROR] [MY-012593] [InnoDB] The error means the system cannot find the path specified.
[ERROR] [MY-012594] [InnoDB] If you are installing InnoDB, remember that you must create directories yourself, InnoDB does not create them.
[ERROR] [MY-012646] [InnoDB] File ./ibtmp1: 'create' returned OS error 71. Cannot continue operation
```

This means that the files are locked and used by another container. This is because when deploying a revision, Microsoft only shuts the previous container down once the new one has booted correctly, which doesn't happen. The solution is to switch the [revision mode](https://learn.microsoft.com/en-us/azure/container-apps/revisions#revision-modes) to multiple, where you de-activate the previous revision, activate the new one and it will run just fine. If you restart manually, the platforms also spins up a container side-by-side and then shuts down the previous one, if the new one starts correctly, which never happens, so you have to create a new revision and repeat the step with de-activating the previous one. Quite complicated, but does the job quite well.

# Backups

Thinking about backups - there are a few options - I never rely on just provider's backups because when the provider looses them, you are ... So what I do is that I run a GitHub action which backs up the entire storage to a private GitHub (or Azure DevOps) repo every night, along with a plaintext SQL export of every database. The site content barely changes and is just PHP files. The databases grows at a steady right, so nothing too critical either.

With Azure Files, you can run Azure Backup on top of the shares and create snapshots for resiliency, but with my previous database experience, I would still recommend exporting the database so in-case it all burns down, you can easily restore it somewhere else and keep going.

# Conclusion

Whether this is the next way of hosting - I don't know, at least not yet, since I haven't received any official notice from WEDOS regarding the newly introduced monthly fee for not using their DNS. But I am ready to move the project within a few hours at any time, and run it for the same, or maybe even cheaper price.
