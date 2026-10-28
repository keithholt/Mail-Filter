#!/bin/zsh
# Stages only the signed, isolated Development configuration. Never replaces
# /Applications/Mail-Filter.app or imports its data or activates Mail extensions.
set -eu
root=${0:A:h:h}
[[ $# == 0 || ($# == 1 && "$1" == --no-build) ]] || {
    print -u2 'Usage: MacApp/install-dev.sh [--no-build]'; exit 1
}
if [[ $# == 0 ]]; then "$root/MacApp/store-build.sh" development; fi
source_app="${MAIL_FILTER_DERIVED_DATA_PATH:-$root/.build/xcode-derived}/Build/Products/Development/Mail-Filter.app"
python3 "$root/MacApp/Store/verify.py" "$source_app" --development
python3 - "$root" "$source_app" <<'PY'
from pathlib import Path
import datetime, os, plistlib, subprocess, sys, tempfile
root, source = map(Path, sys.argv[1:])
destination = Path.home() / 'Applications/Mail-Filter Dev.app'
def info(path):
    return plistlib.loads((path / 'Contents/Info.plist').read_bytes())
metadata = info(source)
if (metadata.get('CFBundleIdentifier'), metadata.get('CFBundleDisplayName'), metadata.get('MailFilterAppGroup')) != (
    'org.mail-filter.development', 'Mail-Filter Dev', 'group.org.mail-filter.development.shared'):
    raise ValueError('Refusing to stage a non-Dev product')
if destination.exists():
    if info(destination).get('CFBundleIdentifier') != 'org.mail-filter.development':
        raise ValueError('Refusing to replace another app')
    processes = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
    if str(destination) + '/Contents/' in processes:
        raise ValueError('Quit Mail and Mail-Filter Dev before replacing this development app')
destination.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='.mail-filter-dev-', dir=destination.parent) as temp:
    staged = Path(temp) / destination.name
    subprocess.run(['/usr/bin/ditto', str(source), str(staged)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(staged)], check=True)
    if destination.exists():
        backup = root / 'outputs/development' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        backup.mkdir(parents=True)
        os.rename(destination, backup / destination.name)
    os.rename(staged, destination)
subprocess.run(['/usr/bin/pluginkit', '-r', str(source / 'Contents/PlugIns/Mail-Filter.appex')], check=True)
subprocess.run(['/usr/bin/pluginkit', '-a', str(destination / 'Contents/PlugIns/Mail-Filter.appex')], check=True)
print('Installed ' + str(destination))
print('Separate development settings and extension; no setup was imported and no extension was enabled.')
PY
