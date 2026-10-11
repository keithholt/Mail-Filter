#!/bin/zsh
set -eu
root=${0:A:h:h}
out=$(mktemp -d "${TMPDIR:-/tmp}/mail-filter-native-tests.XXXXXX")
trap 'rm -rf "$out"' EXIT
export CLANG_MODULE_CACHE_PATH="$out/clang-cache"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$root/Sources/MailFilter/Core.swift" "$root/Sources/MailFilter/MailAutomation.swift" \
    "$root/MacApp/Shared/MIMEBodyDecoder.swift" "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift" \
    "$root/MacApp/SharedStore.swift" "$root/MacApp/AccountInventory.swift" "$root/MacApp/UninstallPlan.swift" \
    "$root/MacApp/Tests/NativeChecks.swift" -framework AppKit -o "$out/native-checks"
"$out/native-checks"
python3 "$root/MacApp/Tests/PackagingChecks.py"
xcrun swiftc -swift-version 5 -parse-as-library -application-extension \
    "$root/MacApp/Shared/MIMEBodyDecoder.swift" "$root/MacApp/Shared/BodyRequestTracker.swift" \
    "$root/MacApp/Tests/MIMEBodyChecks.swift" -o "$out/mime-checks"
"$out/mime-checks"
shared=("$root/Sources/MailFilter/Core.swift" "$root/MacApp/Shared/MIMEBodyDecoder.swift" \
    "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift")
xcrun swiftc -swift-version 5 -parse-as-library -application-extension \
    "${shared[@]}" "$root/MacApp/Shared/InspectionScheduler.swift" \
    "$root/MacApp/Tests/FilteringChecks.swift" -o "$out/filtering-checks"
"$out/filtering-checks"
xcrun swiftc -swift-version 5 -parse-as-library -application-extension \
    "${shared[@]}" "$root/MacApp/Tests/JunkProtectionChecks.swift" -o "$out/protection-checks"
"$out/protection-checks"
