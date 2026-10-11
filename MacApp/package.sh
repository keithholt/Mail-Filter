#!/bin/zsh
set -eu
umask 022
root=${0:A:h:h}
mode=${1:-local}
[[ "$mode" == local || "$mode" == release ]] || { print -u2 'Usage: MacApp/package.sh [local|release]'; exit 1; }
if [[ "$mode" == release ]]; then
    [[ "${MAIL_FILTER_INSTALLER_IDENTITY:-}" == 'Developer ID Installer:'* ]] || {
        print -u2 'Release packaging requires MAIL_FILTER_INSTALLER_IDENTITY (Developer ID Installer).'
        exit 1
    }
fi
"$root/MacApp/build.sh" "$mode"
work="$root/.build/mac-package"
out="$root/outputs"
rm -rf "$work"
mkdir -p "$work/Payload" "$work/Resources" "$out"
mkdir -p "$work/CommandLinePayload/etc/paths.d"
printf '%s\n' '/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools/bin' > "$work/CommandLinePayload/etc/paths.d/org.mail-filter.command-line"
ditto "$root/.build/mac-app/Mail-Filter.app" "$work/Payload/Mail-Filter.app"
ditto "$root/.build/mac-app/Uninstall Mail-Filter.app" "$work/Payload/Uninstall Mail-Filter.app"
pkgbuild --analyze --root "$work/Payload" "$work/components.plist"
python3 - "$work" <<'PY'
from pathlib import Path
import plistlib, sys
work = Path(sys.argv[1])
path = work/'components.plist'
components = plistlib.loads(path.read_bytes())
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleHasStrictIdentifier'] = True
    component['BundleIsVersionChecked'] = True
    component['BundleOverwriteAction'] = 'upgrade'
path.write_bytes(plistlib.dumps(components))
(work/'requirements.plist').write_bytes(plistlib.dumps({'os':['26.0'],'arch':['arm64']}))
PY
pkgbuild --root "$work/Payload" --component-plist "$work/components.plist" \
    --identifier org.mail-filter.installer --version 2.0.0 --install-location /Applications \
    "$work/MailFilterComponents.pkg"
pkgbuild --root "$work/CommandLinePayload" --ownership recommended --scripts "$root/MacApp/InstallerScripts/CommandLineOn" \
    --identifier org.mail-filter.command-line.enabled --version 2.0.0 --install-location / \
    "$work/MailFilterCommandLineOn.pkg"
pkgbuild --nopayload --scripts "$root/MacApp/InstallerScripts/CommandLineOff" \
    --identifier org.mail-filter.command-line.disabled --version 2.0.0 \
    "$work/MailFilterCommandLineOff.pkg"
productbuild --synthesize --product "$work/requirements.plist" --package "$work/MailFilterComponents.pkg" \
    --package "$work/MailFilterCommandLineOn.pkg" --package "$work/MailFilterCommandLineOff.pkg" "$work/Distribution.xml"
python3 - "$work" "$mode" <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET
import sys
work = Path(sys.argv[1])
tree = ET.parse(work/'Distribution.xml'); root = tree.getroot()
options = root.find('options')
options.set('customize','always'); options.set('require-scripts','true')
root.remove(root.find('choices-outline'))
for choice in root.findall('choice'): root.remove(choice)
outline = ET.SubElement(root,'choices-outline')
for identifier in ('app','commandLine','commandLineOff'):
    ET.SubElement(outline,'line',{'choice':identifier})
app = ET.SubElement(root,'choice',{'id':'app','title':'Mail-Filter','description':'Install Mail-Filter and its uninstaller.','visible':'false','selected':'true','enabled':'false'})
ET.SubElement(app,'pkg-ref',{'id':'org.mail-filter.installer'})
cli = ET.SubElement(root,'choice',{'id':'commandLine','title':'Add command-line tool to PATH','description':'Make mail-filter available in new Terminal windows. Uncheck to remove the PATH entry added by this installer; development launchers and private settings are preserved.','start_selected':'true'})
ET.SubElement(cli,'pkg-ref',{'id':'org.mail-filter.command-line.enabled'})
off = ET.SubElement(root,'choice',{'id':'commandLineOff','title':'Remove command-line PATH entry','description':'Remove only the PATH entry managed by Mail-Filter.','visible':'false','selected':'!choices.commandLine.selected','enabled':'false'})
ET.SubElement(off,'pkg-ref',{'id':'org.mail-filter.command-line.disabled'})
ET.SubElement(root,'title').text = 'Mail-Filter'
ET.SubElement(root,'welcome',{'file':'Welcome.html','mime-type':'text/html'})
ET.SubElement(root,'conclusion',{'file':'Finished.html','mime-type':'text/html'})
ET.SubElement(root,'domains',{'enable_localSystem':'true','enable_currentUserHome':'false','enable_anywhere':'false'})
tree.write(work/'Distribution.xml',encoding='utf-8',xml_declaration=True)
local = '<p><b>Local test build:</b> this package is not signed with Developer ID or notarized by Apple. Public distribution will use those protections.</p>' if sys.argv[2] == 'local' else ''
header = '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta http-equiv="Content-Type" content="text/html; charset=utf-8"></head><body style="font-family:-apple-system;font-size:14px">'
(work/'Resources/Welcome.html').write_text(header+'<h2>Mail-Filter</h2><p>Analyze incoming Apple Mail messages on your Mac and move verified political solicitations to Junk.</p><p>Requires macOS 26 or later, an Apple Intelligence-capable Mac, and Apple Intelligence enabled with the on-device model available.</p><p>This installer places Mail-Filter and Uninstall Mail-Filter in Applications. The optional command-line PATH entry can be added or removed during installation. It does not read or move messages, change account settings, enable extensions, or start a timer.</p>'+local+'</body></html>', encoding='utf-8')
(work/'Resources/Finished.html').write_text(header+'<h2>Next: open Mail-Filter</h2><ol><li>Open Mail-Filter from Applications.</li><li>Read Mail accounts, select the inboxes to filter, and save.</li><li>In Mail, open Settings, then Extensions, and enable Mail-Filter.</li></ol><p>If migrating, import your previous setup and protection records, leave any earlier filtering extension disabled, and keep the old timer stopped.</p><p>Keep Mail running and your Mac awake. The Mail-Filter settings app can quit; its window does not need to stay open.</p><p>Open a new Terminal window for command-line PATH changes to take effect. Existing development launchers are unchanged.</p><p>Use Uninstall Mail-Filter in Applications for removal. Existing private settings and protection records survive upgrades.</p></body></html>', encoding='utf-8')
PY
sign_options=()
[[ "$mode" == release ]] && sign_options=(--sign "$MAIL_FILTER_INSTALLER_IDENTITY" --timestamp)
productbuild --distribution "$work/Distribution.xml" --resources "$work/Resources" --package-path "$work" \
    "${sign_options[@]}" "$out/Mail-Filter Installer.pkg"
python3 "$root/MacApp/verify_package.py" "$out/Mail-Filter Installer.pkg"
print "Installer ready: $out/Mail-Filter Installer.pkg"
python3 "$root/MacApp/desktop_shortcut.py" "$out/Mail-Filter Installer.pkg"
if [[ "$mode" == release ]]; then
    print 'Next run MacApp/notarize.sh with your notarytool Keychain profile before distributing.'
else
    print 'Local test package only; not notarized for public distribution.'
fi
