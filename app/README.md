# brew-autoupdate app

`brew-autoupdate.app` is the helper app that runs scheduled updates and posts
their notifications. `BrewAutoupdate.swift` is its source, and `build.sh`
builds and signs it; `brew autoupdate start` runs `build.sh` to build the app
into the job's folder. `notify-result.sh` turns a run's result into a
notification.

- How it works: [ARCHITECTURE](../ARCHITECTURE.md), especially
  [Interfaces](../ARCHITECTURE.md#interfaces),
  [The app](../ARCHITECTURE.md#the-app) and
  [Signing](../ARCHITECTURE.md#signing).
- How to build, sign and test it: [CONTRIBUTING](../CONTRIBUTING.md#building-and-signing-the-app).
