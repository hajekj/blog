---
title: "Debugging Dataverse plugins"
date: 2026-03-09T11:20:00+01:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Dataverse
  - Debugging
---

I haven't seen many developers debug plugins in Dataverse. Since Dataverse runs in cloud, you can't just attach debugger to the remote server like you would do in App Service and debug. There are some ways to do it locally like [FakeXrmEasy](https://github.com/DynamicsValue/fake-xrm-easy), but when you want to debug the end to end in real environment, there are some differences and extra steps which you need to take.

<!-- more -->

I have seen way too many people rely on tracing (which brought back some 2008-ish PHP memories), so just thought I would summarize the whole process here.

First off, let's start with [docs](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/debug-plug-in). Tldr; you have to use the [Plugin Registration Tool (PRT)](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/register-plug-in#about-the-plug-in-registration-tool) (`pac tool prt --update` - make sure you have the latest version).

Next, build your plugin in Debug configuration (simple `dotnet build` does the job usually). This process works for both [ILRepack](https://github.com/gluck/il-repack) and also for [plugin packages](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/build-and-package#dependent-assemblies).

> If you are using ILRepack, ensure that you also get correct PDB file. I had to configure output to a different folder in order for proper PDB to be generated. Without correct PDB, you won't be able to debug the code.

Before launching PRT, navigate to `%LOCALAPPDATA%\Microsoft\PowerPlatform\PRT\9.1.0.200\tools` (the version will change in time) and modify `appsettings.json` to have `LegacyPluginProfiler` set to `false` instead of `true`. This step is very important if you want to debug plugin packages, and I haven't found any reason why not to have this enabled for any kind of debugging. After this, launch PRT (`pac tool prt`). This step is described in [French docs](https://learn.microsoft.com/fr-fr/power-apps/developer/data-platform/dependent-assembly-plugins#profileur-de-plug-ins) (and few other languages) but not in any English version.

> You have to disable the LegacyPluginProfile in order to be able to debug plugin packages, if you use the legacy one, you will get `Unexpected Exception in the Plug-in Profiler` error in the API and some more details in the trace log since plugin packages are stored differently than plugin DLLs.

Now import your plugin/package and create the steps and do all the usual stuff. Make sure that [Plugin Trace Log is enabled](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/logging-tracing#enable-trace-logging) (you can do this in PRT too).

Next you can simply follow the [docs](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/tutorial-debug-plug-in?tabs=prt) - *Start Profiling* (you won't see the *Profile Settings* window if you configured PRT correctly). Perform an action to execute the plugin. Then you can just go to *Debug*, select the execution from the history, and then select the assembly.

Finally, you can just [*Attach to Process* from Visual Studio](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/tutorial-debug-plug-in?tabs=prt#debug-your-plug-in) and replay the execution. If you are using VS Code, create [*launch.json*](https://code.visualstudio.com/docs/debugtest/debugging-configuration#_launchjson-attributes) and set the following (note the type is set to `clr` instead of `coreclr` because you are debugging .NET Framework):

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": ".NET Attach",
            "type": "clr",
            "request": "attach"
        }
    ]
}
```

Have fun debugging!