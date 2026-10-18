#!/bin/zsh
set -eu
umask 022
root=${0:A:h:h}
mode=${1:-local}
[[ "$mode" == local || "$mode" == release ]] || { print -u2 'Usage: MacApp/build.sh [local|release]'; exit 1; }
identity=${MAIL_FILTER_SIGN_IDENTITY:--}
team=${MAIL_FILTER_TEAM_ID:-}
configuration=Local
signing=()
if [[ "$mode" == release ]]; then
    [[ "$identity" == 'Developer ID Application:'* && "$team" =~ '^[A-Z0-9]{10}$' ]] || {
        print -u2 'Release builds require MAIL_FILTER_SIGN_IDENTITY (Developer ID Application) and MAIL_FILTER_TEAM_ID.'
        exit 1
    }
    configuration=DeveloperID
    signing=(CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    [[ "$identity" == '-' ]] || { print -u2 'Local builds use ad hoc signing; use release for Developer ID signing.'; exit 1; }
fi
python3 "$root/MacApp/generate-project.py" --check
xcodebuild -project "$root/Mail-Filter.xcodeproj" -scheme 'Mail-Filter Local' \
    -configuration "$configuration" -destination 'generic/platform=macOS' \
    -derivedDataPath "$root/.build/xcode-derived" "${signing[@]}" build
python3 "$root/MacApp/prepare-direct-products.py" \
    "$root/.build/xcode-derived/Build/Products/$configuration" "$root/.build/mac-app" "$mode" "$identity"
print "Built $mode native app and uninstaller in $root/.build/mac-app"
[[ "$mode" != local ]] || print 'Local test signing only. Public distribution requires Developer ID signing and notarization.'
