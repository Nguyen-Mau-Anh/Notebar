#!/usr/bin/env bash
# NotebarCore must stay free of Apple UI frameworks so it can be ported.
# See spec section 3, rule 1.
set -euo pipefail

# Scoped to the NotebarCore *target*'s own directory, not the whole package:
# `Packages/NotebarCore/Sources/` also contains `NotebarStore`, which is
# expressly allowed platform-specific dependencies NotebarCore is not — it
# already depends on GRDB (Apple platforms + Linux, not Windows, per
# Package.swift's comment on that dependency) and, since the RTF note editor
# (spec §6.2), on AppKit for RTF encoding. NotebarStore was never a candidate
# for the M5 Windows port either target's rule is protecting; only
# NotebarCore is. The Package.swift dependency check further down already
# makes this same target-level distinction — this scoping keeps the import
# scan consistent with it instead of accidentally banning NotebarStore's
# legitimate dependencies.
CORE_TARGET_SOURCES="Packages/NotebarCore/Sources/NotebarCore/"

# These are never legitimate in NotebarCore, conditional or not: they are
# Apple-only UI frameworks with no counterpart on other platforms, so there is
# no #if canImport(...) that makes them acceptable here.
if grep -rnE '^[[:space:]]*import[[:space:]]+(AppKit|SwiftUI|UIKit|Cocoa|os|OSLog|Combine|CoreData|SwiftData|CryptoKit)' \
     "$CORE_TARGET_SOURCES" 2>/dev/null; then
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
       "$CORE_TARGET_SOURCES" 2>/dev/null || true)
  for file in $files_importing; do
    if ! grep -qE "#if[[:space:]]+canImport\(${module}\)" "$file"; then
      echo "ERROR: $file unconditionally imports ${module}." >&2
      echo "${module} is Apple-only and breaks the M5 Windows build (\"no such module\")." >&2
      echo "Guard it: #if canImport(${module}) / import ${module} / #endif" >&2
      exit 1
    fi
  done
done

# The two checks above only see source `import` lines. Neither one would
# notice a dependency declared in Package.swift itself — e.g. adding GRDB
# straight to the NotebarCore target — because nothing in that target's
# *source* would ever say `import AppKit`. That is exactly the mistake M1
# risked (see docs/superpowers/notes/2026-08-29-m1-risks.md item 4): GRDB
# targets Apple platforms and Linux, not Windows, so it must live in
# NotebarStore instead, behind the repository protocols NotebarCore defines.
# Parse Package.swift itself to catch that class of mistake mechanically,
# rather than trusting every future PR to remember the rule by hand.
PACKAGE_SWIFT="Packages/NotebarCore/Package.swift"
if [[ ! -f "$PACKAGE_SWIFT" ]]; then
  echo "ERROR: $PACKAGE_SWIFT not found — cannot check target dependencies." >&2
  exit 1
fi

python3 - "$PACKAGE_SWIFT" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path) as f:
    text = f.read()


def target_blocks(text):
    """Yield the full text of every `.target(...)` call (not `.testTarget(`),
    tracking paren depth so nested calls (e.g. swiftSettings) don't confuse
    where the target's own argument list ends."""
    blocks = []
    i = 0
    while True:
        idx = text.find(".target(", i)
        if idx == -1:
            break
        start = idx + len(".target")
        depth = 0
        j = start
        while j < len(text):
            c = text[j]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        blocks.append(text[idx:j])
        i = j
    return blocks


blocks = target_blocks(text)
core_block = next(
    (b for b in blocks if re.search(r'name:\s*"NotebarCore"', b)), None
)

if core_block is None:
    print(f"ERROR: could not find a `.target(name: \"NotebarCore\", ...)` "
          f"block in {path}.", file=sys.stderr)
    print("This check parses Package.swift textually and may need updating "
          "if the target was renamed or restructured.", file=sys.stderr)
    sys.exit(1)

deps_match = re.search(r'dependencies:\s*\[(.*?)\]', core_block, re.S)
if deps_match and deps_match.group(1).strip():
    print("ERROR: the NotebarCore target in Package.swift declares a "
          "dependency:", file=sys.stderr)
    print(file=sys.stderr)
    print(core_block.strip(), file=sys.stderr)
    print(file=sys.stderr)
    print("NotebarCore must have ZERO dependencies (spec section 3, rule 1). "
          "It exists so a Windows port (M5) can recompile it as-is; any "
          "dependency — even one that only targets Apple platforms and "
          "Linux, like GRDB — would need to resolve and build on Windows "
          "too, which breaks that plan even though this guard's source-"
          "import checks above would still print \"core purity: OK\".",
          file=sys.stderr)
    print("Put the dependency on NotebarStore (or another new target) "
          "instead, behind the repository protocols NotebarCore already "
          "defines. The NotebarCoreTests test target may depend on "
          "NotebarCore itself — that's a different rule and is fine.",
          file=sys.stderr)
    sys.exit(1)

print("Package.swift dependency check: OK")
PY

echo "core purity: OK"
