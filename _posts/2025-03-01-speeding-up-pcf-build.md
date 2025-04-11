---
title: Speeding up PCF build
date: 2025-03-01T17:30:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Power Apps component framework
  - Rush
---

At [NETWORG](https://www.networg.com) we have been extensively using [Power Apps component framework](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/overview) which allows us to build custom UI components for Power Apps. Our largest repo with controls (which we continuously update and re-use across customers) has over 47 controls. The repo is setup with [Rush framework](https://rushjs.io/) to streamline dependency management (more on that topic in another article). And the build for each control in CI (Azure DevOps) averages for 1:30 minutes (the build altogether takes 70 minutes).

Our controls make use of various [Fluent UI](https://github.com/microsoft/fluentui) packages (we have our own component libraries implementing and wrapping Fluent components), and during the build, you could observe the following log:

```
npm run build

> pcf-project@1.0.0 build
> pcf-scripts build

[1:54:45 PM] [build] Initializing...
[1:54:45 PM] [build] Validating manifest...
[1:54:45 PM] [build] Validating control...
[1:54:47 PM] [build] Generating manifest types...
[1:54:47 PM] [build] Generating design types...
[1:54:47 PM] [build] Running ESLint...
[1:54:50 PM] [build] Compiling and bundling control...
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-3.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\icons\chunk-0.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-0.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-15.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\icons\chunk-4.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\icons\chunk-1.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\icons\chunk-3.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\icons\chunk-2.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-4.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-2.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-5.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-12.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-6.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-7.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-10.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-16.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-13.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-14.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-11.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-8.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\@fluentui\react-icons\lib\sizedIcons\chunk-17.js as it exceeds the max of 500KB.
[BABEL] Note: The code generator has deoptimised the styling of <removed>\node_modules\exceljs\dist\exceljs.min.js as it exceeds the max of 500KB.
[Webpack stats]:
asset bundle.js 806 KiB [emitted] (name: main)
orphan modules 14.9 MiB [orphan] 363 modules
runtime modules 1.98 KiB 5 modules
cacheable modules 612 KiB
  modules by path ./node_modules/@griffel/ 40.1 KiB 27 modules
  modules by path ./node_modules/@fluentui/react-icons/lib/ 495 KiB
    modules by path ./node_modules/@fluentui/react-icons/lib/utils/*.js 5.2 KiB 2 modules
    + 2 modules
  modules by path ./node_modules/prop-types/ 4.01 KiB
    ./node_modules/prop-types/checkPropTypes.js 3.64 KiB [built] [code generated]
    + 2 modules
  modules by path ./node_modules/react/ 65.5 KiB
    ./node_modules/react/index.js 189 bytes [built] [code generated]
    ./node_modules/react/cjs/react.development.js 65.3 KiB [built] [code generated]
  + 4 modules
webpack 5.98.0 compiled successfully in 22081 ms
[1:55:14 PM] [build] Generating build outputs...
[1:55:14 PM] [build] Succeeded
```

From the log, you can see that for some reason, Babel is for some reason processing `@fluentui/react-icons` package, which has already been compiled. Same goes for `exceljs` which has been added by another library we rely on. Also note the time **22 seconds**. I started looking into what's going on in Webpack which is used by [`pcf-scripts`](https://www.npmjs.com/package/pcf-scripts) which hide away the complexity of building the PCF. You can inspect it when you install it into `node_modules` or online via [NPM's code explorer](https://www.npmjs.com/package/pcf-scripts?activeTab=code). There you can find a file called `webpackConfig.js` which contains the definition for bundling.

What striked my eyes was this part:

```javascript
{
    // Tell webpack how to handle JS or JSX files
    test: /\.(js|jsx)$/,
    use: [babelLoader],
},
```

This basically loads all included `*.js` or `*.jsx` files and processes them, including those in `node_modules`! So I did a quick experiment, by adding `exclude: /node_modules/` into the object and ran the build again:

```
npm run build

> pcf-project@1.0.0 build
> pcf-scripts build

[2:12:00 PM] [build] Initializing...
[2:12:00 PM] [build] Validating manifest...
[2:12:00 PM] [build] Validating control...
[2:12:01 PM] [build] Generating manifest types...
[2:12:01 PM] [build] Generating design types...
[2:12:01 PM] [build] Running ESLint...
[2:12:03 PM] [build] Compiling and bundling control...
[Webpack stats]:
asset bundle.js 807 KiB [emitted] (name: main)
orphan modules 15.1 MiB [orphan] 363 modules
runtime modules 1.98 KiB 5 modules
cacheable modules 610 KiB
  modules by path ./node_modules/@griffel/ 40.7 KiB 27 modules
  modules by path ./node_modules/@fluentui/react-icons/lib/ 499 KiB
    modules by path ./node_modules/@fluentui/react-icons/lib/utils/*.js 1.98 KiB 2 modules
    + 2 modules
  modules by path ./node_modules/prop-types/ 4.15 KiB
    ./node_modules/prop-types/checkPropTypes.js 3.78 KiB [built] [code generated]
    + 2 modules
  modules by path ./node_modules/react/ 59.4 KiB
    ./node_modules/react/index.js 190 bytes [built] [code generated]
    ./node_modules/react/cjs/react.development.js 59.2 KiB [built] [code generated]
  + 4 modules
webpack 5.98.0 compiled successfully in 3381 ms
[2:12:07 PM] [build] Generating build outputs...
[2:12:07 PM] [build] Succeeded
```

The messages about deoptimised styling are now gone! And if you take a look at the build time, it took just **3.3 seconds** (this is just an empty control, which doesn't have any big business logic, but you can already see the time saved)!

So the issue is actually in `pcf-scripts`, what now? Well, we got in touch with Microsoft and reaised the issue to see if they can fix it - I don't see any reason why `*.js` files in `node_modules` should be processed by Babel. At least in our case of PCFs, it hasn't broken anything. Thanks to this change, we can save **50%** of build time of the controls repo. Which is about 36 minutes!

Now the question is, how do we apply the fix, before (or if) Microsoft changes this in `pcf-scripts`? Despites the fact that you can use your own [`webpack.config.js`](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/dependent-libraries?WT.mc_id=powerapps_community_productblog#webpackconfigjs) (via `pcfAllowCustomWebpack` feature flag), due to its use of [`webpack-merge`](https://www.npmjs.com/package/webpack-merge)'s `merge`, you can't really easily use it to override  the `module/rules` in original Webpack config. Due to that, we decided to override the file in `node_modules` (you shouldn't do this in most cases, but there isn't really any other option besides "forking" `pcf-scripts` and modifying the compiled code ourselves, which we don't want to do, since it isn't opensource).

Thanks to [Rush](https://rushjs.io), we can hook to `postRushInstall` event, which can execute custom code whenever packages have been installed (you can do the same with [`postinstall`](https://docs.npmjs.com/cli/v6/using-npm/scripts#npm-install) in NPM). So we configure `rush.json` like this:

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/rush/v5/rush.schema.json",
  ...
  "eventHooks": {
    ...
    "postRushInstall": [
      "node common/scripts/post-rush-install-fixpcfscripts.js"
    ],
    ...
  }
  ...
}
```

And then we create the respective script:

```javascript
// This code is used to fix an issue in pcf-scripts package which causes longer build times due to processing .js and .jsx files through Babel.
// Since the code is outside of our control, we need to modify the package manually after installation until Microsoft fixes the issue.

const fs = require('fs');
const path = require('path');
const { exit } = require('process');

function findPcfScriptsPackages(nodeModulesPath) {
    const packages = [];
    const dirs = fs.readdirSync(nodeModulesPath, { withFileTypes: true });

    for (const dir of dirs) {
        if (dir.isDirectory() && dir.name.startsWith('pcf-scripts')) {
            packages.push(path.join(nodeModulesPath, dir.name));
        }
    }

    return packages;
}

function modifyWebpackConfig(packagePath) {
    const webpackConfigPath = path.join(packagePath, 'node_modules', 'pcf-scripts', 'webpackConfig.js');
    if (fs.existsSync(webpackConfigPath)) {
        let content = fs.readFileSync(webpackConfigPath, 'utf8');
        
        // Find a line containing // Tell webpack how to handle JS or JSX files
        const regex = /\/\/ Tell webpack how to handle JS or JSX files/;
        const match = content.match(regex);
        const prefix = `// Modified by post-rush-install-fixpcfscripts.js`;
        if (match) {
            const index = match.index;
            const startIndex = content.lastIndexOf('{', index);
            const endIndex = content.indexOf('},', index) + 1;
            let jsLoaderCode = content.substring(startIndex, endIndex);

            if(jsLoaderCode.includes(prefix)) {
                console.log(`webpackConfig.js code already modified: ${jsLoaderCode}, ${webpackConfigPath}`);
                return;
            }
            if(jsLoaderCode.includes('exclude')) {
                console.error(`webpackConfig.js code already has exclude: ${jsLoaderCode}, ${webpackConfigPath}`);
                exit(1);
            }
            
            let replacement = `${prefix}\nexclude: /node_modules/\n`;
            jsLoaderCode = jsLoaderCode.replace(/}$/, `${replacement} }`);
            console.log(`${jsLoaderCode}`);
            
            content = content.substring(0, startIndex) + jsLoaderCode + content.substring(endIndex);
        }

        fs.writeFileSync(webpackConfigPath, content, 'utf8');
        console.log(`Modified: ${webpackConfigPath}`);
        exit(1);
    } else {
        console.warn(`webpackConfig.js not found in ${webpackConfigPath}`);
    }
}

function main() {
    const nodeModulesPath = path.resolve(__dirname, '../temp/node_modules/.pnpm');
    if (!fs.existsSync(nodeModulesPath)) {
        console.error('node_modules directory not found.');
        return;
    }

    const pcfScriptsPackages = findPcfScriptsPackages(nodeModulesPath);
    for (const packagePath of pcfScriptsPackages) {
        modifyWebpackConfig(packagePath);
    }
}

main();
```

What the script does is, that it finds installed `pcf-scripts` (the paths would be different for npm), finds the `webpackConfig.js` file, identifies the code block and modifies it to add the exclude mentioned above. It also checks if the file has been modified by the script.

You can then run `rush --debug update` and see it in action with logs.