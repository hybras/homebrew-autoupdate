# Homebrew Autoupdate

An easy, convenient way to automatically update Homebrew.

This script will run `brew update` in the background once every 24 hours (by
default) until explicitly told to stop, utilising `launchd`.

`brew upgrade` and `brew cleanup` can also be handled automatically, but
are optional flags.

Scheduled runs go through a small macOS app that `brew autoupdate start`
builds from source and signs on your Mac. It also shows notifications, which
are on by default. Pass `--notify-on-error` to suppress successful-run notifications, or
`--no-notify` to disable notifications entirely.

![A comic highlighting humanity's habit of skipping important updates](https://imgs.xkcd.com/comics/update.png)

## Installing this command

Tap the repository and trust its external command:

```sh
brew tap hybras/autoupdate
brew trust --command hybras/autoupdate/autoupdate
```

This is a personal development fork of
[DomT4/homebrew-autoupdate](https://github.com/DomT4/homebrew-autoupdate). It
is not published for others to use: its helper app is not notarized, and is
built from source on your own Mac (see
[ARCHITECTURE](ARCHITECTURE.md#d07-notarization)).

Only one tap can provide `brew autoupdate`. If you used DomT4's tap, run
`brew autoupdate delete` with it first, then `brew untap domt4/autoupdate`:
this fork uses its own names (`com.github.hybras.homebrew-autoupdate`) and
cannot manage DomT4's launch agent.

Homebrew is moving towards requiring explicit trust before loading commands
from non-official taps. Command-scoped trust is recommended here because it
permits only `brew autoupdate`; it does not trust every current or future
formula, cask, or command in this tap.

Existing users who see an untrusted tap warning can run the `brew trust`
command above. When trust enforcement is enabled, an already installed launch
agent will continue running its scheduled built-in `brew update`, `upgrade`,
and `cleanup` commands. Management commands such as `brew autoupdate status`,
`stop`, or `delete` will be unavailable until `autoupdate` is trusted.

See [Homebrew's tap trust documentation](https://docs.brew.sh/Tap-Trust) and
[issue #222](https://github.com/DomT4/homebrew-autoupdate/issues/222) for
background.

Now run `brew autoupdate start [interval] [options]` to enable autoupdate.
The interval defaults to 24 hours and accepts seconds or a short duration such
as `30m`, `12h`, or `1d`, or a 24-hour clock time such as `00:00` to run daily
at that specific time instead of relative to when the command was run.

`start` needs the Xcode Command Line Tools to build the app, which takes about
a minute. The first time, it also creates a code-signing certificate for the
app in a keychain of its own, and says so. The certificate stays the same
when the app is rebuilt, so macOS keeps the app's permissions. Any program
running as you can sign code with it; `brew autoupdate delete` removes it.

### Upgrading apps in place (App Management)

When `--upgrade` includes casks, macOS only lets Homebrew update an app in
place (keeping its Dock position and settings) if the upgrade runs with App
Management permission. Scheduled runs go through the `brew-autoupdate` app,
so the permission belongs to that app and survives Homebrew's Ruby upgrades
and the app's own rebuilds.

1. Open System Settings > Privacy & Security > App Management.
2. Click **+**, press Cmd+Shift+G and enter the app's path, shown at the end
   of `brew autoupdate start --upgrade`
   (`~/Library/Application Support/com.github.hybras.homebrew-autoupdate/brew-autoupdate.app`).
3. Make sure the switch is on.

The app may not appear in that list, or may not stay visible, even when the
permission is in effect, so don't rely on the list. Allowing the "prevented
from modifying apps" notification alone does not grant it either. Without the
permission, Homebrew still upgrades the app, but by reinstalling it.

After each scheduled run that upgrades casks, `brew autoupdate status` shows
whether that run had the permission. Manual `brew upgrade` runs keep using
your terminal's permission.

## Example

```sh
brew autoupdate start 12h --upgrade --cleanup --immediate --sudo
```

This will upgrade all your casks and formulae every 12 hours and on every system boot.
If a sudo password is required for an upgrade, a GUI to enter your password will be displayed.
Also, it will clean up every old version and left-over files.

Casks that have built-in auto-updates enabled by default will not be upgraded.

### Upgrade Only Specific Packages

```sh
brew autoupdate start 12h --upgrade --only=wget,node,firefox
```

This will only auto-upgrade `wget`, `node`, and `firefox` every 12 hours,
leaving all other installed packages untouched. Both formulae and casks are
supported, including tap-qualified names (`homebrew/cask/firefox`) and
versioned formulae (`node@20`).

Cannot be combined with `--leaves-only`. To change which packages are
auto-upgraded, run `brew autoupdate stop` then start again with the new list.

### Run at a specific time every day

```sh
brew autoupdate start 00:00 --upgrade --cleanup
```

Instead of a duration, pass a 24-hour clock time (`HH:MM`) to schedule the run
via `launchd`'s `StartCalendarInterval` at that exact wall-clock time every
day, rather than a relative interval measured from whenever the command was
run (which drifts and won't line up with midnight, or any other fixed time,
over repeated runs).

## Usage

<!-- HELP-COMMAND-OUTPUT:START -->

```help
From tap: hybras/autoupdate
Usage: brew autoupdate subcommand [options]

An easy, convenient way to automatically update Homebrew.

This script will run brew update in the background once every 24 hours (by
default) until explicitly told to stop, utilising launchd.

Start autoupdating with:
  brew autoupdate start [interval] [options]

The interval defaults to 24 hours. It can be provided as seconds or as a
duration such as 30m, 12h, 1d, or 1w, or as a 24-hour clock time such as
00:00 to run daily at that specific time instead of relative to when the
command was run.

Common start options:
  --upgrade upgrades installed formulae and casks.
  --cleanup cleans Homebrew's cache and logs after a successful run.
  --immediate runs immediately and whenever the launch agent is loaded.
  --only=wget,node,firefox upgrades only the listed packages.
  --leaves-only upgrades only top-level formulae.
  --greedy includes auto-updating casks.
  --sudo enables a GUI password prompt for cask upgrades.
  --ac-only skips runs while the Mac is on battery power.
  --notify-on-error shows notifications only for failed runs.
  --no-notify disables notifications.

After this tap's source changes, run brew autoupdate restart so the job uses
the new version; status and the job's notifications remind you.

Examples:
  brew autoupdate start
  brew autoupdate start 12h --upgrade --cleanup --immediate
  brew autoupdate start 1d --upgrade --only=wget,node,firefox
  brew autoupdate start 00:00 --upgrade --cleanup
  brew autoupdate restart
  brew autoupdate logs --lines=50
  brew autoupdate logs --follow

Run brew autoupdate start --help or brew autoupdate logs --help for complete
options for those subcommands.

Subcommands:
  start:
    Start autoupdating in the background.
  stop:
    Stop autoupdating while retaining the launch agent, configuration, and logs.
  restart:
    Start autoupdating again with the saved options.
  delete:
    Stop autoupdating and delete everything start created: the launch agent,
  status:
    Show whether autoupdate is running and describe its installed configuration.
  logs:
    Show the output of the latest autoupdate run.
  version:
    Show this tool's current version and a short changelog.

  -d, --debug                      Display any debugging information.
  -q, --quiet                      Make some output more quiet.
  -v, --verbose                    Make some output more verbose.
  -h, --help                       Show this message.

From tap: hybras/autoupdate
Usage: brew autoupdate start [interval] [options]:
    Start autoupdating in the background. The interval defaults to 24 hours and
accepts seconds or a suffix such as 30m, 12h, or 1d, or a 24-hour clock
time such as 00:00 to run daily at that specific time. After stop, running
start with no interval or options resumes with the saved options; otherwise
the given ones replace them.

  -d, --debug                      Display any debugging information.
  -q, --quiet                      Make some output more quiet.
  -v, --verbose                    Make some output more verbose.
  -h, --help                       Show this message.
      --upgrade                    Automatically upgrade installed formulae and
                                   casks.
      --greedy                     Include auto-updating casks when upgrading.
      --cleanup                    Automatically clean Homebrew's cache and
                                   logs.
      --immediate                  Run immediately and on login instead of
                                   waiting for the first interval.
      --sudo                       Open a GUI password prompt when a cask
                                   upgrade requires sudo. Requires
                                   pinentry-mac to be installed.
      --leaves-only                Upgrade only top-level formulae that are not
                                   dependencies.
      --only                       Upgrade only these formulae and/or casks
                                   (comma-separated). Requires --upgrade.
      --ac-only                    Run only while the Mac is connected to AC
                                   power.
      --notify-on-error            Notify only when an autoupdate run fails.
      --no-notify                  Disable autoupdate notifications.

From tap: hybras/autoupdate
Usage: brew autoupdate logs [options]:
    Show the output of the latest autoupdate run.

  -d, --debug                      Display any debugging information.
  -q, --quiet                      Make some output more quiet.
  -v, --verbose                    Make some output more verbose.
  -h, --help                       Show this message.
  -f, --follow                     Follow the log as new output is written.
  -n, --lines                      Show this many lines from the end of the log.
                                   Defaults to 10.
```

<!-- HELP-COMMAND-OUTPUT:END -->

**Each run's log is kept in:** `~/Library/Logs/com.github.hybras.homebrew-autoupdate/runs`
(the newest 30). `brew autoupdate logs` shows the latest one.

## This vs `brew`'s built-in autoupdate mechanism

This command mostly exists to ensure Homebrew is updated regardless of whether
you invoke `brew` or not, which is the primary difference from the autoupdate
mechanism built into `brew`, the latter requiring a user to explicitly run
any of `brew install`, `brew tap` or `brew upgrade`.

If you run `brew` commands regularly yourself, you may wish to consider using
the built-in autoupdate mechanism, which can be instructed to autoupdate less
often, or disabled entirely. If you wish to update every 24 hours using the
built-in autoupdate mechanism set this in your environment:

```sh
export HOMEBREW_AUTO_UPDATE_SECS="86400"
```

or if you wish to disable the built-in autoupdate mechanism entirely:

```sh
export HOMEBREW_NO_AUTO_UPDATE="1"
```

Please note that Homebrew slightly frowns upon people disabling the built-in
autoupdate mechanism.

## How it works

`brew autoupdate start` saves your options, builds and signs the app, and
writes a launch agent plus a few small shell scripts. Everything a job runs
lives in `~/Library/Application Support/com.github.hybras.homebrew-autoupdate`,
so updating this tap does not change a running job. On schedule, `launchd`
runs a launcher script, which opens the app; the app runs the updater script,
which runs `brew update`, `upgrade` and `cleanup` as configured, then reports
the result as a notification listing what was upgraded.
[ARCHITECTURE](ARCHITECTURE.md) explains the design and the decisions behind
it.

A job keeps the files it was started with. Whenever this tap's source
changes, whether through `brew update` or your own edits, restart the job so
it picks the changes up:

```sh
brew autoupdate restart
```

`restart` reuses your saved options and keeps the app's permissions. When the
tap's commit no longer matches the job's, the job's notifications and
`brew autoupdate status` remind you
([details](ARCHITECTURE.md#d38-applying-upgrades)). Uncommitted edits do not
trigger the reminder.

## Verifying what runs

Everything a scheduled run executes can be read: the scripts in the folder
above, the Ruby code in this tap, and the app's source in
`app/BrewAutoupdate.swift`, which `start` builds on your Mac. No prebuilt
binary is involved. Builds are reproducible when the Swift and SDK versions
are the same (see [ARCHITECTURE](ARCHITECTURE.md#reproducible-builds)).

## Troubleshooting

- **`brew autoupdate` is refused as untrusted:** run the `brew trust` command
  from [Installing this command](#installing-this-command).
- **`start` fails while building the app:** install the Command Line Tools
  with `xcode-select --install`, then run `brew autoupdate start` again.
- **`status` says App Management was "not granted":** grant it as described
  in [Upgrading apps in place](#upgrading-apps-in-place-app-management).
- **Apps are reinstalled instead of upgraded in place:** grant App Management
  as described in [Upgrading apps in place](#upgrading-apps-in-place-app-management).
- **No notifications:** check System Settings > Notifications for
  `brew-autoupdate`, and look for "could not display the update result" in
  `brew autoupdate logs`. macOS 27 is reported to refuse notifications from
  apps that are not notarized, which includes this one
  ([#255](https://github.com/DomT4/homebrew-autoupdate/issues/255)). This is
  not handled yet; updates still run, so check `brew autoupdate logs`
  instead ([known issue](ARCHITECTURE.md#macos-27-may-refuse-notifications)).
- **`status` says "This tap has changed since the job started":** run
  `brew autoupdate restart`.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for setup, testing and building the app,
and [ARCHITECTURE](ARCHITECTURE.md) for the design decisions.

## History

This tap was created by [DomT4](https://github.com/DomT4) in April 2015 to
address a personal desire for a background updater, before being moved to
the Homebrew organisation in April 2021 to become an official part of the
project after gaining somewhat widespread usage, something I'm both surprised
by, but also very appreciative of people finding a small tool I wrote so
useful & contributing their own ideas and time towards.

It was in late 2023 moved back to DomT4's ownership to reduce the burden on
the wider Homebrew leadership team in terms of maintenance/support requests.

## License

Code is under the [BSD 2 Clause (NetBSD) license](https://github.com/DomT4/homebrew-autoupdate/blob/master/LICENSE.txt).
