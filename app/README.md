# brew-autoupdate app maintenance

`BrewAutoupdate.swift` is the reviewable source for the helper app.
`notify-result.sh` summarizes only the output from the current autoupdate run and
passes the resulting title, subtitle, and message to the app as
`brew-autoupdate notify <title> <subtitle> <message>`.
The native helper uses macOS's UserNotifications framework and runs as a
background UI app, so it does not appear in the Dock.

## Validate without signing

```sh
bash -n app/notify-result.sh app/build.sh
swift build
ruby test/app_test.rb
```

The package manifest also allows CodeQL to compile and analyze the standalone
Swift source. CI performs these checks but does not sign or replace the
committed app.

## Rebuild and sign locally

Set the identity exactly as shown by `security find-identity -v -p codesigning`:

```sh
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" app/build.sh
```

The app version is read from the repository's `VERSION` file, which is also
used by `brew autoupdate --version`.

The build happens in a temporary directory. The committed app is replaced only
after signing and strict verification succeed.

`../notifier/notify.sh` forwards to `notify-result.sh` for updater scripts
generated before this directory was renamed from `notifier/`.

## Updater mode

The app also runs scheduled updates
(`brew-autoupdate run-updater <log> <launcher-pid>`), stopping the update if
the launcher exits. The launch agent runs `brew_autoupdate_launcher`, which
opens the app through LaunchServices so
macOS attributes App Management checks to this app instead of Homebrew's
portable Ruby. The launcher only does this when the app's `Info.plist` lists
`run-updater-1` in `BrewAutoupdateCapabilities` (added by `build.sh`); otherwise
it runs the updater script directly. A rebuilt app therefore has to be
committed together with a `VERSION` bump before users get the new behaviour;
`build.sh` records a SHA-256 of `BrewAutoupdate.swift` and `build.sh` in the app's
`Info.plist`, and CI fails until the committed app matches the current sources.

The `-1` names the current `run-updater` arguments. If they change, list a new
name (`run-updater-2`) alongside the old one and keep accepting the old
arguments: existing launchers keep using them until the user runs
`brew autoupdate start` again.

App Management grants are tied to the app's code signature. Keep signing with
the same Developer ID and bundle identifier so existing grants carry over to
rebuilt apps.
