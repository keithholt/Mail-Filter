#!/bin/zsh
set -eu
root=${0:A:h:h}
out=$(mktemp -d "${TMPDIR:-/tmp}/mail-filter-timing.XXXXXX")
trap 'rm -rf "$out"' EXIT
export CLANG_MODULE_CACHE_PATH="$out/clang-cache"
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 \
  "$root/Sources/MailFilter/Core.swift" "$root/Sources/MailFilter/ClassificationRequest.swift" "$root/Sources/MailFilter/PoliticalModel.swift" \
  "$root/MacApp/Shared/MIMEBodyDecoder.swift" "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift" \
  "$root/MacApp/Shared/AnalysisDeadline.swift" "$root/MacApp/Shared/ClassificationRetry.swift" "$root/MacApp/Shared/InspectionScheduler.swift" \
  "$root/MacApp/SharedStore.swift" "$root/MacApp/NativeClassifier.swift" "$root/MacApp/Tests/TimingQualification.swift" -o "$out/timing-checks"
"$out/timing-checks" "$@"
