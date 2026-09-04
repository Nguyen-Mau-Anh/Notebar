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

# 2. No forbidden namespace may be imported anywhere in the core.
# Scoped away from bin/ and obj/: with ImplicitUsings enabled (Directory.Build.props),
# the SDK generates its own GlobalUsings.g.cs under obj/ that legitimately includes
# System.IO and System.Net.Http — that's the .NET SDK's own default, not a developer
# import, and scanning it produces a false positive on every build.
FORBIDDEN='^\s*(global\s+)?using\s+(Microsoft\.UI|Microsoft\.Win32|Microsoft\.Data|Windows\.|WinRT|System\.Drawing|System\.IO|System\.Net|System\.Windows)'
if grep -rEn "$FORBIDDEN" Notebar.Core --include='*.cs' --exclude-dir=bin --exclude-dir=obj ; then
  echo "FAIL: forbidden using directive in Notebar.Core (see above)."
  FAIL=1
fi

# 3. Fully-qualified use bypasses the using check, so catch the common ones too.
QUALIFIED='(System\.IO\.File|System\.IO\.Directory|System\.Net\.|Microsoft\.UI\.|Windows\.UI\.)'
if grep -rEn "$QUALIFIED" Notebar.Core --include='*.cs' --exclude-dir=bin --exclude-dir=obj ; then
  echo "FAIL: fully-qualified platform type used in Notebar.Core (see above)."
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "OK: Notebar.Core is pure."
fi
exit "$FAIL"
