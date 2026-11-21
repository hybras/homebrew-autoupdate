# Contributing

Thanks for helping improve `brew autoupdate`. This guide covers setting up a
development copy, the layout of the repository, testing, and building the
helper app. For why things are the way they are, see
[ARCHITECTURE](ARCHITECTURE.md), which specifies the design; it is linked
below wherever a rule comes from it.

## Background reading

- Homebrew's [External Commands](https://docs.brew.sh/External-Commands) page
  explains how tap commands work: the command types, the tap layout,
  `AbstractCommand` with `cmd_args`, and tap trust. Ruby commands use Homebrew
  internals that come "without compatibility guarantees", so prefer public
  APIs.
- Homebrew's [Reproducible Builds](https://docs.brew.sh/Reproducible-Builds)
  page explains the techniques this project relies on to make builds
  verifiable ([details](ARCHITECTURE.md#reproducible-builds)).

## Development setup

1. Fork the repository, then tap your fork and trust it:

   ```sh
   brew tap <you>/autoupdate
   brew trust --tap <you>/autoupdate
   ```

   Only one tap can provide `brew autoupdate`: Homebrew uses the first one it
   finds. Untap any other copy (for example `brew untap domt4/autoupdate`)
   before working on yours.

2. Work in the tap directory (`$(brew --repo <you>/autoupdate)`), on a branch.

3. If you use VS Code with the Swift extension, define these tasks in
   `.vscode/tasks.json` (the directory is not committed):
   - **Build app (ad-hoc):** `CODESIGN_IDENTITY=- app/build.sh .build/brew-autoupdate.app`
   - **Run tests:** every `test/*_test.rb`, with
     `BREW_AUTOUPDATE_APP=.build/brew-autoupdate.app`
   - **brew style** and **Tap syntax (brew test-bot)**

   A launch configuration can debug `brew-autoupdate notify …`.

## Repository layout

| Path | What it is |
| --- | --- |
| `cmd/autoupdate.rb` | the `brew autoupdate` command; its subcommands register themselves |
| `lib/autoupdate/` | one file per subcommand (`start`, `stop`, `restart`, `delete`, `status`, `logs`, `version`), shared modules that need Homebrew (`setup`, `signing`, `launchd`), and dependency-free generators (`config`, `script`, `launch_agent`, `launcher`, `interval`, `notify`, `core`) |
| `app/BrewAutoupdate.swift` | source of the helper app (`notify` and `run-updater`) |
| `app/build.sh` | builds, signs and verifies the app; `start` runs it |
| `app/notify-result.sh` | turns a run's result into a notification; `start` copies it into the job's folder |
| `test/` | minitest suites, one per area |
| `.github/workflows/` | CI and README help generation |

## Making changes

### Ruby

- Prefer Homebrew's helpers to plain Ruby equivalents: `SystemCommand.quiet_system`,
  `system_command` (`extend SystemCommand::Mixin`), `odie` and `opoo`
  (`extend Utils::Output::Mixin`). The exception is the dependency-free
  generators, which must stay loadable by plain `ruby` for their tests.
- Run `brew style <you>/autoupdate` (or `brew style --fix …`).
- No Sorbet signatures in `lib/`: plain `ruby` cannot load `sig`
  ([Conventions](ARCHITECTURE.md#conventions)).
- A subcommand is a `Homebrew::AbstractSubcommand` nested in
  `Homebrew::Cmd::Autoupdate`, in its own file in `lib/autoupdate/`, required
  from `lib/autoupdate.rb` ([Commands](ARCHITECTURE.md#commands)).
  Inside it, write `::Autoupdate` for this tap's module, since `Autoupdate`
  means the command class there.

### Shell

- `brew style` runs ShellCheck with every check enabled, plus shfmt.
- A tap that lives inside the Homebrew checkout inherits Homebrew's
  `.shellcheckrc`, which disables some checks that CI does not. To see what CI
  sees, run:

  ```sh
  shellcheck --norc --shell=bash --enable=all app/*.sh
  ```

### Swift

- Keep the app's main executable compiled. A script main executable makes
  macOS attribute App Management to `/bin/sh` instead of the app
  ([verified](ARCHITECTURE.md#app-shape)).
- Never run test builds of the app from `/tmp`: macOS refuses notification
  permission there ([verified](ARCHITECTURE.md#notification-permission)).
- The launcher and the app are always generated and built together by
  `start`, so their arguments can change freely.
- Names shared with Ruby (the support folder, script and status file names,
  the bundle ID) are checked by `test/constants_test.rb`.
- Format with `swift format`, which ships with the toolchain
  ([Conventions](ARCHITECTURE.md#conventions)).

### Documentation

- `README.md`'s help section between the `HELP-COMMAND-OUTPUT` markers is
  generated. After changing help text, run:

  ```sh
  python3 .github/generate-help-output.py
  ```

- Keep Markdown free of markdownlint warnings.

## Testing

Run every suite:

```sh
for test in test/*_test.rb; do ruby "$test"; done
```

To include the checks that build and run the real app bundle:

```sh
CODESIGN_IDENTITY=- app/build.sh .build/brew-autoupdate.app
BREW_AUTOUPDATE_APP="$PWD/.build/brew-autoupdate.app" ruby test/app_test.rb
```

- Without `BREW_AUTOUPDATE_APP`, `test/app_test.rb` skips the checks of the
  built app.
- `test/command_test.rb` runs the real `brew autoupdate` from your tap.
- Run Homebrew's tap checks as CI does:

  ```sh
  HOMEBREW_NO_AUTO_UPDATE=1 brew test-bot --only-tap-syntax --tap=<you>/autoupdate
  ```

### Testing on a real job

A registered job does not pick up source changes by itself. After changing
anything a job runs, run `brew autoupdate restart`
([details](ARCHITECTURE.md#applying-tap-changes)). Uncommitted changes do not
trigger the restart reminder.

When testing against your own launch agent, back up
`~/Library/LaunchAgents/com.github.hybras.homebrew-autoupdate.plist` and
`~/Library/Application Support/com.github.hybras.homebrew-autoupdate/` first,
and restore them afterwards. If you replace the updater script with a probe,
check that the probe is in place before launching the app; otherwise the app
runs your real update.

App Management cannot be trusted from System Settings: `brew autoupdate
status` shows what the last scheduled run found
([why](ARCHITECTURE.md#system-settings)). Never test it by
writing into apps in `/Applications` from a test or a terminal: macOS then
asks to grant App Management to your terminal or editor.

## Continuous integration

CI (`.github/workflows/tests.yml`):

- builds the app with an ad-hoc signature and uploads it as an artifact
- builds the Swift package
- runs every test file, and reports all failures rather than stopping at the
  first
- checks shell syntax and runs `brew test-bot --only-tap-syntax`

The README help output is regenerated on `main` only. Dependabot keeps the
pinned actions up to date.

## Building and signing the app

`brew autoupdate start` builds the app into the job's folder and signs it
with the certificate from `Autoupdate::Signing`
([The app](ARCHITECTURE.md#the-app), [Signing](ARCHITECTURE.md#signing)). To
build one yourself:

```sh
CODESIGN_IDENTITY="<identity>" app/build.sh <output.app>
```

`<identity>` is the name or SHA-1 of a code-signing certificate on your
keychain search list, such as `brew-autoupdate local signing` in your login
keychain. `-` (ad-hoc) is only for test builds, as in CI: an
ad-hoc app loses its App Management grant whenever it changes, so don't run
real jobs with it ([details](ARCHITECTURE.md#app-management)). Never
distribute the result: any binary given to others must be notarized
([requirement 9](ARCHITECTURE.md#requirements)).

- `build.sh` builds in a temporary directory and only replaces the output
  once signing and verification succeed.
- The version comes from `VERSION`.
- The build records a hash of `BrewAutoupdate.swift` and `build.sh`; `start`
  skips rebuilding when it matches and the app is signed with the current
  certificate.
- Builds are reproducible only with the same Swift and SDK
  ([verified](ARCHITECTURE.md#reproducible-builds)).
- Keep the bundle ID unchanged: changing it resets the app's App Management
  and notification permission.

## Releases

A release today is a `version: bump` commit that updates `VERSION`;
`brew autoupdate version` lists the changes since the previous one. Releases
are not automated.

## Commits

- Keep commits atomic, each with a message that explains why.
- Subjects follow the existing `area: summary` style.
- Style per language is in [Conventions](ARCHITECTURE.md#conventions).
