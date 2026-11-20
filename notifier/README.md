# Notifier maintenance

`notifier.swift` is the reviewable source for the notification app.
`notify.sh` summarizes only the output from the current autoupdate run and
passes the resulting title, subtitle, and message to the app as arguments.
The native helper uses macOS's UserNotifications framework and runs as a
background UI app, so it does not appear in the Dock.

## Validate without signing

```sh
bash -n notifier/notify.sh notifier/build.sh
swift build
ruby test/notifier_test.rb
```

The package manifest also allows CodeQL to compile and analyze the standalone
Swift source. CI performs these checks but does not sign or replace the
committed app.

## Rebuild and sign locally

Set the identity exactly as shown by `security find-identity -v -p codesigning`:

```sh
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" notifier/build.sh
```

The app version is read from the repository's `VERSION` file, which is also
used by `brew autoupdate --version`.

The build happens in a temporary directory. The committed app is replaced only
after signing and strict verification succeed.

## Updater mode

The app also runs scheduled updates (`--run-updater <log>`). The launch agent
runs `brew_autoupdate_launcher`, which opens the app through LaunchServices so
macOS attributes App Management checks to this app instead of Homebrew's
portable Ruby. The launcher only does this when the app's `Info.plist` lists
`run-updater` in `BrewAutoupdateCapabilities` (added by `build.sh`); otherwise
it runs the updater script directly. A rebuilt app therefore has to be
committed together with a `VERSION` bump before users get the new behaviour.

App Management grants are tied to the app's code signature. Keep signing with
the same Developer ID and bundle identifier so existing grants carry over to
rebuilt apps.
