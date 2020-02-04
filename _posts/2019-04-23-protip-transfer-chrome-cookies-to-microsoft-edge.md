---
id: 1063
title: 'Protip: Transfer Chrome cookies to Microsoft Edge'
date: 2019-04-23T09:00:27+02:00
author: Jan Hajek
layout: post
guid: https://hajekj.net/?p=1063
permalink: /2019/04/23/protip-transfer-chrome-cookies-to-microsoft-edge/
categories:
  - English
  - Microsoft
tags:
  - Google Chrome
  - Microsoft Edge
---
<p>As you might have heard, Microsoft has released a preview version of Microsoft Edge powered by Chromium. If you were using Chrome before and want to make a seamless switch without having to re-log to all your favorite sites, read on!</p>

<!--more-->

<p>First off, you need to locate your Chrome's app data, which are located over here<em>C:\Users\hajek\AppData\Local\Google\Chrome\User Data\Default</em>. You can just use the line below to open the same location in your Explorer:</p>

<pre class="wp-block-code"><code>%LOCALAPPDATA%\Google\Chrome\User Data\Default</code></pre>

<p>In there, you want to find a file called <em>Cookies</em>. Now you need to copy and paste that file to the Edge app data, which are located at <em>C:\Users\hajek\AppData\Local\Microsoft\Edge SxS\User Data\Default</em> for me (Edge Canary) or <em>Dev</em> or <em>Beta</em>, depending which channel you are on:</p>

<pre class="wp-block-code"><code>%LOCALAPPDATA%\Microsoft\Edge SxS\User Data\Default</code></pre>

<p>Same works for other profiles you may have in the browser - located at <em>..\Google\Chrome\User Data\Profile X\</em> where X is the number of the profile.</p>

<p>This should make your switch easier. I strongly suggest however copying only the <em>Cookies</em> file and leaving the rest to the import process of Edge, because some of the data may result in loss of functionality, corruption etc.</p>