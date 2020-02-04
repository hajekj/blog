---
id: 201
title: Deploying ASP.NET Core along with a WebJob to App Service
date: 2017-02-20T08:00:45+01:00
author: Jan Hajek
layout: post
guid: https://hajekj.net/?p=201
permalink: /2017/02/20/deploying-asp-net-core-along-with-a-webjob-to-app-service/
image: /wp-content/uploads/2017/02/WebJobs-1200x675.png
categories:
  - English
  - Microsoft
  - Microsoft Azure
  - Open Source
tags:
  - ASP.NET Core
  - Azure Web Apps
  - WebJobs
---
<!-- wp:paragraph {"coblocks":[]} -->
<p>Recently I have been working on a project in <a href="https://www.asp.net/core">ASP.NET Core</a> and <a href="http://www.dotvvm.com">DotVVM</a>&nbsp;accompanied by a WebJob using <a href="https://docs.microsoft.com/en-us/azure/app-service-web/websites-dotnet-webjobs-sdk">Azure WebJob SDK</a>. The idea behind publishing was that whenever I push code to the repository (VSTS in my case), App Service would pull the code, build it and deploy it automatically (this is achieved by <a href="https://docs.microsoft.com/en-us/azure/app-service-web/app-service-continuous-deployment">setting up Continuous Deployment</a>). This method works just great for ASP.NET Core application, however when accompanied by a WebJob, things weren't as smooth as I was expecting them to be.</p>
<!-- /wp:paragraph -->

<!-- wp:more {"coblocks":[]} -->
<!--more-->
<!-- /wp:more -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>When you deploy a regular ASP.NET application with a WebJob,&nbsp;a special package is used in the main project (<a href="http://www.nuget.org/packages/Microsoft.Web.WebJobs.Publish/">Microsoft.Web.WebJobs.Publish</a>), which causes the WebJobs contained within the project to be built and put into their respective directories.</p>
<!-- /wp:paragraph -->

<!-- wp:quote {"coblocks":[]} -->
<blockquote class="wp-block-quote"><p>In the main application's .csproj file, <a href="https://github.com/davidebbo-test/WebAppWithWebJobsVS/blob/master/WebAppWithWebJobsVS/WebAppWithWebJobsVS.csproj#L273">special targets are imported</a>&nbsp;which in combination with the <a href="https://github.com/davidebbo-test/WebAppWithWebJobsVS/blob/master/WebAppWithWebJobsVS/Properties/webjobs-list.json">configuration file</a>&nbsp;provide the necessary information for the build process to build the jobs and place them to correct WebJob directories.</p></blockquote>
<!-- /wp:quote -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>However this method isn't compatible with ASP.NET Core at the moment and while there is <a href="https://github.com/Azure/Azure-Functions/issues/98">work in progress</a> on enabling it to work together directly, you have to do it on your own.</p>
<!-- /wp:paragraph -->

<!-- wp:heading {"level":1,"coblocks":[]} -->
<h1>Brief introduction to Git publishing to App Service</h1>
<!-- /wp:heading -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>So what happens on the background when you deploy your code to App Service? When change is triggered and the repository is downloaded, Kudu (the engine behind App Service) tries to figure out what type of project you are deploying. It is done by various methods like checking for presence of .sln files and their content (you can look into it yourself <a href="https://github.com/projectkudu/KuduScript">here</a>). Once the project type is figured out, a build script is assembled from templates (which can be found <a href="https://github.com/projectkudu/KuduScript/tree/master/lib/templates">here</a>). That build script is then run in the downloaded project and results in successful deployment (or fail :)).</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>Sample script, which gets generated for ASP.NET Core&nbsp;project can be found below:</p>
<!-- /wp:paragraph -->

<!-- wp:coblocks/gist {"url":"https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451","file":"202-1.bat","coblocks":[]} -->
<div class="wp-block-coblocks-gist"><script src="https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451.js?file=202-1.bat"></script><noscript><a href="https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451#file-202-1-bat">View this gist on GitHub</a></noscript></div>
<!-- /wp:coblocks/gist -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>Whenever you deploy a project, the generated build script is saved to&nbsp;<em>D:\home\site\deployments\tools&nbsp;</em>as&nbsp;<em>deploy.cmd</em>. From there you can download it and make modifications to it.</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>So like you probably understood from the statement above, the script can be completely customized. In order to do so, you have to let Kudu know that you will be using a custom deployment script by creating a file in the project root called&nbsp;<em>.deployment</em> and putting the following content into it (much more information about deployment scripts can be found in <a href="https://github.com/projectkudu/kudu/wiki/Custom-Deployment-Script">Kudu's docs</a>):</p>
<!-- /wp:paragraph -->

<!-- wp:coblocks/gist {"url":"https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451","file":"202-2.ini","coblocks":[]} -->
<div class="wp-block-coblocks-gist"><script src="https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451.js?file=202-2.ini"></script><noscript><a href="https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451#file-202-2-ini">View this gist on GitHub</a></noscript></div>
<!-- /wp:coblocks/gist -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>Once done, you also need to create the&nbsp;<em>deploy.cmd</em> file in the root (or specify its path). You can start with copying the contents of the pregenerated file (<em>D:\home\site\deployments\tools\deploy.cmd</em>). After that, you have to change it, so that the WebJob project gets built and put into correct folder. It is very simple and quite common sense:</p>
<!-- /wp:paragraph -->

<!-- wp:coblocks/gist {"url":"https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451","file":"202-3.bat","coblocks":[]} -->
<div class="wp-block-coblocks-gist"><script src="https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451.js?file=202-3.bat"></script><noscript><a href="https://gist.github.com/hajekj/17ab3a7a18b1ad545ff000252dc35451#file-202-3-bat">View this gist on GitHub</a></noscript></div>
<!-- /wp:coblocks/gist -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>You just put this piece of code to your <em>deploy.cmd</em>, right after section&nbsp;<em>2.1 Build and publish</em>, change the paths, names and done. Next&nbsp;you can do that for every other WebJob&nbsp;you have in your project.</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>The output path&nbsp;<em>%DEPLOYMENT_TEMP%\App_Data\Jobs\Continuous\</em> applies to all cases when you are using the WebJobs SDK. If you need to deploy a triggered job, you would be using&nbsp;<em>Triggered</em> directory instead of&nbsp;<em>Continuous</em> (more info can be found in the <a href="https://github.com/projectkudu/kudu/wiki/WebJobs">docs</a>).</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph {"coblocks":[]} -->
<p>I also found it quite handy to include&nbsp;<em>run.cmd</em> script with my WebJob to make sure that the correct executable is used when the job is run or triggered instead of relying on <em>.exe</em> detection.</p>
<!-- /wp:paragraph -->