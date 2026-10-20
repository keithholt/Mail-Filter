#!/bin/zsh
set -eu
root=${0:A:h:h}
mode=${1:-check}
[[ "$mode" == check || "$mode" == development || "$mode" == archive || "$mode" == export ]] || {
    print -u2 'Usage: MacApp/store-build.sh [check|development|archive|export]'; exit 1
}
python3 "$root/MacApp/generate-project.py" --check
destination='generic/platform=macOS'
[[ "$mode" != development ]] || destination='platform=macOS,arch=arm64,name=My Mac'
args=(-project "$root/Mail-Filter.xcodeproj" -scheme 'Mail-Filter Store' -destination "$destination" -derivedDataPath "$root/.build/xcode-derived")
if [[ "$mode" == check ]]; then
    # Compile the actual Store payload without claiming that it is signed or runnable.
    # Xcode records built apps with Launch Services. Use isolated development
    # identities even though this checks the Store configuration and archive.
    xcodebuild "${args[@]}" -configuration Store archive -archivePath "$root/.build/store-unsigned.xcarchive" CODE_SIGNING_ALLOWED=NO \
        MAIL_FILTER_BUNDLE_ID=org.mail-filter.development MAIL_FILTER_APP_GROUP=group.org.mail-filter.development.shared MAIL_FILTER_DISPLAY_NAME='Mail-Filter Build Check'
    python3 "$root/MacApp/Store/verify.py" "$root/.build/store-unsigned.xcarchive/Products/Applications/Mail-Filter.app" --unsigned --development
    python3 "$root/MacApp/Tests/StorePackagingChecks.py" "$root/.build/store-unsigned.xcarchive/Products/Applications/Mail-Filter.app"
else
    team=${MAIL_FILTER_TEAM_ID:-}
    [[ "$team" =~ '^[A-Z0-9]{10}$' ]] || { print -u2 'Set MAIL_FILTER_TEAM_ID after developer enrollment.'; exit 1; }
    if [[ "$mode" == development ]]; then
        xcodebuild "${args[@]}" -configuration Development -allowProvisioningUpdates -allowProvisioningDeviceRegistration build DEVELOPMENT_TEAM="$team"
        python3 "$root/MacApp/Store/verify.py" "$root/.build/xcode-derived/Build/Products/Development/Mail-Filter.app" --development
    elif [[ "$mode" == archive ]]; then
        archive="$root/outputs/store/Mail-Filter.xcarchive"
        [[ ! -e "$archive" ]] || { print -u2 'Preserve or move the existing outputs/store/Mail-Filter.xcarchive first.'; exit 1; }
        xcodebuild "${args[@]}" -configuration Store -allowProvisioningUpdates archive -archivePath "$archive" DEVELOPMENT_TEAM="$team"
        python3 "$root/MacApp/Store/verify.py" "$archive/Products/Applications/Mail-Filter.app" --archive
    else
        archive="$root/outputs/store/Mail-Filter.xcarchive"
        python3 "$root/MacApp/Store/verify.py" "$archive/Products/Applications/Mail-Filter.app" --archive
        [[ ! -e "$root/outputs/store/export" ]] || { print -u2 'Preserve or move the existing outputs/store/export first.'; exit 1; }
        python3 - "$root/MacApp/Store/ExportOptions.plist" "$root/.build/store-export-options.plist" "$team" <<'PY'
import pathlib, plistlib, sys
options = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
options['teamID'] = sys.argv[3]
pathlib.Path(sys.argv[2]).write_bytes(plistlib.dumps(options))
PY
        xcodebuild -allowProvisioningUpdates -exportArchive -archivePath "$archive" -exportPath "$root/outputs/store/export" -exportOptionsPlist "$root/.build/store-export-options.plist"
        python3 "$root/MacApp/Store/verify-export.py" "$root/outputs/store/export"
    fi
fi
print 'No installation, extension activation or submission was performed.'
