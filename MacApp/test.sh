#!/bin/zsh
set -eu
root=${0:A:h:h}
out=$(mktemp -d "${TMPDIR:-/tmp}/mail-filter-native-tests.XXXXXX")
trap 'rm -rf "$out"' EXIT
export CLANG_MODULE_CACHE_PATH="$out/clang-cache"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$root/Sources/MailFilter/Core.swift" "$root/Sources/MailFilter/MailAutomation.swift" \
    "$root/MacApp/Shared/MIMEBodyDecoder.swift" "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift" \
    "$root/Sources/MailFilter/ClassificationRequest.swift" "$root/Sources/MailFilter/PoliticalModel.swift" "$root/MacApp/Shared/ClassificationRetry.swift" "$root/MacApp/SharedStore.swift" "$root/MacApp/Shared/AnalysisDeadline.swift" "$root/MacApp/MessageDiagnostics.swift" "$root/MacApp/SelectedEmailReport.swift" "$root/MacApp/AccountInventory.swift" "$root/MacApp/UninstallPlan.swift" \
    "$root/MacApp/Tests/NativeChecks.swift" -framework AppKit -o "$out/native-checks"
"$out/native-checks"
python3 "$root/MacApp/Tests/PackagingChecks.py"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$root/Sources/MailFilter/Core.swift" "$root/MacApp/Shared/MIMEBodyDecoder.swift" \
    "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift" \
    "$root/MacApp/SharedStore.swift" "$root/MacApp/DiagnosticReport.swift" \
    "$root/MacApp/Tests/DiagnosticChecks.swift" -o "$out/diagnostic-checks"
"$out/diagnostic-checks"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$root/MacApp/Shared/AnalysisDeadline.swift" "$root/MacApp/Shared/InspectionScheduler.swift" \
    "$root/MacApp/Tests/DeadlineChecks.swift" -o "$out/deadline-checks"
"$out/deadline-checks"
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 \
    "$root/Sources/MailFilter/Core.swift" "$root/Sources/MailFilter/ClassificationRequest.swift" "$root/MacApp/Shared/AnalysisDeadline.swift" \
    "$root/MacApp/Shared/ClassificationRetry.swift" "$root/MacApp/Shared/InspectionScheduler.swift" \
    "$root/MacApp/Tests/RetryChecks.swift" -o "$out/retry-checks"
"$out/retry-checks"
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

xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 \
    "$root/Sources/MailFilter/Core.swift" "$root/Sources/MailFilter/ClassificationRequest.swift" "$root/Sources/MailFilter/PoliticalModel.swift" \
    "$root/MacApp/Shared/MIMEBodyDecoder.swift" "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift" \
    "$root/MacApp/SharedStore.swift" "$root/MacApp/Tests/ModelRequestChecks.swift" -o "$out/model-request-checks"
"$out/model-request-checks"
