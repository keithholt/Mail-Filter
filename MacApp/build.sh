#!/bin/zsh
set -eu
umask 022
root=${0:A:h:h}
mode=${1:-local}
[[ "$mode" == local || "$mode" == release ]] || { print -u2 'Usage: MacApp/build.sh [local|release]'; exit 1; }
identity=${MAIL_FILTER_SIGN_IDENTITY:--}
team=${MAIL_FILTER_TEAM_ID:-}
if [[ "$mode" == release ]]; then
    [[ "$identity" == 'Developer ID Application:'* && "$team" =~ '^[A-Z0-9]{10}$' ]] || {
        print -u2 'Release builds require MAIL_FILTER_SIGN_IDENTITY (Developer ID Application) and MAIL_FILTER_TEAM_ID.'
        exit 1
    }
fi
if [[ "$mode" == release ]]; then
    group="$team.org.mail-filter.shared"
else
    group=''
fi
out="$root/.build/mac-app"
app="$out/Mail-Filter.app"
ext="$app/Contents/PlugIns/Mail-Filter.appex"
uninstaller="$out/Uninstall Mail-Filter.app"
rm -rf "$app" "$uninstaller"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$ext/Contents/MacOS" "$uninstaller/Contents/MacOS" "$uninstaller/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/mail-filter-native-clang"
shared=("$root/Sources/MailFilter/Core.swift" "$root/MacApp/Shared/MIMEBodyDecoder.swift" "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift" "$root/MacApp/Shared/AnalysisDeadline.swift" "$root/MacApp/Shared/ClassificationRetry.swift" "$root/MacApp/SharedStore.swift")
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 \
    "${shared[@]}" "$root/Sources/MailFilter/MailAutomation.swift" \
    "$root/MacApp/AccountInventory.swift" "$root/MacApp/UninstallPlan.swift" "$root/MacApp/MessageDiagnostics.swift" "$root/MacApp/DiagnosticReport.swift" "$root/MacApp/SettingsModel.swift" "$root/MacApp/SettingsView.swift" "$root/MacApp/MailFilterApp.swift" \
    -framework AppKit -framework SwiftUI -o "$app/Contents/MacOS/MailFilter"
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 -application-extension -module-name MailFilterExtension \
    "${shared[@]}" "$root/MacApp/Shared/InspectionScheduler.swift" "$root/MacApp/Shared/BodyRequestTracker.swift" \
    "$root/MacApp/NativeClassifier.swift" "$root/MacApp/NativeExtension.swift" \
    -Xlinker -e -Xlinker _NSExtensionMain -framework Foundation -framework MailKit -framework AppKit \
    -o "$ext/Contents/MacOS/MailFilterExtension"
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 \
    "${shared[@]}" "$root/Sources/MailFilter/MailAutomation.swift" "$root/MacApp/UninstallPlan.swift" "$root/MacApp/UninstallerApp.swift" \
    -framework AppKit -framework SwiftUI -o "$uninstaller/Contents/MacOS/MailFilterUninstaller"
cp "$root/MacApp/Resources/filter.txt" "$root/MacApp/Resources/political-evidence.txt" "$app/Contents/Resources/"
developer="$app/Contents/Resources/DeveloperTools"
mkdir -p "$developer/bin" "$developer/libexec" "$developer/prompts" "$developer/config"
xcrun swiftc -O -swift-version 6 -parse-as-library -target arm64-apple-macos26.0 \
    "$root"/Sources/MailFilter/*.swift -framework AppKit -o "$developer/libexec/mail-filter"
cp "$root/prompts/filter.txt" "$root/prompts/political-evidence.txt" "$developer/prompts/"
cp "$root/config/accounts.example.txt" "$developer/config/"
cp "$root/README-DEVELOPER.md" "$developer/"
cat > "$developer/bin/mail-filter" <<'SH'
#!/bin/zsh
set -eu
export MAIL_FILTER_ROOT="${0:A:h:h}"
exec "$MAIL_FILTER_ROOT/libexec/mail-filter" "$@"
SH
xcrun swiftc "$root/MacApp/MakeIcon.swift" -o "$out/make-icon"
"$out/make-icon" "$out/AppIcon.iconset"
sips -s format icns "$out/AppIcon.iconset/icon_512x512.png" --out "$app/Contents/Resources/AppIcon.icns" >/dev/null
cp "$app/Contents/Resources/AppIcon.icns" "$uninstaller/Contents/Resources/"
python3 - "$app" "$ext" "$uninstaller" "$group" "$out" "$mode" <<'PY'
import plistlib, pathlib, sys
app, ext, uninstaller, group, out, mode = sys.argv[1:]
base = {'CFBundleDevelopmentRegion':'en','CFBundleShortVersionString':'2.0.0','CFBundleVersion':'10','LSMinimumSystemVersion':'26.0','MailFilterStorageMode':'app-group' if mode == 'release' else 'local-development','NSHighResolutionCapable':True}
if mode == 'release': base['MailFilterAppGroup'] = group
products = [
    (app, {'CFBundleIdentifier':'org.mail-filter.app','CFBundleName':'Mail-Filter','CFBundleExecutable':'MailFilter','CFBundlePackageType':'APPL','CFBundleIconFile':'AppIcon','NSAppleEventsUsageDescription':'Mail-Filter reads Mail account settings during setup, and reads one selected email when you request a read-only diagnostic test.'}),
    (ext, {'CFBundleIdentifier':'org.mail-filter.app.extension','CFBundleName':'Mail-Filter','CFBundleExecutable':'MailFilterExtension','CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.email.extension','NSExtensionPrincipalClass':'MailFilterExtension','NSExtensionAttributes':{'MEExtensionCapabilities':['MEMessageActionHandler']}}}),
    (uninstaller, {'CFBundleIdentifier':'org.mail-filter.uninstaller','CFBundleName':'Uninstall Mail-Filter','CFBundleExecutable':'MailFilterUninstaller','CFBundlePackageType':'APPL','CFBundleIconFile':'AppIcon'})]
for path, extra in products:
    with open(path+'/Contents/Info.plist','wb') as f: plistlib.dump(base|extra,f)
    for item in pathlib.Path(path).rglob('*'):
        item.chmod(0o755 if item.is_dir() else 0o644)
    pathlib.Path(path).chmod(0o755)
    pathlib.Path(path+'/Contents/MacOS/'+extra['CFBundleExecutable']).chmod(0o755)
for relative in ('bin/mail-filter','libexec/mail-filter'):
    (pathlib.Path(app)/'Contents/Resources/DeveloperTools'/relative).chmod(0o755)
for name, sandbox in [('Host',False),('Extension',True),('Uninstaller',False)]:
    entitlements = {'com.apple.security.application-groups':[group]} if mode == 'release' else {}
    if sandbox:
        entitlements['com.apple.security.app-sandbox'] = True
        if mode == 'local': entitlements['com.apple.security.temporary-exception.files.home-relative-path.read-write'] = ['/Library/Application Support/Mail-Filter Local/']
    elif name == 'Host': entitlements['com.apple.security.automation.apple-events'] = True
    with open(out+'/'+name+'.entitlements','wb') as f: plistlib.dump(entitlements,f)
with open(out+'/CLI.entitlements','wb') as f:
    plistlib.dump({'com.apple.security.automation.apple-events':True},f)
PY
sign_options=(--force --sign "$identity" --options runtime)
[[ "$mode" == release ]] && sign_options+=(--timestamp)
codesign "${sign_options[@]}" --entitlements "$out/Extension.entitlements" "$ext"
codesign "${sign_options[@]}" --entitlements "$out/CLI.entitlements" "$developer/libexec/mail-filter"
codesign "${sign_options[@]}" --entitlements "$out/Host.entitlements" "$app"
codesign "${sign_options[@]}" --entitlements "$out/Uninstaller.entitlements" "$uninstaller"
codesign --verify --deep --strict "$app"
codesign --verify --deep --strict "$uninstaller"
python3 "$root/MacApp/verify_bundle.py" "$app" "$uninstaller"
print "Built $mode native app and uninstaller in $out"
if [[ "$identity" == '-' ]]; then
    print 'Local test signing only. Public distribution requires Developer ID signing and notarization.'
fi
