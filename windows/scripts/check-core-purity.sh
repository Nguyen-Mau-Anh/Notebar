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
QUALIFIED='(System\.IO\.File|System\.IO\.Directory|System\.Net\.|Microsoft\.UI\.|Windows\.UI\.|Microsoft\.Win32\.)'
if grep -rEn "$QUALIFIED" Notebar.Core --include='*.cs' --exclude-dir=bin --exclude-dir=obj ; then
  echo "FAIL: fully-qualified platform type used in Notebar.Core (see above)."
  FAIL=1
fi

# 4. A using alias hides the aliased namespace from every check above:
#    `using IO = System.IO;` puts IO after `using`, so check 2's namespace grep
#    misses it, and code written against it never contains the literal
#    `System.IO.File` check 3 looks for. One line defeated the whole guard.
ALIAS='^\s*(global\s+)?using\s+[A-Za-z_][A-Za-z0-9_]*\s*='
if grep -rEn "$ALIAS" Notebar.Core --include='*.cs' --exclude-dir=bin --exclude-dir=obj; then
  echo "FAIL: using alias in Notebar.Core (see above). An alias hides the aliased"
  echo "      namespace from every other check here; write the namespace out instead."
  FAIL=1
fi

# 5. A bare assembly reference bypasses check 1's Package/Project grep entirely.
if grep -qE '<Reference\s' Notebar.Core/Notebar.Core.csproj; then
  echo "FAIL: Notebar.Core.csproj declares a bare <Reference>. The core takes none."
  grep -nE '<Reference\s' Notebar.Core/Notebar.Core.csproj
  FAIL=1
fi

# 6. `using static System.IO.Path;` slips checks 2-5: check 2 needs the
#    namespace immediately after `using` and `static` intervenes; check 3 greps
#    only File/Directory literals, so Path, Stream, StreamReader, BinaryWriter
#    and friends pass unseen. Same hole as check 4, reached via static.
USING_STATIC='^\s*(global\s+)?using\s+static\s+(Microsoft\.UI|Microsoft\.Win32|Microsoft\.Data|Windows\.|WinRT|System\.Drawing|System\.IO|System\.Net|System\.Windows)'
if grep -rEn "$USING_STATIC" Notebar.Core --include='*.cs' --exclude-dir=bin --exclude-dir=obj; then
  echo "FAIL: using static of a forbidden namespace in Notebar.Core (see above)."
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "OK: Notebar.Core is pure."
fi
exit "$FAIL"
