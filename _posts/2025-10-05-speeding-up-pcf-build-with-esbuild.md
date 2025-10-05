---
title: Speeding up PCF build with esbuild
date: 2025-10-05T10:15:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Power Apps component framework
---

Previously I wrote about [optimizations/fixes](https://hajekj.net/2025/03/01/speeding-up-pcf-build/) which you can do to improve PCF build times with the default PCF setup. Since then, Microsoft has added a support for [esbuild](https://esbuild.github.io/) build to [pcf-scripts](https://www.npmjs.com/package/pcf-scripts) to provide an alternative to [webpack](https://webpack.js.org/).

<!-- more -->

Using esbuild to build PCF is however undocumented besides the release notes saying it's an experimental feature and that it has to be enabled via `featureconfig.json` file (we will explore some other options in another article).

So when you create `featureconfig.json` file and add the following flag into it:

```json
{
    "pcfUseESBuild": "on"
}
```

You will also need to add a peer dependency called `esbuild` into your control. Simply do it by `npm i esbuild` or whatever you use as your package manager.

Once you set this up, you can now call `npm run build`. Hopefully your control will build without any issues (I haven't hit any issues in our ~60 control repo - React, Fluent and bunch of other libraries used). Also remember that if it builds, it doesn't mean it will work, so test it thoroughly.

The build will output `bundle.js`, you can even pack it into a solution, but if you run the control (via harness or in Power Apps), it will not run. The issue here is that this feature is either unfinished (yes, it's experimental, but ...) and probably lacks documentation, or more work needs to be done.

The control is missing registration with Power Apps host (or test harness host). This is a few lines of code which is added by a build step of webpack and looks like this:

```javascript
if (window.ComponentFramework && window.ComponentFramework.registerControl) {
    ComponentFramework.registerControl('TALXIS.PCF.CompanyProfileHinting', pcf_tools_652ac3f36e1e4bca82eb3c1dc44e6fad.CompanyProfileHinting);
} else {
    var TALXIS = TALXIS || {};
    TALXIS.PCF = TALXIS.PCF || {};
    TALXIS.PCF.CompanyProfileHinting = pcf_tools_652ac3f36e1e4bca82eb3c1dc44e6fad.CompanyProfileHinting;
    pcf_tools_652ac3f36e1e4bca82eb3c1dc44e6fad = undefined;
}
```

The most important part here is `ComponentFramework.registerControl` call, I haven't found the use for the rest. So simply to end of your `index.ts` file, add the following:

```typescript
// @ts-ignore
if (window.ComponentFramework && window.ComponentFramework.registerControl) {
    // @ts-ignore
    ComponentFramework.registerControl('Your.Full.Namespace.Control', Control);
} else {
    throw new Error("ComponentFramework.registerControl is not present!");
}
```

Now try to build your control and run it either in Power Apps or control harness. **It is going to build way faster** than with webpack, and we're talking tens of seconds saved with some large controls!

Are there any downsides to this? Yes. It is experimental, which means that it is not likely supported by Microsoft. It is undocumented and unfinished. It may change over time. It also doesn't support any customization like webpack ([custom webpack config](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/dependent-libraries#webpackconfigjs), [platform libraries](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) and more), but in our setup, we can do just fine without it. Also note, that [esbuild is still in development](https://esbuild.github.io/faq/#production-readiness) and hasn't hit 1.0 stable version at the time of writing.

I am really looking forward to see where Microsoft takes this (and I hope they allow some extensibility and add feature parity with webpack).