# brew-autoupdate app

`brew-autoupdate.app` is the helper app that runs scheduled updates and posts
their notifications. `BrewAutoupdate.swift` is its source, `build.sh` builds
and signs it, and `notify-result.sh` turns a run's output into a notification.

- How it works, and why: [ARCHITECTURE](../ARCHITECTURE.md), especially
  [Internal interfaces](../ARCHITECTURE.md#internal-interfaces) and
  [D39 signing modes](../ARCHITECTURE.md#d39-signing-modes).
- How to build, sign and test it: [CONTRIBUTING](../CONTRIBUTING.md#building-and-signing-the-app).
