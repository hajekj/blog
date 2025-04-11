---
title: PCF Dependent Libraries Preview
date: 2025-03-28T17:30:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Power Apps component framework
---

Few days ago, Microsoft has [silently published docs](https://www.linkedin.com/posts/jahaj_dependent-libraries-preview-power-apps-activity-7311170929462542336-I3TR/) about a new feature in Power Apps component framework called [Dependent Libraries](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/dependent-libraries). We are going to look under the hood of this preview feature.

<!-- more -->

One of [my many asks](https://github.com/microsoft/powerplatform-build-tools/discussions/679) in PCF was to support shipping custom libraries, which could be shared between PCFs - to improve load times and allow resource re-use. This had been [partially answered](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) over a year ago with platform libraries, which brought support for sharing React and Fluent with the platform's libraries, which however brings challenges on its own (we will look into it in a different post). But what if you wanted to share some other library of your own, or share a different version of Fluent?

While you could ship your own libraries via enabling undocumented `pcfAllowLibraryResources` flag, it wasn't really supported (until now, despites Microsoft does this in their own controls for quite a long time) and it has its own flaws. Since the introduction of Dependent Libraries, I have been given hope, that we might be able to solve our dependency issues with PCFs.

## How do dependent libraries work?

Long story short, you create a "library" control (which doesn't really do anything, except sets the dependencies into `window.*`) and you reference it in your own control, which then accesses the libraries either directly via `window.*` or via [externals](https://webpack.js.org/configuration/externals/) configured in Webpack.

## How to use it?

[Microsoft's docs](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/tutorial-use-dependent-libraries?tabs=after) have quite a good tutorial on how to build a control like this, but I will go into a few things which aren't that clear from the docs, or I believe need some extra clarification.

### Referencing your own libraries

You can reference your libraries in two ways - either by configuring it as a `packaged_library` like shown in the sample or by bundling it in your `bundle.js` in the library control. Each has its own specifics.

#### packaged_library way

If you want to use the `packaged_library` way with some NPM package, it might be more complex, unless the package is providing an [UMD ready](https://www.typescriptlang.org/docs/handbook/declaration-files/templates/global-plugin-d-ts.html#umd) module which might be an issue with some libraries. If it doesn't expose it, you may need to "repack" (or bundle) the module in order to support this.

You can achieve it simply by configuring Webpack like this (this is quick and dirty way, and probably could use some extra work, it's based on my previous exploration of packaged libraries):

`webpack.config.js`:
```javascript
module.exports = {
    entry: './src/index.bundle.ts',

    output: {
        filename: 'fluentui-react.js',
        libraryTarget: 'var',
        library: 'MyCustomFluentUIReactV9',
    },

    externals: {
        react: 'React',
        'react-dom': 'ReactDOM',
    },
};
```

`src/index.bundle.ts`:
```typescript
export * from '@fluentui/react-components';
```

`package.json` (add your own versions):
```json
{
  "dependencies": {
    "@fluentui/react-components": "^9.19.1",
    "react": "^17.0.2",
    "react-dom": "^17.0.2",
    "webpack": "^5.89.0"
  },
  "devDependencies": {
    "webpack-cli": "^5.1.4"
  }
}
```

The code above will result in Fluent UI being available under `window.MyCustomFluentUIReactV9` variable. Don't forget that you have to do the same for React, ReactDOM and eventually other dependencies which aren't marked as externals. You also need to make sure that all your dependency versions match. You obviously don't need to do this at all for any of UMD supported libraries.

The output of the code built above can then be referenced in your `ControlManifest.Input.xml` like shown in docs:

```xml
<resources> 
  <library name="MyCustomFluentUIReactV9" version=">=1" order="1"> 
    <packaged_library path="libs/fluentui-react.js" version="0.0.1" /> 
  </library> 
  <code path="index.ts" order="2"/> 
</resources> 
```

Don't mind the versions above, but **do mind** the names! The `name` property of the library **MUST** be unique in the environment, see [**below**](#versioning-and-namespacing-your-libraries).

#### Bundled way

Alternatively, you can bundle the library directly into `bundle.js`. You simply `npm install` the library into your PCF, import it in `index.ts` and export it:

```typescript
import * as clientLibraries from '@talxis/client-libraries';

// Default PCF scaffold class
// ...

(function () {
   window.TALXISClientLibrariesV2 = clientLibraries;
})();
```

Note that above, I am including the library's major version in the namespace as well. See below for the reason.

#### Versioning and namespacing your libraries

The `window.*` namespace is shared across all controls. There is no isolation whatsoever. This means, that you **MUST** use as unique namespaces as possible. For instance, if you would bring your own React@16, and exposed it as `window.Reactv16` you would override Microsoft's version and thus affect all controls depending on it. Therefor, bringing your own React should be under your own namespace, eg. `window.TALXISReactV16` or something similar.

You probably noticed the `V9`, `V2` or `V16` suffix in the names. This is on purpose (and mandatory), because like mentioned above, there is no isolation between the control code. And the versions in `packaged_library` library (if you decide to use them) will result only in the latest version being given. So if you were to bundle `React@16`, `React@17` and `React@18` under `name="React"` (eg. `window.React`) with respective versions, you would always get `React@18` (this was one of the issues with the undocumented implementation of `packaged_library`).

### Consuming libraries

Consuming libraries is pretty straightforward. You reference the library control as a dependency in `ControlManifest.Input.xml`:

```xml
<resources>
    <dependency type="control" name="hajekj_hajekj.DependentLibraries.DependentLibrary" order="1" />
</resources>
```

Then you enable custom Webpack support and dependencies in `featureconfig.json`:
```json
{
    "pcfResourceDependency": "on",
    "pcfAllowCustomWebpack": "on" 
}
```

Then you create `webpack.config.js`:

```javascript
module.exports = { 
  externals: { 
    "@talxis/client-libraries": "TALXISClientLibrariesV2" 
  }, 
};
```
Here, you can specify all your externals and its respective namespace in `window.*`. This is going to tell Webpack to skip bundling the library, even if you import it `import * as clientLibraries from '@talxis/client-libraries';`, and instead look for it in `window.TALXISClientLibrariesV2` (or whatever you provide).

You can also access it inside the PCF via calling `window.TALXISClientLibrariesV2.something();`. This also works, however it will not provide out of box types inferred from the NPM package (you can see how to do it in [example](#example) below).

## Note on asynchronous library loading

One of the features which I was surprised by was support for [loading the libraries on demand](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/tutorial-use-dependent-libraries?tabs=after#modify-the-dependent-component-to-load-library-on-demand), eg. async dependency loading. I have yet to figure out a use case for this in our projects, but one caveat, which you have to mind when you work with it is, that you should never directly import the library which you are loading on demand, because the control will fail to initialize, you will only get an exception like the constructor cannot be found or something in Power Apps. This happens, because when the `bundle.js` of your PCF gets loaded in the page, it tries to look for the dependency, and since it hasn't loaded, it will crash, and the PCF will never register with the framework, thus won't even render.

One of the interesting things I have found however is, that when you call `const loadedControl = await this.context.utils.loadDependency?.("samples_SampleNamespace.StubLibrary");` the `loadedControl` variable will contain the PCF's class, which you can call yourself. This might be useful, if you want to write libraries of your own, but I don't think this is really supported, so probably best to stay away from it.

## Example

I compiled an example together with a few sample libraries (NPM and local) and put it on GitHub, along with a sample app, which you can use to play around with it. It's really a dirty example.

**[EXAMPLE](https://github.com/NETWORG/sample-pcf-dependent-libraries)**