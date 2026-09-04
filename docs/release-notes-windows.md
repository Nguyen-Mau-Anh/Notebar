## Notebar for Windows

The first Windows build: a WinUI 3 / C# port of the same panel, notes, tasks, and settings
the macOS app has, built from scratch against the same design rather than shared code.

**Notebar for Windows and Notebar for macOS keep entirely separate databases and do not
sync.** A note written on one is not visible on the other. If you use both, treat them as
two different notebooks, not one that follows you across machines.

### Requirements

- **Windows 11, version 22H2 or later, x64.** That's what this build was built and tested
  against (`TargetPlatformMinVersion` 10.0.22621). Whether it actually refuses to start on
  an older Windows has not been verified — this is what was targeted, not a guarantee of
  what happens below it.
- **The Microsoft Edge WebView2 Runtime.** The note editor is a WebView2 control, and
  without the runtime installed, opening a note will fail to start. It ships preinstalled
  with Windows 11 and current Windows 10, so most people already have it and don't need to
  do anything. If Notebar fails the first time you open a note, install the
  [Evergreen WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/#download-section)
  from Microsoft and try again.

### Install: unzip and run

Download `Notebar-portable-x64.zip` from this release, unzip it anywhere, and run
`Notebar.App.exe`. That's it — no installer, no admin rights needed.

**Windows SmartScreen will warn you** the first time you run it: "Windows protected your
PC." Click **More info**, then **Run anyway**. This is expected, not a sign anything is
wrong.

### Why it's unsigned

That SmartScreen warning exists because this build isn't signed with an EV code-signing
certificate. Those certificates cost several hundred dollars a year, and — unlike Apple
notarization on the macOS build — a signature isn't *required* for the app to run on
Windows; it only removes the one-time warning. For a small open-source utility, that isn't
a cost worth carrying yet. Signing may come later if that changes.

### Alternative: the MSIX package

If `Notebar-x64.msix` is attached to this release, you can install it instead of running
the portable build directly. It's also unsigned, so it can't be installed by double-clicking
— Windows refuses to install an unsigned package that way, and refuses `-AllowUnsigned`
from an ordinary PowerShell window too, since the package contains executable content.
**Open PowerShell as Administrator** (right-click the Start menu → *Terminal (Admin)*, or
search "PowerShell", right-click it, and choose *Run as administrator*), then run:

```powershell
Add-AppxPackage -Path .\Notebar-x64.msix -AllowUnsigned
```

Running that same command from a non-elevated PowerShell fails with an access-denied error
— that's expected, and elevating is the fix, not a sign the package itself is broken.

If no `.msix` is attached to this release, MSIX packaging didn't succeed for this build —
the portable zip above is the supported path, needs no elevation, and needs no special
command at all.

### Known difference from macOS: exclusive fullscreen

On macOS, the panel draws over everything, including fullscreen apps. On Windows, it draws
over maximized windows and borderless-fullscreen windows (most video players, most modern
games running in "fullscreen" that's really borderless) — but **not** over a window running
in true exclusive fullscreen mode. That's a rule the Windows window manager enforces itself,
not a limitation Notebar chose; working around it would require the kind of low-level
display hooks this project deliberately avoids for anything else, too.

### What hasn't been verified yet

This build compiles and passes its automated tests in CI, but almost nothing about how it
actually *feels* to use has been confirmed on a real Windows machine yet — this project was
built entirely from a Mac, which cannot run WinUI 3 at all. If something looks or behaves
oddly, check
[`docs/superpowers/notes/2026-09-04-windows-manual-checks.md`](https://github.com/Nguyen-Mau-Anh/Notebar/blob/main/docs/superpowers/notes/2026-09-04-windows-manual-checks.md)
first — it's the running list of exactly what still needs a human to confirm, organized by
area (window behaviour, the panel's hover/collapse timing, the tray icon, the editor,
notes, formatting, tasks, linking, and Settings). If you hit something that isn't already on
that list, please file an issue.

### Feedback

This is an early build. If you run into something broken, confusing, or just worse than the
macOS app, [open an issue](https://github.com/Nguyen-Mau-Anh/Notebar/issues) — ideally with
Settings → Data → **Export Diagnostics** attached, which never includes your note or task
content, only version, environment, and database facts.
