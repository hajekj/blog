---
title: "Executing custom scripts from PCF"
date: 2025-10-06T20:00:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Power Apps component framework
---

We have hit some cases where we want to enable client extensibility of controls we develop - for example, display a custom dialog to enter metadata before a file is uploaded or to call [token broker](https://hajekj.net/2025/04/28/using-entra-authentication-in-power-apps-pcfs-and-client-scripts/) to retrieve tokens. This can be achieved either through [events in PCF (preview)](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/events) or via calling into a custom script.

<!-- more -->

Before events were available, we utilized a library loaded on the form's load event, and then executed it by finding the right iframe where the script lives and then executing the method passed in through parameters. In some cases, there are multiple "handlers" with specified order.

With events, obtaining a result through an async method becomes much more complicated, since you have to [pass a custom method](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/tutorial-define-event?tabs=after#pass-payload-with-event) to call back with result parameters and wait for the callback to be executed. Something like this:

```typescript
let outputParameter1: string;
let promiseResolve: () => void;
const promise = new Promise((resolve) => {
    promiseResolve = resolve;
});
// Wrap the rest into try {} catch (err) {}
context.events.customEvent1({
    parameter1: "<parameter_1>",
    parameter2: {
        parameter: 2
    },
    callback: (outputParam1: string) => {
        outputParameter1 = outputParam1;
        promiseResolve();
    }
});
// Use Promise.race to implement timeout and prevent hangs
await promise();
console.log(outputParameter1);
```

In the handler script, you would end up doing something like this:

```typescript
namespace Your.Namespace {
    export class Class {
        static async OnLoad(executionContext) {
            const formContext = executionContext.getFormContext();
            const sampleControl1 = formContext.getControl("<control_name>");
            sampleControl1.addEventHandler("customEvent1", async (params) => {
                console.log(params.parameter1);
                const accounts = await Xrm.WebApi.retrieveMultiple("account", "?$top=1");
                params.callback(accounts[0]["name"]);
            });
        }
    }
}
```

You can see that the code above is quite complex, and becomes even more complex for proper error handling, timeouts to prevent hangs etc. I haven't tested what happens when you have multiple event subscribers, but I believe that it would result in even more complex code.

Over time, I discovered a method called `Xrm.Utility.executeFunction` which is undocumented, but allows you to specify a web resource, method to call and parameters to pass. It also handles script's dependencies, translations etc. As a result, you will get a [`Promise`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise) which you can await to get the result. And you don't need to attach the script beforehand.

Calling it is super simple:

```typescript
// Wrap this into try { } catch (err) { }
const result = await Xrm.Utility.executeFunction("webresource.js", "Your.Namespace.Class.Method", ["<parameter_1>", { parameter: 2 }]);
```

Handling the call and returning a result is also easy:

```typescript
namespace Your.Namespace {
    export class Class {
        static async Method(parameter1: string, parameter2: object): Promise<string> {
            console.log(parameter1);
            const accounts = await Xrm.WebApi.retrieveMultiple("account", "?$top=1");
            return accounts[0]["name"];
        }
    }
}
```

The code above will execute the script, but there's a catch. The limit for execution is 10 seconds, if the code runs longer, `executeFunction` will throw an error. So if you need to use this to collect some data from the user - for example via a dialog or have something long running, you will still need to resolve to a similar pattern with `Promise` and callbacks like with events.

Something like this for the caller (you can make a nice wrapper for this):
```typescript
let outputParameter1: string;
let promiseResolve: () => void;
let promiseReject: (reason: any) => void;
const promise = new Promise<void>((resolve, reject) => {
    promiseResolve = resolve;
    promiseReject = reject;
});
const result = await Xrm.Utility.executeFunction("webresource.js", "Your.Namespace.Class.Method", [
    "<parameter_1>",
    { parameter: 2 },
    (outputParam1: string) => {
        outputParameter1 = outputParam1;
        promiseResolve();
    },
    (error: any) => {
        promiseReject(error);
    }
]);
try {
    await promise();
    console.log(outputParameter1);
} catch (error) {
    console.error(error);
}
```

And this for the handler:
```typescript
namespace Your.Namespace {
    export class Class {
        static async Method(parameter1: string, parameter2: object, callback: (outputParam1: string) => void, reject: (error: any) => void): Promise<boolean> {
            (async () => {
                try {
                    console.log(parameter1);
                    const accounts = await Xrm.WebApi.retrieveMultiple("account", "?$top=1");
                    callback(accounts[0]["name"]);
                } catch (error) {
                    reject(error);
                }
            })();
 
            return true;
        }
    }
}
```

This results in much cleaner and more readable code than using the wrappers for events. Have fun!

> Remember that you can however only use `Xrm.*` methods in model-driven apps only, and it won't work in canvas or Power Pages.
