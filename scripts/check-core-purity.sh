#!/usr/bin/env bash
# NotebarCore must stay free of Apple UI frameworks so it can be ported.
# See spec section 3, rule 1.
set -euo pipefail

if grep -rnE '^[[:space:]]*import[[:space:]]+(AppKit|SwiftUI|UIKit)' \
     Packages/NotebarCore/Sources/ 2>/dev/null; then
  echo "ERROR: NotebarCore imports a UI framework (see above)." >&2
  echo "Move that code into the Notebar app target instead." >&2
  exit 1
fi

echo "core purity: OK"
