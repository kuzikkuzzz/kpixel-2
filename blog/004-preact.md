# Migrating from react to preact

**Disclaimer:** This is a story of our own experience and not a guide, dated May 2026. The motivation for writing this is the fact that you mostly get either LLM slop or reports from six years ago when searching for this subject.

## Current State

### Where we are

We have a code base of 100 react components and various custom hooks. We do not use Portals, but rely heavily on Contexts. The repository [is here](https://git.pixelplanet.fun).

The project started years ago with class components, migrated to functional components and is now on React 18 with 2388 commits. We do not use React Compiler. It is plain JavaScript, not Type Script, but initially used [flow](https://flow.org/) for type checking. Once upon a time we utilized React for server-side rendering as well, but it got us DDoSed, so we only have HTML in template strings now. Paths are followed by our own logic, no React Router.

We focus on building stuff ourselves, so the current list of react related dependencies is unusually small for the project size:

- react-icons
- react-redux
- redux-persist
- react-toggle
- react-chartjs-2

### Where is React

React is at version `19` for 1.5 years now. React 18 is EoL, had its latest release in April 2024, but is still getting security updates when they are necessary; they were not necessary in the past year, speaking for its stability.

React 19 focuses on the (optional) React Compiler, server-side rendering performance and increases the bundle size by **30%**. From `143.87 kB` to `186.49 kB`. A larger bundle size doesn't necessarily mean slower page load — optimizations could make up for it — and so we can see in [some benchmarks](https://github.com/guoyunhe/test-react-bundle-size), that 19 can be faster for the first draw than 18, while being slower for a full page load.

The only benchmark that matters is our own application. Whatever a third-party benchmark does, is not what we do, so their results don't translate well. But the **30%** size increase is a fact and we individually have to decide whether it is worth it or not.

### Where is Preact

Preact claims to be an alternative to react, focusing on bundle size and performance. It is on major version `10` for 7 years now, and keeps publishing updates for it. `10.29.1` was released a month before this writing. Version `11` is in beta. [Their blog](https://preactjs.com/blog) had their last post almost two years ago, but their documentation looks great on first glance.

Preact claims `3 kB` bundle size, but to become compatible with react, it also needs `preact/compat`, pushing it to `16 kB`.


## The options

### React 19

React Compiler is appealing, but with many components used for multiple years and refactored regularly during those, i am hesitant on dumping the manual memoization. I do not have any issues with writing `useMemo` and `useCallback` myself. Migrating to it also makes it harder to switch to a different framework later.

Since we do not use reacts server side rendering and are indifferent about React Compiler, what is left is the 30% increase in bundle size, which we do care about. No React 19 for us.

### Staying with React 18

React 18 is very stable and will be supported for years to come. The issue with consciously freezing the major version is third party components. At some point in the future, third party libraries will use new React features that aren't on 18 and become incompatible. Freezing them as well may become a hazard.

So a long-term goal, when staying with 18, would be to replace all react related third party dependencies. A goal we have anyway.

### Preact

Preact aligns closer with our philosophy. React dependent third party libraries can be used by making the bundler overwrite react imports to `preact/compat`(like in webpack, by defining an alias). This may or may not work. Just like React 18, it turns them into a possible (future or current) headache.

Again, we have to replace or merge react related third party dependencies. **Lets bite the bullet now: Preact is the goal, with a self-imposed restriction of not aliasing react.**

## Merging third party dependencies

First we replace or merge react related dependencies, to get a grasp of what react features we are using and to bring them under our control, in the likely case we want to adjust or replace them.

### react-redux

The elephant in the room is redux. [react-redux](https://github.com/reduxjs/react-redux/tree/master/src) had its last relevant commit over two years ago, with a source folder with 30 files summing up to `164 kB`. Much of it being Type Script definitions, which we do not need in our masochistic vanilla JS project. A big part of the code base is `connect()`, which is from pre-functional-components times [and about to be deprecated](https://github.com/reduxjs/react-redux/issues/2264). And there is an isomorphic wrapper for `useLayoutEffect`, which we don't need since we are always on the client.

Copying it into our repository and removing the things we do not use got us down to 9 manageable files. Linting it with our rules got us three `react-hooks/exhaustive-deps` and one `react-hooks/immutability` warnings, none of which point to any actual issue.

[use-sync-external-store/with-selector](https://www.npmjs.com/package/use-sync-external-store?activeTab=readme) is the only dependency and we will tackle it when moving to preact later.

### redux-persist

`redux-persist` is unmaintained for over five years and we only use it to take a redux store and store it in localStorage. We can do this ourselves. The only reason why it pulls in react, is because it offers a component to wait until the store is loaded. We don't need that.

### react-icons

There are many libraries for SVG icons, also native ones for preact, but some are unmaintained and others don't offer the icons we want.
So why not drop it altogether and instead include `.svg` icons directly, which has the benefit that we can modify them or bundle our own? `react-svgr` can do this for us and has a section for preact and webpack [in its documentation](https://react-svgr.com/docs/webpack/).

Under modules.rules in webpack.config.client.js:
```js
{
  test: /\.svg$/,
  use: [
    /* using our babel-loader, so we can use either react or preact */
    'babel-loader',
    {
      loader: '@svgr/webpack',
      options: {
        icon: true,
        babel: false,
        jsxRuntime: 'automatic',
        svgProps: {
          className: 'svgr-icon',
        },
      },
    },
  ],
},
```

### react-chartjs-2

[react-chartjs-2](https://github.com/reactchartjs/react-chartjs-2) is a wrapper for [chart.js](https://www.chartjs.org). There is a preact port of it, but it is outdated and unmaintained. It only consists of two files with Components, merging it into our code base is no issue. It uses `forwardRef()` a lot.

### react-toggle

It is just a toggle. There are enough available libraries that do similar things like [preact-material-components/Switch](https://material.preactjs.com/component/switch/). But for now `<input type="checkbox" />`will do.

## Trying Preact

After testing and confirming that the merges work, it is time to try preact. Ever since `runtime: 'automatic'` became a thing in `@babel/plugin-transform-react-jsx`, we do not need `import React from 'react'` on top of our jsx files anymore. We only have to define `importSource: 'preact'`and it will do the right thing and use preact instead.

Under plugins in babel.config.js:
```
['@babel/plugin-transform-react-jsx', {
  runtime: 'automatic',
  importSource: 'preact',
}],
```

For testing, i imported `forwardRef` in our react-chartjs-2 copy using `preact/compat`, merged [useSyncExternalStoreWithSelector](https://github.com/facebook/react/blob/main/packages/use-sync-external-store/src/useSyncExternalStoreWithSelector.js) and imported the `useSyncExternalStore` inside it also with `preact/compat` (which is itself a copy of the shim offered in reacts repository).
All occurrences of `memo`, `lazy` and `Suspense` also had to be imported from `preact/compat`.

### First impression

Everything tested so far works. The initial load is noticeably faster, but i can not judge the performance in operation before deployment. The bundle sizes:

```
Before After    Name
304K   304K     client.en.4ce8bdf7.js
56K     56K     converter.en.ef3513bd.js
8,0K     8K     globe.en.5db73fdc.js
4,0K     4K     invite.en.390c834b.js
32K     28K     modtools.en.39d1d4a0.js
8,0K     8K     oidc.en.272ef069.js
232K   232K     popup.en.259b9eaf.js
208K   212K     stats.en.a9951157.js
24K     24K     voxel.en.23e8c041.js
196K    36K     vendor.68b754c1.js
184K    32K     pvendor.d90d4d43.js
```

We saved 25% on total JS and 32% of the main entry point (client + vendor). The next subject of optimization is getting obvious as well: The code splitting. The `vendor.js` and `pvendor.js` bundles are everything we use that is in `node_modules`, this made sense when it was large, because it could be efficently cached and would change less often than `client.js`, but since the relations are so different now, and the `vendor.js` only a ninth of `client.js`, this should be rethought.

### The 14kB rule

An interesting question is whether or not we can use [the 14kB rule](https://endtimes.dev/why-your-website-should-be-under-14kb-in-size/) to get a quick first draw and save a round-trip.

In our application, the first draw would be initialization of the store, websocket, the canvas renderer (which itself fetches chunks and images, so it best be available soon) and preact. All the components can come in later.

A quick split in webpack revealed that we have (in gzipped size) 8.35K of preact + `preact/compat` and 18.54K of store related stuff. This is 26.7K already. With some effort the store could be cut down below 14K (don't need all actions available immediately), but including preact and some components in an inline script in the html and expecting to stay below 14K is unrealistic.