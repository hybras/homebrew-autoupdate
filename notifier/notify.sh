#!/bin/bash
# Updater scripts generated before app/ was renamed from notifier/ call this
# path, and setups created before options were saved keep their script.
# Forward them to the renamed script and the app's new location.
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
exec "${script_dir}/../app/notify-result.sh" "${1:-}" "${2:-}" "${3:-always}" "${script_dir}/../app/brew-autoupdate.app"
