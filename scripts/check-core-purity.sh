#!/usr/bin/env bash
# NotebarCore must stay free of Apple UI frameworks so it can be ported.
# See spec section 3, rule 1.
set -euo pipefail

# These are never legitimate in NotebarCore, conditional or not: they are
# Apple-only UI frameworks with no counterpart on other platforms, so there is
# no #if canImport(...) that makes them acceptable here.
if grep -rnE '^[[:space:]]*import[[:space:]]+(AppKit|SwiftUI|UIKit|Cocoa)' \
     Packages/NotebarCore/Sources/ 2>/dev/null; then
  echo "ERROR: NotebarCore imports a UI framework (see above)." >&2
  echo "AppKit/SwiftUI/UIKit/Cocoa are Apple-only and have no place in this package." >&2
  echo "Move that code into the Notebar app target instead." >&2
  exit 1
fi

# CoreGraphics and QuartzCore are Apple-only too: they don't exist on
# Linux/Windows Swift toolchains, where swift-corelibs-foundation defines its
# own CGFloat/CGPoint/CGRect inside Foundation instead. An unconditional
# import compiles fine on macOS today but fails the M5 "recompile NotebarCore
# under Swift for Windows" milestone with "no such module". They may only be
# imported behind a matching #if canImport(...) guard in the same file, so the
# module falls back to Foundation's types on platforms where they're missing.
for module in CoreGraphics QuartzCore; do
  files_importing=$(grep -rlE "^[[:space:]]*import[[:space:]]+${module}\b" \
       Packages/NotebarCore/Sources/ 2>/dev/null || true)
  for file in $files_importing; do
    if ! grep -qE "#if[[:space:]]+canImport\(${module}\)" "$file"; then
      echo "ERROR: $file unconditionally imports ${module}." >&2
      echo "${module} is Apple-only and breaks the M5 Windows build (\"no such module\")." >&2
      echo "Guard it: #if canImport(${module}) / import ${module} / #endif" >&2
      exit 1
    fi
  done
done

echo "core purity: OK"
