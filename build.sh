#!/bin/zsh
set -eu
cd "${0:A:h}"
print 'Regenerating Word docs from Markdown...'
python3 docs/build-docx.py
swift build --build-system native -c release
print 'Built .build/release/mail-filter'
