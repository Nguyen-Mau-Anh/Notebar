#!/usr/bin/env bash
# Notebar.Core must stay pure: no UI, no platform types, no I/O, no packages.
# A single stray using directive is all it takes to end that, and the failure
# is silent until someone tries to build somewhere new.
set -euo pipefail

cd "$(dirname "$0")/.."
FAIL=0

# 1. The project file must declare no PackageReference and no ProjectReference.
if grep -qE '<(Package|Project)Reference' Notebar.Core/Notebar.Core.csproj; then
  echo "FAIL: Notebar.Core.csproj declares a reference. The core takes none."
  grep -nE '<(Package|Project)Reference' Notebar.Core/Notebar.Core.csproj
  FAIL=1
fi

# 2. Allowlist, not denylist. Three bypasses (a `=` alias, `using static`, and
#    a `global::` prefix) each slipped a denylist that enumerated forbidden
#    namespaces, because the set of spellings is open-ended and the set of
#    things the core legitimately needs is not. Anything not named here fails,
#    however it is written.
# Scoped away from bin/ and obj/: with ImplicitUsings enabled (Directory.Build.props),
# the SDK generates its own GlobalUsings.g.cs under obj/ that legitimately includes
# System.IO and System.Net.Http — that's the .NET SDK's own default, not a developer
# import, and scanning it produces a false positive on every build.
ALLOWED='^\s*(global\s+)?using\s+(static\s+)?(global::)?(System|System\.Collections\.Generic|System\.Collections\.Immutable|System\.Linq|System\.Text|System\.Globalization|Notebar\.Core(\.[A-Za-z0-9_]+)*)\s*;'
# Two-stage, not one grep piped into another: grep -rn's output is
# "file:line:content", so filtering that combined string against a pattern
# anchored at `^using` never matches anything — every result would look like
# a violation, including every legitimate import. Strip the "file:line:"
# prefix per match before testing it against ALLOWED.
ALLOWLIST_FAIL=0
while IFS= read -r match; do
  [ -z "$match" ] && continue
  content="${match#*:*:}"
  if ! printf '%s\n' "$content" | grep -qE "$ALLOWED"; then
    echo "$match"
    ALLOWLIST_FAIL=1
  fi
done < <(grep -rEn '^\s*(global\s+)?using\s' Notebar.Core --include='*.cs' --exclude-dir=bin --exclude-dir=obj || true)
if [ "$ALLOWLIST_FAIL" -eq 1 ]; then
  echo "FAIL: Notebar.Core imports something outside its allowlist (see above)."
  echo "      Permitted: System, System.Collections.Generic, System.Collections.Immutable,"
  echo "      System.Linq, System.Text, System.Globalization, and Notebar.Core.*"
  echo "      If the core genuinely needs something else, that is a design decision,"
  echo "      not a guard problem — raise it rather than widening this list."
  FAIL=1
fi

# 3. Fully-qualified use bypasses the using check, so catch the common ones too.
QUALIFIED='(System\.IO\.File|System\.IO\.Directory|System\.Net\.|Microsoft\.UI\.|Windows\.UI\.|Microsoft\.Win32\.)'
if grep -rEn "$QUALIFIED" Notebar.Core --include='*.cs' --exclude-dir=bin --exclude-dir=obj ; then
  echo "FAIL: fully-qualified platform type used in Notebar.Core (see above)."
  FAIL=1
fi

# 4. A bare assembly reference bypasses check 1's Package/Project grep entirely.
if grep -qE '<Reference\s' Notebar.Core/Notebar.Core.csproj; then
  echo "FAIL: Notebar.Core.csproj declares a bare <Reference>. The core takes none."
  grep -nE '<Reference\s' Notebar.Core/Notebar.Core.csproj
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "OK: Notebar.Core is pure."
fi
exit "$FAIL"
