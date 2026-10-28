#!/bin/zsh
set -eu
root=${0:A:h:h}
[[ $# -eq 1 || $# -eq 2 ]] || { print -u2 'Usage: MacApp/probe-model-queue.sh NEW_OUTPUT_DIRECTORY [PACING_GAP_SECONDS]'; exit 2; }
out=$(mktemp -d "${TMPDIR:-/tmp}/mail-filter-queue-probe.XXXXXX")
trap 'rm -rf "$out"' EXIT
export CLANG_MODULE_CACHE_PATH="$out/clang-cache"
# Capture historical request text as data, not executable source. The JSON output
# is private experiment material and is never added to a shipping resource.
python3 - "$root" "$out/legacy.json" <<'PY'
import hashlib,json,subprocess,sys,textwrap
from pathlib import Path
root=Path(sys.argv[1])
def read(path): return subprocess.check_output(['git','show','00b9e1c:'+path],cwd=root,text=True)
core=read('Sources/MailFilter/Core.swift')
function=core.split('func politicalClassificationInstructions(',1)[1].split('\nfunc parseClassification',1)[0]
tail=function.split('rules + """\n',1)[1].rsplit('\n    """',1)[0]
tail=textwrap.dedent(tail)
terms=[s.strip() for s in read('prompts/political-evidence.txt').splitlines() if s.strip() and not s.strip().startswith('#')]
tail=tail.replace('\\(evidenceTerms.joined(separator: ", "))',', '.join(terms))
rules=read('prompts/filter.txt').strip()
payload={'commit':'00b9e1c','instructions':rules+tail,'rules':rules,'sourceSHA256':hashlib.sha256(core.encode()).hexdigest()}
Path(sys.argv[2]).write_text(json.dumps(payload))
PY
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos27.0 \
  "$root/Sources/MailFilter/Core.swift" "$root/Sources/MailFilter/ClassificationRequest.swift" "$root/Sources/MailFilter/PoliticalModel.swift" \
  "$root/MacApp/Shared/MIMEBodyDecoder.swift" "$root/MacApp/Shared/FilteringConfiguration.swift" "$root/MacApp/Shared/JunkProtection.swift" \
  "$root/MacApp/Shared/AnalysisDeadline.swift" "$root/MacApp/Shared/ClassificationRetry.swift" "$root/MacApp/Shared/InspectionScheduler.swift" \
  "$root/MacApp/SharedStore.swift" "$root/MacApp/Shared/ModelEnvironment.swift" "$root/MacApp/NativeClassifier.swift" "$root/MacApp/Tests/ModelQueueProbe.swift" -o "$out/queue-probe"
"$out/queue-probe" "$1" "$out/legacy.json" "${2:-10}"
