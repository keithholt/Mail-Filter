#!/bin/zsh
set -eu
cd "${0:A:h}"
# Some Command Line Tools versions fail to discover the bundled Testing macro.
testing_plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
    swift test -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin"
else
    swift test
fi
