# MSIX packaging: what was tried, and what to try next

Notebar for Windows ships a portable zip. MSIX packaging was attempted 15 times
across the milestone and never produced a valid package — every run wrote a
`package.map.txt` containing only its `[Files]` header and no payload, and MakeAppx
then failed with 0x80080203, "no valid AppxManifest.xml in the source".

This file exists because that investigation cost 15 CI runs and lived only in a
gitignored working file. Everything below is evidence, not speculation.

## Leads, ranked

This is the authoritative lead list — it supersedes any partial or hedged version of these leads
mentioned earlier in this report's blow-by-blow history above.

**Lead #1 — `WindowsPackageType=MSIX` itself is the most likely culprit, not any property supplied
alongside it.** The most valuable finding from the whole task: across all 13 CI runs,
`RuntimeIdentifier` is honoured — real RID-suffixed output, a working self-contained build — under
`WindowsPackageType=None` (the portable-zip step, green every run since `e5209c6`), and silently
ignored under `WindowsPackageType=MSIX` (`Package MSIX`, every run), regardless of how it's supplied:
via a `PublishProfile` (`.pubxml`, run
[33846275223](https://github.com/Nguyen-Mau-Anh/Notebar/actions/runs/33846275223)), as an explicit
`/p:RuntimeIdentifier` with `/p:SelfContained=true` (run
[33846700356](https://github.com/Nguyen-Mau-Anh/Notebar/actions/runs/33846700356)), or as an explicit
`/p:RuntimeIdentifier` without `SelfContained` (run
[33847340373](https://github.com/Nguyen-Mau-Anh/Notebar/actions/runs/33847340373)) — the build
output path stays `net9.0-windows10.0.22621.0\` (no RID suffix) in every MSIX attempt, never
`...\win-x64\`. That is property-*level* behaviour (the same property, honoured or ignored purely
based on which `WindowsPackageType` value is active), not a configuration-file or entry-point
problem — which is why every combination of `.csproj`/`.sln`, `Build`/`Publish`,
`dotnet build`/`msbuild.exe`, and WindowsAppSDK `2.4.0`/`1.7.260224002` produced the identical empty
`package.map.txt`. `<WindowsPackageType>MSIX</WindowsPackageType>` was added to `Notebar.App.csproj`
on the team lead's own initiative during round 1 (commit `17a11b7`'s brief) and is **not** part of
the standard WinUI single-project MSIX template documented at
`learn.microsoft.com/windows/apps/windows-app-sdk/single-project-msix` — that template relies on
`EnableMsixTooling=true` alone to imply a packaged app. Worth trying first for Task 16: remove
`WindowsPackageType=MSIX` from `Notebar.App.csproj` (keeping `EnableMsixTooling=true`) and rerun the
`Package MSIX` step's command as-is.

**Lead #2 — the `Notebar.Core` `ProjectReference` (untested).** `Notebar.Core` is a plain `net9.0`
classlib (not `net9.0-windows...`) referenced via `ProjectReference` from the packaged WinUI app.
`microsoft/WindowsAppSDK` discussion #3749 describes a WinUI-class-library reference breaking
single-project MSIX packaging from the CLI specifically — though that discussion's own stated fix
(`EnableMsixTooling=false` on the library) doesn't directly apply here, since `Notebar.Core.csproj`
never sets `EnableMsixTooling` at all. Never isolated across all 13 runs: temporarily remove the
`ProjectReference` (and the one line in `PanelWindow.xaml.cs` that uses it) to test whether a
dependency-free `Notebar.App` packages cleanly.

**Ruled out, do not re-try:** the WindowsAppSDK major version (`2.4.0` vs `1.7.260224002`, identical
failure both); the solution-configuration hypothesis (`windows/Notebar.sln` already has a correctly
mapped `Release|x64` — confirmed and withdrawn by the team lead, see "Correction 2" above);
`RuntimeIdentifier`/`SelfContained` supplied via publish profile vs explicit command-line property
(both silently ignored under `WindowsPackageType=MSIX`, which is exactly Lead #1).

## One more attempt was made after that list was written

Lead #1 was tried during Task 16: `<WindowsPackageType>MSIX</WindowsPackageType>` was
removed from `Notebar.App.csproj`. The result confirmed the *mechanism* without fixing
the symptom — `RuntimeIdentifier` was finally honoured (a RID-suffixed output path, for
the first time in any MSIX run) and the payload was still empty. So the property was
genuinely suppressing the RID, and something else also has to be wrong. Lead #2 is
still untested.

## A trap the release itself fell into

`windows-v0.1.0` briefly shipped a file named `Notebar-x64.msix` that was actually the
Windows App SDK's own framework package — `Microsoft.WindowsAppRuntime.Release 1.7.224`,
containing `PushNotificationsLongRunningTask.exe` and no Notebar executable. The
collection step used `find windows/Notebar.App -name '*.msix'`, and NuGet restores that
framework package into the same tree.

The step reported success. The guard checked that a file existed, never that it was the
right file. Both workflows now restrict by path *and* name *and* verify the archive
contains `Notebar.App.exe` before copying — and the manual-check list carries a line to
open any future `.msix` and confirm what is inside it.
