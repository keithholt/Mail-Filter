#!/bin/zsh
set -eu
root=${0:A:h:h}
label=org.mail-filter.agent
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
logs="$HOME/.local/state/mail-filter/logs"
case "${1:-status}" in
  install|install-apply)
    [[ -x "$root/.build/release/mail-filter" ]] || { print -u2 'Build the release executable first.'; exit 1; }
    [[ -f "$HOME/.config/mail-filter/accounts.txt" ]] || { print -u2 'Set up the private account file first.'; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents" "$logs"
    chmod 700 "$logs"
    python3 - "$root" "$plist" "$logs" "$1" <<'PY'
import os, plistlib, sys
root, path, logs, mode = sys.argv[1:]
args = [root + '/.build/release/mail-filter', '--skip-processed']
if mode == 'install': args += ['--dry-run']
job = {'Label': 'org.mail-filter.agent', 'ProgramArguments': args,
       'EnvironmentVariables': {'MAIL_FILTER_ROOT': root}, 'StartInterval': 900,
       'RunAtLoad': True, 'ProcessType': 'Background', 'Umask': 63,
       'StandardOutPath': logs + '/output.log', 'StandardErrorPath': logs + '/error.log'}
with open(path, 'wb') as f: plistlib.dump(job, f)
os.chmod(path, 0o600)
PY
    plutil -lint "$plist"
    if launchctl print "$domain/$label" >/dev/null 2>&1; then
      launchctl bootout "$domain/$label"
    fi
    launchctl bootstrap "$domain" "$plist"
    print "Installed $1: every 15 minutes. Logs: $logs"
    ;;
  stop) launchctl bootout "$domain/$label" ;;
  start) launchctl bootstrap "$domain" "$plist" ;;
  run) launchctl kickstart "$domain/$label" ;;
  status) launchctl print "$domain/$label" ;;
  logs) tail -n 30 "$logs/output.log" "$logs/error.log" ;;
  *) print -u2 'Usage: scripts/agent.sh install|install-apply|stop|start|run|status|logs'; exit 1 ;;
esac
