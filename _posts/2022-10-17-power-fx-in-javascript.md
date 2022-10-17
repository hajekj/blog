---
title: Power FX in JavaScript
date: 2022-10-17T07:30:00+02:00
author: Jan Hajek
categories:
  - Microsoft Power Platform
tags:
  - JavaScript
  - .NET
  - Power Apps
  - Power FX
  - Blazor
---

It's been a while since Microsoft [announced and open-sourced](https://powerapps.microsoft.com/en-us/blog/power-fx-open-source-now-available/) its low-code engine called Power FX. The implementation, however, is only available in [.NET](https://github.com/microsoft/power-fx), which doesn't allow it to run on client without backend out of box. Let's take a look at how to achieve that!

Along with the language repo itself, Microsoft also has a [repo with samples](https://github.com/microsoft/power-fx-host-samples), where one of those samples is an interactive playground powered by ASP.NET Core. The experience is also hosted and available directly [from your browser](https://powerfxpublic.azurewebsites.net/), so you don't have to run it.

Over the past few years, Microsoft implemented support for [WebAssembly in ASP.NET](https://learn.microsoft.com/en-us/aspnet/core/blazor/hosting-models?view=aspnetcore-6.0#blazor-webassembly) and it is still continuously [getting a lot of attention](https://visualstudiomagazine.com/articles/2022/09/20/aspnet-core-updates.aspx). Thanks to this, I decided to try to port the Power FX sample to run directly in the browser, without any need of server-side.

The main point of this was to be able to evaluate Power FX directly from JavaScript (an existing React application in my case). Blazor support two-way interop with JavaScript - calling JavaScript from .NET, and [calling .NET from JavaScript](https://learn.microsoft.com/en-us/aspnet/core/blazor/javascript-interoperability/call-dotnet-from-javascript?view=aspnetcore-6.0). We will use the last option.

Once Blazor loads, you can execute `DotNet.invokeMethodAsync` and `DotNet.invokeMethod` from your JavaScript, passing the the required parameters - assembly name, method ID and arguments.

Everything which I implemented was done in [`Program.cs`](https://github.com/NETWORG/power-fx-wasm-demo/blob/main/PowerFxWasm/Program.cs), simply methods annotated with [`JSInvokable` attribute](https://learn.microsoft.com/en-us/dotnet/api/microsoft.jsinterop.jsinvokableattribute?view=aspnetcore-6.0). The methods are almost the same as the ones provided in the [host sample](https://github.com/microsoft/power-fx-host-samples/tree/main/Samples/WebDemo/Controllers).

Once compiled, the application outputs `wwwroot` folder with `_framework` folder in it, which contains all the necessary code. Because I was testing things locally, and didn't want to complicate the build process, I simply launched a [`http-server`](https://www.npmjs.com/package/http-server) from the `wwwroot` folder on `http://localhost:7080`. Next, I had to customize the [React part of the sample](https://github.com/microsoft/power-fx-host-samples/tree/main/Samples/WebDemo/ClientApp). Luckily, the sample is very simple - it is a basic [create-react-app scaffold](https://create-react-app.dev/) with custom page, which displays the interactive formula bar and some debug information.

In the original sample, the communication is done via HTTP calls executed via async `fetch` method. Replacing it was really simple. Instead of the [original](https://github.com/microsoft/power-fx-host-samples/blob/main/Samples/WebDemo/ClientApp/src/PowerFxDemoPage.tsx#LL107C5-L107C89):

```javascript
const result = await sendDataAsync('eval', JSON.stringify({ context, expression }));
```

The code now calls the following:

```javascript
const result = await DotNet.invokeMethodAsync<string>("PowerFxWasm", "EvaluateAsync", context, expression);
```

But before I could call this method, I had to load the Blazor code into the existing page (this could have been done nicer, and will probably change as I move forward with this). Because I was hosting the script locally on a different host (React app runs on port 3000), the scripts and required resources weren't loading due to CORS errors. The first fix was to run the `http-server` with `--cors` parameter. Because it was running technically on a different host, I had to also modify the boot of the Blazor app, to provide it with correct hostnames. Thanks to Github [issue](https://github.com/dotnet/aspnetcore/issues/40348) which was concerning something similar, I managed to get it up and running quite fast:

```javascript
const script = document.createElement('script');
script.type = 'text/javascript';
script.src = `${process.env.REACT_APP_PFX_WASM_HOST}/_framework/blazor.webassembly.js`;
script.setAttribute("autostart", "false");
script.crossOrigin = "anonymous";
script.onload = async () => {
  await Blazor.start({
    loadBootResource: function (type, name, defaultUri, integrity) {
      console.log(`Loading: '${type}', '${name}', '${defaultUri}', '${integrity}'`);
      switch (type) {
        case 'dotnetjs':
          return `${process.env.REACT_APP_PFX_WASM_HOST}/_framework/${name}`;
        default:
          return fetch(`${process.env.REACT_APP_PFX_WASM_HOST}/_framework/${name}`, {
            credentials: 'omit'
          });
      }
    }
  });

  ReactDOM.render(
    <BrowserRouter basename={baseUrl}>
      <PowerFxDemoPage />
    </BrowserRouter>,
    rootElement);
};
document.body.appendChild(script);
```

I created an environment variable called `REACT_APP_PFX_WASM_HOST` which holds the current hostname, which is then used to load the resources correctly. To avoid CORS issues, we are [omitting the credentials](https://developer.mozilla.org/en-US/docs/Web/API/fetch#credentials) from the requests. Same goes for [initial script append](https://developer.mozilla.org/en-US/docs/Web/HTML/Attributes/crossorigin). If you are on the same host, you don't need to do this.

The most important thing however is to await the `Blazor.start` call, so that we continue only once the application is running (more on that [here](https://developer.mozilla.org/en-US/docs/Web/HTML/Attributes/crossorigin)). The only bad thing is that the [types are not fully available](https://github.com/dotnet/aspnetcore/issues/10124) at the time of writing, so you may need to go with [`@ts-ignore`](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-2-6.html#suppress-errors-in-ts-files-using--ts-ignore-comments) in your code. If you don't await the start, you will likely end up with `No .NET call dispatcher has been set` exception.

Once I made all the changes, I was able to run the code, which is [now available on Github](https://github.com/NETWORG/power-fx-wasm-demo). And since it runs in the browser without any backend, [it is available on GitHub Pages](https://networg.github.io/power-fx-wasm-demo/) right from your browser (feel free to check with F12 that no API requests are made 😉).

# Futures

So what next? Right now, this is just a simple Proof of Concept to see if it runs and to compare the performance. There are a few things which need to be configured - like [tree shaking](https://learn.microsoft.com/en-us/aspnet/core/blazor/host-and-deploy/configure-linker?view=aspnetcore-3.1), since the total size of downloaded resources is 20MB, which is really excessive. Once that is handled, I would like to publish this to a CDN as a library, so that anyone can reference it from their code and use Power FX right away. Eventually with some wrappers to simplify the loading process.
