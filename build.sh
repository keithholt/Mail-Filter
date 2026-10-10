#!/bin/zsh
set -eu
cd "${0:A:h}"
swift build --build-system native -c release
print 'Built .build/release/mail-filter'
