#!/bin/zsh
set -eu
root=${0:A:h:h}
out=$(mktemp -d "${TMPDIR:-/tmp}/mail-filter-model-probe.XXXXXX")
trap 'rm -rf "$out"' EXIT
export CLANG_MODULE_CACHE_PATH="$out/clang-cache"
export MAIL_FILTER_ROOT="${MAIL_FILTER_ROOT:-$root}"
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 \
    "$root/Sources/MailFilter/Core.swift" "$root/Sources/MailFilter/ClassificationRequest.swift" "$root/Sources/MailFilter/PoliticalModel.swift" \
    "$root/MacApp/Shared/AnalysisDeadline.swift" "$root/MacApp/Shared/ClassificationRetry.swift" \
    "$root/MacApp/Shared/ModelEnvironment.swift" "$root/MacApp/LocalModelReplay.swift" "$root/MacApp/ModelProbe.swift" -o "$out/model-probe"
"$out/model-probe" "$@"
