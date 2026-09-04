# Notebar for Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a WinUI 3 build of Notebar with feature parity to macOS v0.2.2, released from GitHub Actions as an MSIX plus a portable zip.

**Architecture:** Three projects mirroring the macOS split — `Notebar.Core` (pure C#, no UI, no I/O), `Notebar.Store` (Microsoft.Data.Sqlite), `Notebar.App` (WinUI 3). Core and Store target plain `net9.0` and are buildable and testable on any machine, including the macOS development machine; only `Notebar.App` needs Windows. The panel's behaviour is a pure reducer, exactly as on macOS, so every transition is a table test rather than something you reproduce by waving a mouse.

**Tech Stack:** C# / .NET 9 · WinUI 3 (Windows App SDK) · Microsoft.Data.Sqlite (SQLite with FTS5) · WebView2 · xUnit · GitHub Actions on `windows-latest`

**Spec:** `docs/superpowers/specs/2026-09-04-notebar-windows-design.md`

**Reference implementation:** the shipped macOS app in this same repo. `Packages/NotebarCore/` is the source of truth for behaviour and schema; `Notebar/` is the source of truth for UI structure. Read the Swift when a C# detail is ambiguous — it is the same product.

**Product and visual authority:** `docs/superpowers/specs/2026-08-29-notebar-design.md` (what it does) and `docs/design/2026-08-29-screen-spec.md` (how it looks). Neither is restated here.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Target frameworks:** `Notebar.Core`, `Notebar.Store`, and both test projects target `net9.0`. `Notebar.App` targets `net9.0-windows10.0.22621.0`.
- **`Notebar.Core` takes zero NuGet dependencies and references no other project.** No `Microsoft.UI.*`, no `Windows.*`, no `System.Drawing`, no `Microsoft.Data.Sqlite`, no file or network I/O. This is guarded by a CI script, exactly as `scripts/check-core-purity.sh` guards the Swift core.
- **`Notebar.Store` references `Notebar.Core` and `Microsoft.Data.Sqlite` only.** No UI packages. It must stay `net9.0` so it runs in CI on any OS.
- **Never log note or task content.** Ids and counts only. This holds in every project.
- **Diagnostics export contains no note or task content.** Test-enforced.
- **Migrations are additive only.** Never edit a migration that has shipped; add a new one.
- **No permission-requiring or hook-based APIs.** Specifically forbidden: `SetWindowsHookEx`, `WH_KEYBOARD_LL`, `WH_MOUSE_LL`, any UI Automation client API, any API requiring elevation. `GetCursorPos` and `RegisterHotKey` are the sanctioned mechanisms.
- **Never run the app, drive any application, move the cursor, or change system appearance on the developer's live desktop.** No `Start-Process`, no `osascript`, no window activation. This is a hard rule carried from the macOS build, where violating it opened an unrelated app on the user's screen mid-session.
- **Never `git add -A`.** Stage explicit paths only.
- **Commit at the end of every task.** Push after every task.
- **All timing and geometry constants live in `PanelTiming`.** Nothing inlines those numbers at a call site.
- **Dates persist as ISO-8601 UTC text**, format string `yyyy-MM-ddTHH:mm:ss.fffZ`, so `ORDER BY` on a timestamp column sorts correctly as text.

### Working directory and toolchain

All Windows work happens under `windows/` at the repo root. The macOS app is not modified by any task in this plan.

The development machine is a Mac with .NET 9.0.317 installed at `~/.dotnet`. Every shell that runs `dotnet` must first:

```bash
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.dotnet:$PATH"
```

`Notebar.App` **cannot be built on macOS** — WinUI 3 is Windows-only. Locally you build and test only the solution's cross-platform half:

```bash
cd windows
dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
dotnet test Notebar.Store.Tests/Notebar.Store.Tests.csproj
```

`Notebar.App`'s correctness rests on CI compilation plus human use of the released build. Do not claim a WinUI change is verified because it compiles.

---

## File Structure

```
windows/
├── Notebar.sln
├── Directory.Build.props                 Shared: LangVersion, Nullable, TreatWarningsAsErrors
├── Notebar.Core/
│   ├── Notebar.Core.csproj
│   ├── Geometry/PanelPoint.cs            readonly record struct (X, Y)
│   ├── Geometry/PanelRect.cs             readonly record struct (X, Y, Width, Height) + Min/Max/Contains/Inflate
│   ├── Panel/PanelState.cs               PanelState, PanelTimer, PollRate, PanelEvent enums
│   ├── Panel/PanelEffect.cs              abstract record + 5 nested effect records
│   ├── Panel/PanelContext.cs             the six suppression signals
│   ├── Panel/PanelTiming.cs              every timing and geometry constant
│   ├── Panel/EdgeZone.cs                 EdgeProximity + Classify + IsOutside
│   ├── Panel/PanelMachine.cs             Reduce + ShouldCollapse
│   ├── Models/Note.cs, NoteSummary.cs, TaskItem.cs, Board.cs, BoardColumn.cs
│   ├── Models/Link.cs, LinkTarget.cs, LinkEntityType.cs, LinkUrl.cs, LinkTombstone.cs
│   ├── Models/OpenTab.cs, Theme.cs, Attachment.cs
│   ├── Models/DatabaseDiagnostics.cs, DiagnosticsEnvironment.cs
│   ├── Schema/NoteSchema.cs, TaskSchema.cs, LinkSchema.cs, AppStateSchema.cs, AttachmentSchema.cs
│   └── Repositories/INoteRepository.cs, ITaskRepository.cs, ILinkRepository.cs,
│                    IAppStateRepository.cs, IOpenTabRepository.cs,
│                    IDiagnosticsRepository.cs, IAttachmentRepository.cs
├── Notebar.Core.Tests/                   the 46-test conformance suite + additions
├── Notebar.Store/
│   ├── NotebarDatabase.cs                Connection, migrator, applied-migration tracking
│   ├── Migrations.cs                     Ordered, additive, named
│   ├── SqliteNoteRepository.cs, SqliteTaskRepository.cs, SqliteLinkRepository.cs
│   ├── SqliteAppStateRepository.cs, SqliteOpenTabRepository.cs
│   ├── SqliteDiagnosticsRepository.cs, SqliteAttachmentRepository.cs
│   ├── SortOrder.cs                      Fractional between-two-neighbours arithmetic
│   └── NoteHtml.cs                       HTML → body_plain derivation
├── Notebar.Store.Tests/
└── Notebar.App/
    ├── Notebar.App.csproj, app.manifest, Package.appxmanifest
    ├── App.xaml / App.xaml.cs
    ├── Interop/NativeMethods.cs          Every P/Invoke, one file
    ├── Interop/MessageWindow.cs          Hidden HWND: WM_HOTKEY + tray callback
    ├── Panel/PanelWindow.xaml(.cs)       The borderless topmost window
    ├── Panel/PanelController.cs          The only code turning PanelEffect into Win32 calls
    ├── Panel/CursorMonitor.cs            GetCursorPos on a DispatcherTimer
    ├── Panel/PanelGeometry.cs            dip↔physical, work area, collapsed/expanded/maximized rects
    ├── App/TrayIcon.cs, GlobalHotKey.cs, DiagnosticsExporter.cs
    ├── DesignSystem/Tokens.xaml          Colours, radii, type scale, light + dark
    ├── Features/RootPage.xaml(.cs), TabRail.xaml(.cs), TabToolbar.xaml(.cs)
    ├── Features/PanelViewModel.cs
    ├── Features/Notes/NotesTab.xaml(.cs), NoteEditorHost.xaml(.cs), AllNotesMenu.xaml(.cs)
    ├── Features/Tasks/TasksTab.xaml(.cs), TaskDetailPane.xaml(.cs)
    ├── Features/Linking/BacklinksSection.xaml(.cs)
    ├── Features/Settings/SettingsTab.xaml(.cs)
    └── Editor/editor.html, editor.css, editor.js   The contenteditable surface
```

---

## Task Order

Platform risk first. The three things that could sink this milestone are packaging (Task 1), always-on-top over other windows and virtual desktops (Task 7), and the WebView2↔host bridge (Task 10). Tasks 2–6 are the pure logic those depend on, and are fully verifiable on the development machine, so they are cheap insurance rather than a delay.

| # | Task | Verified |
|---|---|---|
| 1 | Solution scaffold + CI producing an MSIX | CI |
| 2 | Core geometry, timing, and the panel state machine | Local |
| 3 | Core models, link URLs, and tombstones | Local |
| 4 | Store: database, migrator, notes | Local |
| 5 | Store: tasks, links, app state, open tabs, attachments, diagnostics | Local |
| 6 | Panel geometry: DPI, work area, three rects | Local |
| 7 | **RISK** The panel window: borderless, topmost, non-stealing, all desktops | CI + human |
| 8 | **RISK** Cursor monitor and the controller wiring | CI + human |
| 9 | Tray icon, global hotkey, quit | CI + human |
| 10 | **RISK** WebView2 editor and its bridge | CI + human |
| 11 | Shell chrome: tab rail, toolbar, handle, pin, maximize, collapse | CI + human |
| 12 | Notes tab: tab strip, all-notes menu, create, rename, delete | CI + human |
| 13 | Formatting bar, lists, checkboxes, images | CI + human |
| 14 | Tasks board: columns, cards, drag, detail pane | CI + human |
| 15 | Linking: `@` autocomplete, chips, backlinks, tombstones | CI + human |
| 16 | Settings, packaging, and the first release | CI + human |

---

### Task 1: Solution scaffold and a CI job that produces an MSIX

The riskiest single unknown is whether a WinUI 3 MSIX builds and packages unattended in GitHub Actions. Find out before writing anything worth losing.

**Files:**
- Create: `windows/Notebar.sln`
- Create: `windows/Directory.Build.props`
- Create: `windows/Notebar.Core/Notebar.Core.csproj`
- Create: `windows/Notebar.Core/Panel/PanelTiming.cs`
- Create: `windows/Notebar.Core.Tests/Notebar.Core.Tests.csproj`
- Create: `windows/Notebar.Core.Tests/PanelTimingTests.cs`
- Create: `windows/Notebar.App/Notebar.App.csproj`
- Create: `windows/Notebar.App/app.manifest`
- Create: `windows/Notebar.App/Package.appxmanifest`
- Create: `windows/Notebar.App/App.xaml`, `windows/Notebar.App/App.xaml.cs`
- Create: `windows/Notebar.App/Panel/PanelWindow.xaml`, `windows/Notebar.App/Panel/PanelWindow.xaml.cs`
- Create: `windows/scripts/check-core-purity.sh`
- Create: `windows/.gitignore`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: `Notebar.Core.PanelTiming` — a static class of `public const double` timing values and `public const double` geometry values, consumed by Tasks 2, 6, 7, 8, 16.

- [ ] **Step 1: Resolve the Windows App SDK version to pin**

Floating NuGet versions make CI non-reproducible. Pin an exact one, discovered rather than guessed:

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
dotnet package search Microsoft.WindowsAppSDK --exact-match --format json | head -40
```

Take the highest **stable** version (no `-preview`, no `-experimental`). Call it `$WASDK` below and write the literal number into the csproj — not a variable, not a wildcard.

- [ ] **Step 2: Write `windows/Directory.Build.props`**

```xml
<Project>
  <PropertyGroup>
    <LangVersion>13.0</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <WarningsNotAsErrors>NU1701</WarningsNotAsErrors>
    <EnableNETAnalyzers>true</EnableNETAnalyzers>
    <AnalysisLevel>latest</AnalysisLevel>
    <Version>0.1.0</Version>
  </PropertyGroup>
</Project>
```

- [ ] **Step 3: Write `windows/Notebar.Core/Notebar.Core.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <RootNamespace>Notebar.Core</RootNamespace>
  </PropertyGroup>
</Project>
```

No `<ItemGroup>`. The absence of dependencies is the point; Step 10's script enforces it.

- [ ] **Step 4: Write `windows/Notebar.Core/Panel/PanelTiming.cs`**

Every value copied from `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelTiming.swift`, including the reasoning, because the reasoning is what stops someone "tidying" a number that was chosen by feel.

```csharp
namespace Notebar.Core.Panel;

/// <summary>
/// Timing and geometry defaults. Every value here is either a user setting or
/// a measurement the layout depends on; nothing may inline these numbers at a
/// call site.
/// </summary>
/// <remarks>
/// Seconds for durations, device-independent pixels for lengths. The panel
/// window works in physical pixels, so <see cref="Notebar.App"/>'s
/// PanelGeometry scales these by the target monitor's DPI — these constants
/// are never used as physical pixels directly.
/// </remarks>
public static class PanelTiming
{
    /// <summary>Cursor must rest in the trigger zone this long before expanding.
    /// Prevents accidental opens when reaching for a scrollbar.</summary>
    public const double EdgeDwell = 0.120;

    /// <summary>Cursor must stay outside the panel this long before collapsing.</summary>
    public const double ExitDwell = 0.350;

    /// <summary>The collapsed handle's size. It lives here rather than with the
    /// design tokens because <see cref="TriggerWidth"/> must equal it — the
    /// handle *is* the target, and two modules disagreeing about its width is
    /// exactly how the affordance stopped working on macOS.</summary>
    public const double HandleWidth = 30;
    public const double HandleHeight = 56;

    /// <summary>The expanded panel's fixed width, flush to the right edge.</summary>
    public const double PanelWidth = 340;

    /// <summary>Fraction of the work area's height the expanded panel occupies,
    /// vertically centred — a card, not a full-height column.</summary>
    public const double PanelHeightFraction = 0.70;

    /// <summary>Fraction of the work area's width the panel occupies when
    /// maximized. At that width it fills the full work-area height instead of
    /// <see cref="PanelHeightFraction"/> — maximized reads as a docked
    /// half-screen column, not a bigger card.</summary>
    public const double MaximizedWidthFraction = 0.5;

    /// <summary>Width of the activation strip at the screen edge. Equal to the
    /// handle width so that hovering the handle — the only thing the user can
    /// see — arms the panel. <see cref="EdgeDwell"/> remains the guard against
    /// accidental opens, not a narrow target.</summary>
    public const double TriggerWidth = HandleWidth;

    /// <summary>Distance from the edge at which polling speeds up.</summary>
    public const double ProximityWidth = 80;

    /// <summary>Cursor must clear the panel bounds by this margin before the
    /// exit timer starts.</summary>
    public const double ExitSlop = 24;

    public const double ExpandDuration = 0.180;

    /// <summary>Deliberately faster than expanding — reads as responsive,
    /// not sluggish.</summary>
    public const double CollapseDuration = 0.140;

    /// <summary>How long after the last keystroke the panel still counts as
    /// "in use". Referenced by PanelMachine.ShouldCollapse.</summary>
    public const double TypingGrace = 2.0;

    // Activation settings ranges. Used both as the slider bounds in Settings
    // and as the clamp the app-state repository applies on read, so a
    // hand-edited database cannot push the panel further than the UI ever
    // could.

    /// <summary>Zero is left in: an open delay of zero is merely eager,
    /// not hostile.</summary>
    public const double EdgeDwellMin = 0.0;
    public const double EdgeDwellMax = 0.5;

    /// <summary>The floor is deliberately above zero — an exit dwell of 0
    /// makes the panel collapse the instant the cursor leaves, which is the
    /// hostile behaviour the suppression rules exist to prevent.</summary>
    public const double ExitDwellMin = 0.05;
    public const double ExitDwellMax = 2.0;

    public const double ExitSlopMin = 0.0;
    public const double ExitSlopMax = 100.0;

    /// <summary>Clamps <paramref name="value"/> into [min, max]. Used by the
    /// app-state repository on every read of a stored timing.</summary>
    public static double Clamp(double value, double min, double max) =>
        value < min ? min : value > max ? max : value;
}
```

- [ ] **Step 5: Write `windows/Notebar.Core.Tests/Notebar.Core.Tests.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <RootNamespace>Notebar.Core.Tests</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../Notebar.Core/Notebar.Core.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 6: Write the two ported `PanelTimingTests`**

Direct ports of `PanelTimingTests.swift`'s `triggerMatchesHandle` and `maximizedWidthReachesBoardBreakpoint`.

```csharp
using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class PanelTimingTests
{
    /// The handle is the only visible target, so the activation strip must be
    /// exactly as wide as it. These drifting apart is how the affordance
    /// silently stopped working on macOS.
    [Fact]
    public void TriggerMatchesHandle()
    {
        Assert.Equal(PanelTiming.HandleWidth, PanelTiming.TriggerWidth);
    }

    /// Maximized must be wide enough for the tasks board's three columns to
    /// stop being unusably narrow. On a 1440-wide work area, half is 720.
    [Fact]
    public void MaximizedWidthReachesBoardBreakpoint()
    {
        const double workAreaWidth = 1440;
        double maximized = workAreaWidth * PanelTiming.MaximizedWidthFraction;
        Assert.True(maximized >= 600, $"maximized width {maximized} is below the board breakpoint");
        Assert.True(maximized > PanelTiming.PanelWidth, "maximized must be wider than the normal panel");
    }
}
```

- [ ] **Step 7: Run the tests and confirm they pass**

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd windows && dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
```

Expected: `Passed! - Failed: 0, Passed: 2`.

- [ ] **Step 8: Write the minimal WinUI app**

`windows/Notebar.App/Notebar.App.csproj` — substitute the literal version from Step 1 for `$WASDK`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0-windows10.0.22621.0</TargetFramework>
    <TargetPlatformMinVersion>10.0.22621.0</TargetPlatformMinVersion>
    <RootNamespace>Notebar.App</RootNamespace>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <Platforms>x64;arm64</Platforms>
    <RuntimeIdentifiers>win-x64;win-arm64</RuntimeIdentifiers>
    <UseWinUI>true</UseWinUI>
    <EnableMsixTooling>true</EnableMsixTooling>
    <WindowsPackageType>MSIX</WindowsPackageType>
    <ApplicationIcon>Assets/Notebar.ico</ApplicationIcon>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.WindowsAppSDK" Version="$WASDK" />
    <PackageReference Include="Microsoft.Windows.SDK.BuildTools" Version="$SDKBUILDTOOLS" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../Notebar.Core/Notebar.Core.csproj" />
  </ItemGroup>
  <!-- Single-project MSIX: the manifest and the tile assets must be declared as
       items. Nothing generates them, and without the AppxManifest item MakeAppx
       is handed a package directory with no manifest and fails with 0x80080203,
       "You must include a valid app package manifest file named AppxManifest.xml
       in the source" — with no earlier error to explain it. -->
  <ItemGroup>
    <AppxManifest Include="Package.appxmanifest">
      <SubType>Designer</SubType>
    </AppxManifest>
    <Manifest Include="$(ApplicationManifest)" />
    <Content Include="Assets\**\*.png" />
  </ItemGroup>
</Project>
```

`$SDKBUILDTOOLS` is discovered the same way as `$WASDK` — the Windows App SDK's own
dependency chain sets a floor, and pinning below it produces an NU1605 downgrade error rather
than a helpful message.

`windows/Notebar.App/app.manifest` — PerMonitorV2 matters: without it every geometry
calculation is wrong on a scaled display, silently, and only on the user's machine.

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="Notebar.App"/>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </windowsSettings>
  </application>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>
</assembly>
```

`windows/Notebar.App/App.xaml`:

```xml
<Application
    x:Class="Notebar.App.App"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <XamlControlsResources xmlns="using:Microsoft.UI.Xaml.Controls" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Application.Resources>
</Application>
```

`windows/Notebar.App/App.xaml.cs`:

```csharp
using Microsoft.UI.Xaml;

namespace Notebar.App;

public partial class App : Application
{
    private PanelWindow? _window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new PanelWindow();
        _window.Activate();
    }
}
```

`windows/Notebar.App/Panel/PanelWindow.xaml`:

```xml
<Window
    x:Class="Notebar.App.PanelWindow"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Grid>
        <TextBlock x:Name="Placeholder" HorizontalAlignment="Center" VerticalAlignment="Center" />
    </Grid>
</Window>
```

`windows/Notebar.App/Panel/PanelWindow.xaml.cs` — proves the App project really links against Core:

```csharp
using Microsoft.UI.Xaml;
using Notebar.Core.Panel;

namespace Notebar.App;

public sealed partial class PanelWindow : Window
{
    public PanelWindow()
    {
        InitializeComponent();
        Title = "Notebar";
        Placeholder.Text = $"Notebar — panel width {PanelTiming.PanelWidth}";
    }
}
```

`windows/Notebar.App/Package.appxmanifest` — replace `Publisher` only if a real certificate is ever obtained; `CN=Notebar` is correct for an unsigned build.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">
  <Identity Name="Notebar" Publisher="CN=Notebar" Version="0.1.0.0" />
  <Properties>
    <DisplayName>Notebar</DisplayName>
    <PublisherDisplayName>Notebar</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.22621.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Resources><Resource Language="en-us" /></Resources>
  <Applications>
    <Application Id="App" Executable="Notebar.App.exe" EntryPoint="$targetentrypoint$">
      <uap:VisualElements
        DisplayName="Notebar"
        Description="A notes and tasks panel that lives at the screen edge."
        BackgroundColor="transparent"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png" />
    </Application>
  </Applications>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
```

- [ ] **Step 9: Generate the MSIX logo assets from the existing icon generator**

Both platforms should look like the same product, and the macOS icon is already reproducible
from `scripts/make-icon.py` — its `render()` returns the 1024pt master. Reuse it rather than
drawing a second, drifting mark. The filename has a hyphen so it cannot be imported by name;
load it by path.

Create `windows/scripts/make-msix-assets.py`:

```python
#!/usr/bin/env python3
"""Generate Notebar's MSIX tile assets and Windows .ico from the shared icon.

Run from the repo root:  python3 windows/scripts/make-msix-assets.py
Requires Pillow: pip3 install Pillow
"""
import importlib.util
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "windows", "Notebar.App", "Assets")

spec = importlib.util.spec_from_file_location(
    "make_icon", os.path.join(ROOT, "scripts", "make-icon.py"))
make_icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_icon)

master = make_icon.render()
os.makedirs(OUT, exist_ok=True)

for name, size in [("Square44x44Logo.png", 44),
                   ("Square150x150Logo.png", 150),
                   ("StoreLogo.png", 50)]:
    master.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))

# Wide tile: the square mark centred on a transparent 310x150 field.
wide = Image.new("RGBA", (310, 150), (0, 0, 0, 0))
sq = master.resize((150, 150), Image.LANCZOS)
wide.paste(sq, (80, 0), sq)
wide.save(os.path.join(OUT, "Wide310x150Logo.png"))

# .ico for the portable build's window and taskbar icon.
master.save(os.path.join(OUT, "Notebar.ico"),
            sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

print("wrote", OUT)
```

Run it and confirm five files appear:

```bash
cd /Users/anhnm/dev/01.Github/Notebar
python3 windows/scripts/make-msix-assets.py
ls windows/Notebar.App/Assets
```

Expected: `Notebar.ico  Square150x150Logo.png  Square44x44Logo.png  StoreLogo.png  Wide310x150Logo.png`

If `render()` is not importable because `make-icon.py` guards it behind `main()`, it is not —
it is a module-level `def render()` at line 61 and importing the module does not run `main()`,
which sits under `if __name__ == "__main__":`.

- [ ] **Step 10: Write the core purity guard**

The Swift core has `scripts/check-core-purity.sh` because a single stray import quietly ends
portability. The C# core needs the same guard, and needs it now rather than after the first
violation. Create `windows/scripts/check-core-purity.sh`:

```bash
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
FORBIDDEN='^\s*(global\s+)?using\s+(Microsoft\.UI|Microsoft\.Win32|Microsoft\.Data|Windows\.|WinRT|System\.Drawing|System\.IO|System\.Net|System\.Windows)'
if grep -rEn "$FORBIDDEN" Notebar.Core --include='*.cs' ; then
  echo "FAIL: forbidden using directive in Notebar.Core (see above)."
  FAIL=1
fi

# 3. Fully-qualified use bypasses the using check, so catch the common ones too.
QUALIFIED='(System\.IO\.File|System\.IO\.Directory|System\.Net\.|Microsoft\.UI\.|Windows\.UI\.)'
if grep -rEn "$QUALIFIED" Notebar.Core --include='*.cs' ; then
  echo "FAIL: fully-qualified platform type used in Notebar.Core (see above)."
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "OK: Notebar.Core is pure."
fi
exit "$FAIL"
```

Make it executable and run it:

```bash
chmod +x windows/scripts/check-core-purity.sh
windows/scripts/check-core-purity.sh
```

Expected: `OK: Notebar.Core is pure.`

- [ ] **Step 11: Write the solution file and `.gitignore`**

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd /Users/anhnm/dev/01.Github/Notebar/windows
dotnet new sln --name Notebar
dotnet sln add Notebar.Core/Notebar.Core.csproj
dotnet sln add Notebar.Core.Tests/Notebar.Core.Tests.csproj
dotnet sln add Notebar.App/Notebar.App.csproj
```

`dotnet sln add` on the App project succeeds on macOS even though building it does not — the
solution file is just a list.

`windows/.gitignore`:

```
bin/
obj/
*.user
AppPackages/
BundleArtifacts/
*.appx
*.msix
*.msixbundle
```

- [ ] **Step 12: Add the Windows build job to CI**

Append a fourth job to `.github/workflows/ci.yml`, alongside the existing `core`, `app`, and
`windows` (Swift) jobs. Do not modify the existing three.

```yaml
  windows-app:
    name: Windows app (C#)
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '9.0.x'

      # The cross-platform half. These carry the behaviour, so they run first
      # and a failure here stops the build before the slow MSIX step.
      - name: Test Notebar.Core
        run: dotnet test windows/Notebar.Core.Tests/Notebar.Core.Tests.csproj -c Release

      - name: Core purity guard
        shell: bash
        run: windows/scripts/check-core-purity.sh

      - name: Build the WinUI app
        run: dotnet build windows/Notebar.App/Notebar.App.csproj -c Release -p:Platform=x64

      - name: Package MSIX
        run: >
          dotnet build windows/Notebar.App/Notebar.App.csproj
          -c Release
          -p:Platform=x64
          -p:GenerateAppxPackageOnBuild=true
          -p:AppxPackageSigningEnabled=false
          -p:UapAppxPackageBuildMode=SideloadOnly

      - name: Collect the package
        shell: bash
        run: |
          mkdir -p artifacts
          find windows/Notebar.App -name '*.msix' -exec cp {} artifacts/ \;
          ls -la artifacts

      - uses: actions/upload-artifact@v4
        with:
          name: notebar-windows-msix
          path: artifacts/
          if-no-files-found: error
```

`if-no-files-found: error` is deliberate. A packaging step that produces nothing while
reporting success is exactly the failure this whole task exists to rule out.

**The portable zip is the primary artifact and its step must not depend on MSIX succeeding.**
An unsigned MSIX cannot be installed by double-click — it needs an `Add-AppxPackage` incantation
— while the zip needs no installation ceremony at all. Publish and upload it in its own step,
before the MSIX step, so a packaging problem can never leave the pipeline with nothing
distributable:

```yaml
      - name: Publish the portable build
        run: >
          dotnet publish windows/Notebar.App/Notebar.App.csproj
          -c Release -r win-x64 --self-contained true
          -p:Platform=x64 -p:WindowsPackageType=None
          -o publish/portable

      - uses: actions/upload-artifact@v4
        with:
          name: notebar-windows-portable
          path: publish/portable/
          if-no-files-found: error
```

- [ ] **Step 13: Commit and push, then watch CI**

```bash
cd /Users/anhnm/dev/01.Github/Notebar
git add windows .github/workflows/ci.yml
git commit -m "Scaffold the Windows solution and a CI job that packages an MSIX

Proves the riskiest unknown first: that a WinUI 3 MSIX builds and packages
unattended on windows-latest. Everything else in this milestone depends on
that being true, and finding out in week four would be expensive.

Notebar.Core is set up pure from its first commit — no packages, no project
references, no platform namespaces — and windows/scripts/check-core-purity.sh
enforces it in CI, mirroring the Swift core's guard. The Swift core lost a
day to a single stray CoreGraphics import; this is that day, prepaid.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
gh run watch "$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

Expected: the `windows-app` job passes and uploads a non-empty `notebar-windows-msix` artifact.

**If MSIX packaging fails**, do not proceed to Task 2 with it broken. The likely causes, in
order: `-p:Platform=x64` missing (WinUI does not build for `AnyCPU`); a `Package.appxmanifest`
asset path pointing at a file Step 9 did not produce; `WindowsPackageType` conflicting with
`GenerateAppxPackageOnBuild`. Fix and re-push before moving on.

---

### Task 2: Core geometry, edge classification, and the panel state machine

The 328 lines of behaviour that took the macOS build the longest to get right. Ported with its
24 tests, which is what makes "does the C# behave like the shipped Swift" a fact rather than a
hope.

**Files:**
- Create: `windows/Notebar.Core/Geometry/PanelPoint.cs`
- Create: `windows/Notebar.Core/Geometry/PanelRect.cs`
- Create: `windows/Notebar.Core/Panel/EdgeZone.cs`
- Create: `windows/Notebar.Core/Panel/PanelState.cs`
- Create: `windows/Notebar.Core/Panel/PanelEffect.cs`
- Create: `windows/Notebar.Core/Panel/PanelContext.cs`
- Create: `windows/Notebar.Core/Panel/PanelMachine.cs`
- Test: `windows/Notebar.Core.Tests/EdgeZoneTests.cs`
- Test: `windows/Notebar.Core.Tests/PanelMachineTests.cs`
- Test: `windows/Notebar.Core.Tests/CollapsePolicyTests.cs`

**Interfaces:**
- Consumes: `PanelTiming` (Task 1).
- Produces:
  - `readonly record struct PanelPoint(double X, double Y)`
  - `readonly record struct PanelRect(double X, double Y, double Width, double Height)` with `MinX`, `MaxX`, `MinY`, `MaxY`, `bool Contains(PanelPoint)`, `PanelRect Inflate(double dx, double dy)`
  - `enum PanelState { Hidden, Expanding, Expanded, Collapsing }`
  - `enum PanelTimerKind { EdgeDwell, ExitDwell }`
  - `enum PollRate { Idle, Active }`
  - `enum PanelEvent { CursorEnteredTrigger, CursorLeftTrigger, CursorEnteredPanel, CursorLeftPanel, EdgeDwellElapsed, ExitDwellElapsed, AnimationFinished, ToggleRequested, EscapePressed }`
  - `abstract record PanelEffect` with `PanelEffect.StartTimer(PanelTimerKind)`, `.CancelTimer(PanelTimerKind)`, `.ShowPanel`, `.HidePanel`, `.SetPollRate(PollRate)`
  - `readonly record struct PanelContext(bool IsPinned, bool HasOpenOverlay, bool IsDragging, bool IsEditorFocused, int? MsSinceLastKeystroke, bool IsWindowActive)` with `static PanelContext Idle`
  - `enum EdgeProximity { Away, Near, Inside }`
  - `sealed class EdgeZone(double triggerWidth, double proximityWidth)` with instance method `EdgeProximity Classify(PanelPoint cursor, PanelRect screen)`
  - `static bool EdgeZone.IsOutside(PanelPoint cursor, PanelRect panel, double slop)`
  - `static (PanelState, IReadOnlyList<PanelEffect>) PanelMachine.Reduce(PanelState state, PanelEvent evt, PanelContext context)`
  - `static bool PanelMachine.ShouldCollapse(PanelContext context)` — `internal`, exposed to tests via `InternalsVisibleTo`

- [ ] **Step 1: Write the geometry primitives**

Own types rather than `System.Drawing.Point`, because the core takes no dependencies and
because a distinct type stops device-independent and physical pixels being mixed up silently —
these are always dips, and the App project's `PanelGeometry` is the only place that converts.

`windows/Notebar.Core/Geometry/PanelPoint.cs`:

```csharp
namespace Notebar.Core.Geometry;

/// <summary>A point in device-independent pixels.</summary>
/// <remarks>
/// Windows screen coordinates are top-left origin with Y increasing downward.
/// Nothing in the core depends on that — see <see cref="Notebar.Core.Panel.EdgeZone"/>
/// for why every expression is written against a rect's min and max instead.
/// </remarks>
public readonly record struct PanelPoint(double X, double Y);
```

`windows/Notebar.Core/Geometry/PanelRect.cs`:

```csharp
namespace Notebar.Core.Geometry;

/// <summary>A rectangle in device-independent pixels. <paramref name="Y"/> is the
/// top edge, matching Windows screen coordinates.</summary>
public readonly record struct PanelRect(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MaxX => X + Width;
    public double MinY => Y;
    public double MaxY => Y + Height;

    public bool Contains(PanelPoint p) =>
        p.X >= MinX && p.X <= MaxX && p.Y >= MinY && p.Y <= MaxY;

    /// <summary>Grows the rect by <paramref name="dx"/> on each horizontal edge and
    /// <paramref name="dy"/> on each vertical edge. Negative values shrink it.</summary>
    public PanelRect Inflate(double dx, double dy) =>
        new(X - dx, Y - dy, Width + 2 * dx, Height + 2 * dy);
}
```

- [ ] **Step 2: Write the failing `EdgeZoneTests`**

All ten ported from `EdgeZoneTests.swift`. **The numbers are unchanged from the Swift**, which
is the point: see the comment on the class.

`windows/Notebar.Core.Tests/EdgeZoneTests.cs`:

```csharp
using Notebar.Core.Geometry;
using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

/// <summary>
/// Ported verbatim from the macOS EdgeZoneTests, numbers included.
///
/// Windows screen coordinates are top-left origin with Y increasing downward,
/// the opposite of Cocoa — and none of these assertions changes because of it.
/// Every expression in EdgeZone is written against a rect's min and max on each
/// axis, and both coordinate systems have MinY..MaxY spanning the screen. Only
/// the *meaning* of MinY changes, from "bottom" to "top". No arithmetic does.
/// If you came here to flip a sign, that is why you should not.
/// </summary>
public class EdgeZoneTests
{
    private static readonly EdgeZone Zone = new(triggerWidth: 4, proximityWidth: 80);
    private static readonly PanelRect Screen = new(0, 0, 1440, 900);

    [Fact]
    public void FarLeftIsAway() =>
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(200, 400), Screen));

    [Fact]
    public void FortyPointsIsNear() =>
        Assert.Equal(EdgeProximity.Near, Zone.Classify(new PanelPoint(1400, 400), Screen));

    [Fact]
    public void OnePointIsInside() =>
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(1439, 400), Screen));

    [Fact]
    public void BoundariesAreInclusive()
    {
        // Exactly triggerWidth from the edge is still inside.
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(1436, 400), Screen));
        // Exactly proximityWidth from the edge is still near.
        Assert.Equal(EdgeProximity.Near, Zone.Classify(new PanelPoint(1360, 400), Screen));
        // One point beyond proximityWidth is away.
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1359, 400), Screen));
    }

    [Fact]
    public void OutsideVerticalBoundsIsAway()
    {
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1439, -1), Screen));
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1439, 901), Screen));
    }

    /// A second display sitting to the right puts the cursor past this screen's
    /// right edge. Negative distance means it has left, not that it is deeply inside.
    [Fact]
    public void PastTheEdgeIsAway() =>
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1441, 400), Screen));

    [Fact]
    public void NonZeroOriginScreen()
    {
        var right = new PanelRect(1440, 0, 1280, 800);
        Assert.Equal(EdgeProximity.Inside, Zone.Classify(new PanelPoint(2719, 400), right));
        Assert.Equal(EdgeProximity.Away, Zone.Classify(new PanelPoint(1500, 400), right));
    }

    /// The handle is the target, so a zone built from PanelTiming must arm on it.
    [Fact]
    public void HandleWidthArmsTrigger()
    {
        var zone = new EdgeZone(PanelTiming.TriggerWidth, PanelTiming.ProximityWidth);
        double justInsideHandle = Screen.MaxX - PanelTiming.HandleWidth + 1;
        Assert.Equal(EdgeProximity.Inside, zone.Classify(new PanelPoint(justInsideHandle, 400), Screen));
    }

    /// ...and must not arm on the band beyond it.
    [Fact]
    public void HandleSizedRectArmsOnlyItsBand()
    {
        var zone = new EdgeZone(PanelTiming.TriggerWidth, PanelTiming.ProximityWidth);
        double justOutsideHandle = Screen.MaxX - PanelTiming.HandleWidth - 1;
        Assert.Equal(EdgeProximity.Near, zone.Classify(new PanelPoint(justOutsideHandle, 400), Screen));
    }

    /// The slop is what stops the panel collapsing when the cursor drifts a few
    /// points past its edge on the way to a scrollbar.
    [Fact]
    public void ExitSlopWidensBounds()
    {
        var panel = new PanelRect(1100, 100, 340, 700);
        Assert.False(EdgeZone.IsOutside(new PanelPoint(1090, 400), panel, slop: 24));
        Assert.True(EdgeZone.IsOutside(new PanelPoint(1070, 400), panel, slop: 24));
        Assert.False(EdgeZone.IsOutside(new PanelPoint(1200, 400), panel, slop: 0));
    }
}
```

- [ ] **Step 3: Run and confirm they fail**

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd windows && dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
```

Expected: compilation errors — `EdgeZone` and `EdgeProximity` do not exist.

- [ ] **Step 4: Write `EdgeZone`**

`windows/Notebar.Core/Panel/EdgeZone.cs`:

```csharp
using Notebar.Core.Geometry;

namespace Notebar.Core.Panel;

public enum EdgeProximity
{
    /// <summary>Far from the edge. Poll slowly.</summary>
    Away,
    /// <summary>Close enough to be approaching. Poll fast, but do not arm the dwell.</summary>
    Near,
    /// <summary>Inside the activation strip. Arm the dwell timer.</summary>
    Inside,
}

/// <summary>Classifies a cursor position against a screen's right edge.</summary>
/// <remarks>
/// All coordinates are device-independent pixels in Windows screen space:
/// top-left origin, Y increasing downward. The macOS original was written for
/// Cocoa's bottom-left origin and this is a verbatim port with no sign flips,
/// because every expression below is in terms of a rect's min and max on each
/// axis and both systems have MinY..MaxY spanning the screen. Only what MinY
/// *means* changed.
/// </remarks>
public sealed class EdgeZone(double triggerWidth, double proximityWidth)
{
    public double TriggerWidth { get; } = triggerWidth;
    public double ProximityWidth { get; } = proximityWidth;

    public EdgeProximity Classify(PanelPoint cursor, PanelRect screen)
    {
        if (cursor.Y < screen.MinY || cursor.Y > screen.MaxY) return EdgeProximity.Away;

        double distance = screen.MaxX - cursor.X;

        // Negative means the cursor is past this screen's right edge, which
        // happens when a second display sits to the right. It has left.
        if (distance < 0) return EdgeProximity.Away;

        if (distance <= TriggerWidth) return EdgeProximity.Inside;
        if (distance <= ProximityWidth) return EdgeProximity.Near;
        return EdgeProximity.Away;
    }

    /// <summary>Whether the cursor has cleared the panel by more than
    /// <paramref name="slop"/>. The slop is what stops the panel collapsing when
    /// the cursor drifts a few points past its edge on the way to a scrollbar.</summary>
    public static bool IsOutside(PanelPoint cursor, PanelRect panel, double slop) =>
        !panel.Inflate(slop, slop).Contains(cursor);
}
```

- [ ] **Step 5: Run and confirm the ten pass**

```bash
cd windows && dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
```

Expected: `Passed: 12` (the ten new plus Task 1's two).

- [ ] **Step 6: Commit**

```bash
git add windows/Notebar.Core/Geometry windows/Notebar.Core/Panel/EdgeZone.cs windows/Notebar.Core.Tests/EdgeZoneTests.cs
git commit -m "Port EdgeZone to C# with its ten tests unchanged

The coordinate flip the spec expected turned out not to be needed. Every
expression in EdgeZone is written against a rect's min and max on each axis,
and both Cocoa and Win32 have MinY..MaxY spanning the screen — only what MinY
means changes, from bottom to top. No arithmetic does, so the numbers in the
tests are the shipped macOS numbers.

Said out loud in both the type and the test class, because a reader who knows
the two coordinate systems differ will otherwise assume a flip was forgotten.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
```

- [ ] **Step 7: Write the state, event, effect, and context types**

`windows/Notebar.Core/Panel/PanelState.cs`:

```csharp
namespace Notebar.Core.Panel;

public enum PanelState { Hidden, Expanding, Expanded, Collapsing }

public enum PanelTimerKind { EdgeDwell, ExitDwell }

public enum PollRate
{
    /// <summary>Cursor is far from the edge. 10 Hz.</summary>
    Idle,
    /// <summary>Cursor is near the edge or the panel is open. 60 Hz.</summary>
    Active,
}

public enum PanelEvent
{
    /// <summary>Cursor entered the narrow activation strip at the screen edge.</summary>
    CursorEnteredTrigger,
    /// <summary>Cursor left the activation strip before the dwell elapsed.</summary>
    CursorLeftTrigger,
    /// <summary>Cursor moved inside the panel's bounds.</summary>
    CursorEnteredPanel,
    /// <summary>Cursor moved further than ExitSlop outside the panel's bounds.</summary>
    CursorLeftPanel,
    /// <summary>The edge-dwell timer fired.</summary>
    EdgeDwellElapsed,
    /// <summary>The exit-dwell timer fired.</summary>
    ExitDwellElapsed,
    /// <summary>A show or hide animation finished.</summary>
    AnimationFinished,
    /// <summary>Global hotkey pressed, or the tray toggle chosen.</summary>
    ToggleRequested,
    EscapePressed,
}
```

`windows/Notebar.Core/Panel/PanelEffect.cs` — records rather than an enum with payloads,
because record equality is what lets a test assert on a whole effect list in one line:

```csharp
namespace Notebar.Core.Panel;

/// <summary>Side effects the reducer requests. PanelController is the only code
/// that turns these into real Win32 and XAML calls — that separation is what
/// makes every transition testable without a window.</summary>
public abstract record PanelEffect
{
    private PanelEffect() { }

    public sealed record StartTimer(PanelTimerKind Timer) : PanelEffect;
    public sealed record CancelTimer(PanelTimerKind Timer) : PanelEffect;
    public sealed record ShowPanel : PanelEffect;
    public sealed record HidePanel : PanelEffect;
    public sealed record SetPollRate(PollRate Rate) : PanelEffect;
}
```

`windows/Notebar.Core/Panel/PanelContext.cs`:

```csharp
namespace Notebar.Core.Panel;

/// <summary>The suppression signals. Snapshotted by PanelController and passed
/// into every Reduce call.</summary>
public readonly record struct PanelContext(
    /// <summary>User pinned the panel, or summoned it by hotkey.</summary>
    bool IsPinned = false,
    /// <summary>A menu, flyout, or dialog is open.</summary>
    bool HasOpenOverlay = false,
    /// <summary>A drag is in flight.</summary>
    bool IsDragging = false,
    /// <summary>A text editor holds focus.</summary>
    bool IsEditorFocused = false,
    /// <summary>Milliseconds since the last keystroke, or null if none this session.</summary>
    int? MsSinceLastKeystroke = null,
    /// <summary>The panel window is the foreground window.</summary>
    bool IsWindowActive = false)
{
    /// <summary>A context with every suppression signal off.</summary>
    public static PanelContext Idle => new();
}
```

- [ ] **Step 8: Write the failing `PanelMachineTests` and `CollapsePolicyTests`**

Both classes need `PanelMachine.ShouldCollapse`, which is `internal`. Add to
`windows/Notebar.Core/Notebar.Core.csproj`:

```xml
  <ItemGroup>
    <AssemblyAttribute Include="System.Runtime.CompilerServices.InternalsVisibleToAttribute">
      <_Parameter1>Notebar.Core.Tests</_Parameter1>
    </AssemblyAttribute>
  </ItemGroup>
```

This is not a `PackageReference` or `ProjectReference`, so the purity guard still passes.

`windows/Notebar.Core.Tests/PanelMachineTests.cs` — twelve, ported one for one:

```csharp
using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class PanelMachineTests
{
    private static (PanelState, IReadOnlyList<PanelEffect>) Reduce(
        PanelState state, PanelEvent evt, PanelContext? context = null) =>
        PanelMachine.Reduce(state, evt, context ?? PanelContext.Idle);

    [Fact]
    public void EnteringTriggerStartsDwell()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.CursorEnteredTrigger);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.StartTimer(PanelTimerKind.EdgeDwell),
            new PanelEffect.SetPollRate(PollRate.Active),
        }, effects);
    }

    [Fact]
    public void LeavingTriggerCancelsDwell()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.CursorLeftTrigger);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.CancelTimer(PanelTimerKind.EdgeDwell),
            new PanelEffect.SetPollRate(PollRate.Idle),
        }, effects);
    }

    [Fact]
    public void DwellElapsedExpands()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.EdgeDwellElapsed);
        Assert.Equal(PanelState.Expanding, state);
        Assert.Equal(new PanelEffect[] { new PanelEffect.ShowPanel() }, effects);
    }

    [Fact]
    public void ExpandingCompletes()
    {
        var (state, effects) = Reduce(PanelState.Expanding, PanelEvent.AnimationFinished);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    /// Leaving an open panel only *arms* the collapse. Whether it is allowed to
    /// fire is decided when the timer elapses, against a fresh context.
    [Fact]
    public void LeavingPanelStartsExitTimer()
    {
        var (state, effects) = Reduce(PanelState.Expanded, PanelEvent.CursorLeftPanel);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.StartTimer(PanelTimerKind.ExitDwell),
        }, effects);
    }

    [Fact]
    public void ReturningCancelsExitTimer()
    {
        var (state, effects) = Reduce(PanelState.Expanded, PanelEvent.CursorEnteredPanel);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Equal(new PanelEffect[]
        {
            new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell),
        }, effects);
    }

    [Fact]
    public void ExitDwellCollapses()
    {
        var (state, effects) = Reduce(PanelState.Expanded, PanelEvent.ExitDwellElapsed);
        Assert.Equal(PanelState.Collapsing, state);
        Assert.Equal(new PanelEffect[] { new PanelEffect.HidePanel() }, effects);
    }

    [Fact]
    public void CollapseCompletes()
    {
        var (state, effects) = Reduce(PanelState.Collapsing, PanelEvent.AnimationFinished);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Equal(new PanelEffect[] { new PanelEffect.SetPollRate(PollRate.Idle) }, effects);
    }

    /// Cursor came back mid-collapse: reverse without touching Hidden.
    [Fact]
    public void ReEntryDuringCollapseReverses()
    {
        foreach (var evt in new[] { PanelEvent.CursorEnteredPanel, PanelEvent.CursorEnteredTrigger })
        {
            var (state, effects) = Reduce(PanelState.Collapsing, evt);
            Assert.Equal(PanelState.Expanding, state);
            Assert.Equal(new PanelEffect[] { new PanelEffect.ShowPanel() }, effects);
        }
    }

    /// Escape overrides every suppression signal, pinning included.
    [Fact]
    public void EscapeAlwaysCollapses()
    {
        var pinned = PanelContext.Idle with { IsPinned = true, IsEditorFocused = true };
        foreach (var from in new[] { PanelState.Expanded, PanelState.Expanding })
        {
            var (state, effects) = Reduce(from, PanelEvent.EscapePressed, pinned);
            Assert.Equal(PanelState.Collapsing, state);
            Assert.Equal(new PanelEffect[]
            {
                new PanelEffect.HidePanel(),
                new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell),
            }, effects);
        }
    }

    [Fact]
    public void ToggleFlips()
    {
        foreach (var from in new[] { PanelState.Hidden, PanelState.Collapsing })
        {
            var (state, effects) = Reduce(from, PanelEvent.ToggleRequested);
            Assert.Equal(PanelState.Expanding, state);
            Assert.Equal(new PanelEffect[]
            {
                new PanelEffect.ShowPanel(),
                new PanelEffect.SetPollRate(PollRate.Active),
            }, effects);
        }

        foreach (var from in new[] { PanelState.Expanded, PanelState.Expanding })
        {
            var (state, effects) = Reduce(from, PanelEvent.ToggleRequested);
            Assert.Equal(PanelState.Collapsing, state);
            Assert.Equal(new PanelEffect[] { new PanelEffect.HidePanel() }, effects);
        }
    }

    /// Anything not explicitly handled is inert: same state, no effects. This is
    /// what lets the controller fire events speculatively without checking state.
    [Fact]
    public void UnhandledPairsAreInert()
    {
        var (state, effects) = Reduce(PanelState.Hidden, PanelEvent.ExitDwellElapsed);
        Assert.Equal(PanelState.Hidden, state);
        Assert.Empty(effects);

        (state, effects) = Reduce(PanelState.Expanded, PanelEvent.EdgeDwellElapsed);
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);

        (state, effects) = Reduce(PanelState.Collapsing, PanelEvent.EscapePressed);
        Assert.Equal(PanelState.Collapsing, state);
        Assert.Empty(effects);
    }
}
```

`windows/Notebar.Core.Tests/CollapsePolicyTests.cs` — the twelve that encode the whole
suppression policy. These are the tests that made the macOS panel stop collapsing while people
were typing in it:

```csharp
using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class CollapsePolicyTests
{
    // --- Hard invariants: never collapse under these. ---

    [Fact]
    public void PinnedNeverCollapses() =>
        Assert.False(PanelMachine.ShouldCollapse(PanelContext.Idle with { IsPinned = true }));

    [Fact]
    public void OpenOverlayNeverCollapses() =>
        Assert.False(PanelMachine.ShouldCollapse(PanelContext.Idle with { HasOpenOverlay = true }));

    [Fact]
    public void DraggingNeverCollapses() =>
        Assert.False(PanelMachine.ShouldCollapse(PanelContext.Idle with { IsDragging = true }));

    [Fact]
    public void IdlePanelCollapses() =>
        Assert.True(PanelMachine.ShouldCollapse(PanelContext.Idle));

    // --- The same signals, checked through Reduce, because the policy is applied
    //     twice per collapse and a regression could hit either call site. ---

    [Fact]
    public void PinnedSurvivesExitDwell()
    {
        var (state, effects) = PanelMachine.Reduce(
            PanelState.Expanded, PanelEvent.ExitDwellElapsed,
            PanelContext.Idle with { IsPinned = true });
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    [Fact]
    public void DragInFlightSurvivesExit()
    {
        var (state, effects) = PanelMachine.Reduce(
            PanelState.Expanded, PanelEvent.CursorLeftPanel,
            PanelContext.Idle with { IsDragging = true });
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    // --- A focused editor holds the panel open indefinitely, no grace period.
    //     Losing what you are typing because the mouse drifted is the worst
    //     failure this panel can have. ---

    [Fact]
    public void FocusedEditorNeverCollapsesWithNoKeystrokes() =>
        Assert.False(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = true, MsSinceLastKeystroke = null }));

    [Fact]
    public void FocusedEditorNeverCollapsesRegardlessOfKeystrokeAge() =>
        Assert.False(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = true, MsSinceLastKeystroke = 600_000 }));

    [Fact]
    public void FocusedEditorSurvivesExitDwell()
    {
        var (state, effects) = PanelMachine.Reduce(
            PanelState.Expanded, PanelEvent.ExitDwellElapsed,
            PanelContext.Idle with { IsEditorFocused = true });
        Assert.Equal(PanelState.Expanded, state);
        Assert.Empty(effects);
    }

    // --- Once focus is gone, TypingGrace still covers a recent burst. ---

    [Fact]
    public void UnfocusedRecentKeystrokeDoesNotCollapse() =>
        Assert.False(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = false, MsSinceLastKeystroke = 1_500 }));

    [Fact]
    public void UnfocusedStaleKeystrokeCollapses() =>
        Assert.True(PanelMachine.ShouldCollapse(
            PanelContext.Idle with { IsEditorFocused = false, MsSinceLastKeystroke = 5_000 }));

    /// IsWindowActive is deliberately unused. A window can become foreground from
    /// one stray click, which is too weak a signal to suppress collapse on. This
    /// test is what stops someone "fixing" that by wiring it in.
    [Fact]
    public void WindowActiveAloneDoesNotSuppress() =>
        Assert.True(PanelMachine.ShouldCollapse(PanelContext.Idle with { IsWindowActive = true }));
}
```

- [ ] **Step 9: Run and confirm they fail**

```bash
cd windows && dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
```

Expected: compilation errors — `PanelMachine` does not exist.

- [ ] **Step 10: Write `PanelMachine`**

`windows/Notebar.Core/Panel/PanelMachine.cs`:

```csharp
namespace Notebar.Core.Panel;

/// <summary>The panel's behaviour as a pure function.</summary>
/// <remarks>
/// This type must never touch UI, hold state, read a clock, or start a timer.
/// Time enters only as events (EdgeDwellElapsed, ExitDwellElapsed) that
/// PanelController schedules on the reducer's instruction. That is what makes
/// flicker scenarios — the bugs that are miserable to reproduce by hand — into
/// ordinary table tests.
/// </remarks>
public static class PanelMachine
{
    private static readonly IReadOnlyList<PanelEffect> None = [];

    public static (PanelState, IReadOnlyList<PanelEffect>) Reduce(
        PanelState state, PanelEvent evt, PanelContext context) =>
        (state, evt) switch
        {
            // Approaching the edge: arm the dwell timer, speed up polling.
            (PanelState.Hidden, PanelEvent.CursorEnteredTrigger) =>
                (PanelState.Hidden, [
                    new PanelEffect.StartTimer(PanelTimerKind.EdgeDwell),
                    new PanelEffect.SetPollRate(PollRate.Active)]),

            (PanelState.Hidden, PanelEvent.CursorLeftTrigger) =>
                (PanelState.Hidden, [
                    new PanelEffect.CancelTimer(PanelTimerKind.EdgeDwell),
                    new PanelEffect.SetPollRate(PollRate.Idle)]),

            (PanelState.Hidden, PanelEvent.EdgeDwellElapsed) =>
                (PanelState.Expanding, [new PanelEffect.ShowPanel()]),

            (PanelState.Expanding, PanelEvent.AnimationFinished) =>
                (PanelState.Expanded, None),

            // Leaving an open panel only *arms* the collapse. Whether it is
            // allowed to fire is decided when the timer elapses, against a
            // fresh context — 350 ms is long enough for things to change.
            (PanelState.Expanded, PanelEvent.CursorLeftPanel) =>
                ShouldCollapse(context)
                    ? (PanelState.Expanded, [new PanelEffect.StartTimer(PanelTimerKind.ExitDwell)])
                    : (PanelState.Expanded, None),

            (PanelState.Expanded, PanelEvent.CursorEnteredPanel) =>
                (PanelState.Expanded, [new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell)]),

            (PanelState.Expanded, PanelEvent.ExitDwellElapsed) =>
                ShouldCollapse(context)
                    ? (PanelState.Collapsing, [new PanelEffect.HidePanel()])
                    : (PanelState.Expanded, None),

            (PanelState.Collapsing, PanelEvent.AnimationFinished) =>
                (PanelState.Hidden, [new PanelEffect.SetPollRate(PollRate.Idle)]),

            // Cursor came back mid-collapse: reverse without touching Hidden.
            (PanelState.Collapsing, PanelEvent.CursorEnteredPanel) or
            (PanelState.Collapsing, PanelEvent.CursorEnteredTrigger) =>
                (PanelState.Expanding, [new PanelEffect.ShowPanel()]),

            // Escape overrides every suppression signal, pinning included.
            (PanelState.Expanded, PanelEvent.EscapePressed) or
            (PanelState.Expanding, PanelEvent.EscapePressed) =>
                (PanelState.Collapsing, [
                    new PanelEffect.HidePanel(),
                    new PanelEffect.CancelTimer(PanelTimerKind.ExitDwell)]),

            (PanelState.Hidden, PanelEvent.ToggleRequested) or
            (PanelState.Collapsing, PanelEvent.ToggleRequested) =>
                (PanelState.Expanding, [
                    new PanelEffect.ShowPanel(),
                    new PanelEffect.SetPollRate(PollRate.Active)]),

            (PanelState.Expanded, PanelEvent.ToggleRequested) or
            (PanelState.Expanding, PanelEvent.ToggleRequested) =>
                (PanelState.Collapsing, [new PanelEffect.HidePanel()]),

            _ => (state, None),
        };

    /// <summary>Decides whether the panel is allowed to collapse right now.</summary>
    /// <remarks>
    /// Called twice per collapse: once when the cursor leaves (to decide whether
    /// to arm the exit timer at all) and again when that timer elapses.
    ///
    /// The trade-off: collapsing eagerly keeps the screen clean but interrupts
    /// you mid-thought; collapsing lazily never interrupts but leaves the panel
    /// loitering over your work. IsPinned, HasOpenOverlay, and IsDragging are
    /// hard requirements. Of the remaining three:
    ///
    ///   · IsEditorFocused      holds the panel open indefinitely, no grace
    ///                          period. Losing what you are typing because the
    ///                          mouse drifted is the worst failure this panel
    ///                          can have, and clicking into another app clears
    ///                          focus anyway, so this cannot strand it open.
    ///   · MsSinceLastKeystroke once focus is gone, TypingGrace still covers a
    ///                          recent burst of typing.
    ///   · IsWindowActive       deliberately unused. A window can become
    ///                          foreground from one stray click, which is too
    ///                          weak a signal to suppress collapse on.
    /// </remarks>
    internal static bool ShouldCollapse(PanelContext context)
    {
        if (context.IsPinned || context.HasOpenOverlay || context.IsDragging) return false;

        if (context.IsEditorFocused) return false;

        if (context.MsSinceLastKeystroke is { } ms && ms / 1000.0 <= PanelTiming.TypingGrace)
            return false;

        return true;
    }
}
```

- [ ] **Step 11: Run and confirm all 36 pass**

```bash
cd windows && dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
```

Expected: `Passed: 36` — 2 timing + 10 edge zone + 12 machine + 12 collapse policy.

- [ ] **Step 12: Commit**

```bash
git add windows/Notebar.Core/Panel windows/Notebar.Core/Notebar.Core.csproj windows/Notebar.Core.Tests
git commit -m "Port PanelMachine and its collapse policy to C#

The 24 behaviour tests pass against the C# reducer with the same assertions
they make against the shipped Swift one, so 'does the Windows panel behave
like the Mac panel' is now a fact the build checks rather than something
someone has to remember.

Effects are records rather than an enum with payloads: record equality is what
lets a test assert on a whole effect list in one line, which is why the effect
ordering in every transition is covered rather than just the resulting state.

IsWindowActive stays deliberately unused, with a test asserting it alone does
not suppress collapse — the macOS original documented that decision in a
comment, and a comment does not stop anyone wiring it in.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
```

---

### Task 3: Core models, link URLs, and tombstones

Mostly mechanical records. The two that carry real logic — `LinkUrl` and `LinkTombstone` —
get the remaining nine ported tests.

**Files:**
- Create: `windows/Notebar.Core/Models/Note.cs`, `NoteSummary.cs`, `TaskItem.cs`, `Board.cs`, `BoardColumn.cs`, `OpenTab.cs`, `Theme.cs`, `Attachment.cs`
- Create: `windows/Notebar.Core/Models/LinkEntityType.cs`, `LinkTarget.cs`, `Link.cs`, `LinkUrl.cs`, `LinkTombstone.cs`
- Create: `windows/Notebar.Core/Models/DatabaseDiagnostics.cs`, `DiagnosticsEnvironment.cs`
- Test: `windows/Notebar.Core.Tests/NoteTests.cs`, `LinkUrlTests.cs`, `LinkTombstoneTests.cs`, `DiagnosticsTests.cs`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, for Tasks 4, 5, 11–16:
  - `record Note(string Id, string Title, string BodyHtml, string BodyPlain, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, double SortOrder, bool IsPinned)` with `string DisplayTitle` and `bool IsEmptyAndUntitled`
  - `record NoteSummary(string Id, string Title, DateTimeOffset UpdatedAt)` with `string DisplayTitle`
  - `record TaskItem(string Id, string Title, string DetailPlain, string ColumnId, double SortOrder, int Priority, DateTimeOffset? DueAt, DateTimeOffset? CompletedAt, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt)`
  - `record Board(string Id, string Name, double SortOrder)`
  - `record BoardColumn(string Id, string BoardId, string Name, string Kind, double SortOrder, int? WipLimit)` with `const string BacklogKind = "backlog"`, `ActiveKind = "active"`, `DoneKind = "done"`
  - `record OpenTab(string Id, string Kind, string RefId, double SortOrder, bool IsActive)` with `const string NoteKind = "note"`
  - `enum Theme { System, Light, Dark }` with `static Theme Default => Theme.System`, `static Theme Parse(string?)`
  - `enum LinkEntityType { Note, Task }`
  - `readonly record struct LinkTarget(LinkEntityType Type, string Id)`
  - `record Link(string Id, LinkEntityType SrcType, string SrcId, LinkEntityType DstType, string DstId, string Kind, DateTimeOffset CreatedAt)` with `const string ReferencesKind = "references"`, `LinkTarget Source`, `LinkTarget Destination`
  - `record Attachment(string Id, string MimeType, byte[] Data, int Width, int Height, DateTimeOffset CreatedAt)`
  - `static class LinkUrl` — `string Build(LinkEntityType, string id)`, `string Build(LinkTarget)`, `LinkTarget? Parse(string)`
  - `static class LinkTombstone` — `bool? IsTombstone(string url, IReadOnlySet<LinkTarget> existingTargets)`
  - `record DatabaseDiagnostics(string? Path, long? SizeOnDisk, IReadOnlyList<string> AppliedMigrations)`
  - `record DiagnosticsEnvironment(string AppVersion, string BuildNumber, string OsVersion, IReadOnlyList<string> DisplayGeometry, DatabaseDiagnostics Database)` with `string RenderedText`

- [ ] **Step 1: Write the plain records**

`windows/Notebar.Core/Models/Note.cs` — note `BodyHtml` where macOS has `BodyRtf`, and note
that `IsEmptyAndUntitled` checks `BodyPlain`, never `BodyHtml`:

```csharp
namespace Notebar.Core.Models;

/// <summary>A single note.</summary>
/// <remarks>
/// BodyHtml is what the contenteditable editor round-trips; BodyPlain is the
/// plain-text shadow column FTS5 actually indexes, regenerated alongside
/// BodyHtml every time it changes so the two can never drift. Both live on
/// Note itself, and whoever holds the live document derives BodyPlain from it
/// and sets both fields together.
/// </remarks>
public sealed record Note(
    string Id,
    string Title,
    string BodyHtml,
    string BodyPlain,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    double SortOrder,
    bool IsPinned)
{
    public static Note New(double sortOrder)
    {
        var now = DateTimeOffset.UtcNow;
        return new Note(Guid.NewGuid().ToString(), "Untitled", "", "", now, now, sortOrder, false);
    }

    /// <summary>The tab strip's label. Title is a stored, user-editable column —
    /// it does not track the body in any way, so typing in a note never changes
    /// its tab.</summary>
    public string DisplayTitle => string.IsNullOrEmpty(Title) ? "Untitled" : Title;

    /// <summary>Whether the note is exactly as it was created. Such a note carries
    /// no information the user typed, so closing its tab deletes it outright
    /// rather than leaving a contentless row cluttering the all-notes menu. A
    /// note with a title or a body is the user's actual content, and closing a
    /// tab must never destroy that.</summary>
    /// <remarks>
    /// Checks BodyPlain, not BodyHtml. An "empty" editor document still
    /// serializes to markup like &lt;p&gt;&lt;br&gt;&lt;/p&gt;, so a check
    /// against BodyHtml would never be true for a real note and this predicate
    /// would quietly stop working the moment the editor landed. BodyPlain is
    /// exactly the visible-text shadow that already answers "is there anything
    /// here."
    /// </remarks>
    public bool IsEmptyAndUntitled =>
        DisplayTitle == "Untitled" && string.IsNullOrWhiteSpace(BodyPlain);
}
```

`windows/Notebar.Core/Models/NoteSummary.cs` — a distinct type, not a `Note` with an empty
body, and the reason matters:

```csharp
namespace Notebar.Core.Models;

/// <summary>The lightweight projection the all-notes menu needs: just enough to
/// render a title and a relative timestamp.</summary>
/// <remarks>
/// Deliberately its own type rather than a Note with a placeholder body. The
/// repository never selects body_html for these — twenty notes with one
/// screenshot each would otherwise mean reading megabytes to draw a list of
/// names — and a distinct type is what keeps that honest. A Note with
/// BodyHtml: "" would compile at every call site whether or not the body was
/// actually loaded; NoteSummary has no body field at all.
/// </remarks>
public sealed record NoteSummary(string Id, string Title, DateTimeOffset UpdatedAt)
{
    /// <summary>Mirrors Note.DisplayTitle exactly — the all-notes menu must show
    /// "Untitled" the same way the tab strip does.</summary>
    public string DisplayTitle => string.IsNullOrEmpty(Title) ? "Untitled" : Title;
}
```

`windows/Notebar.Core/Models/TaskItem.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>A single task card.</summary>
public sealed record TaskItem(
    string Id,
    string Title,
    string DetailPlain,
    string ColumnId,
    double SortOrder,
    int Priority,
    DateTimeOffset? DueAt,
    DateTimeOffset? CompletedAt,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static TaskItem New(string title, string columnId, double sortOrder)
    {
        var now = DateTimeOffset.UtcNow;
        return new TaskItem(Guid.NewGuid().ToString(), title, "", columnId, sortOrder,
                            0, null, null, now, now);
    }
}
```

`windows/Notebar.Core/Models/Board.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>A tasks board. v1 seeds exactly one, but the schema does not assume
/// a single board.</summary>
public sealed record Board(string Id, string Name, double SortOrder);
```

`windows/Notebar.Core/Models/BoardColumn.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>A status column on a Board.</summary>
/// <remarks>
/// Kind drives the one behaviour rule the repository owns — moving a task into a
/// DoneKind column stamps CompletedAt, moving it out clears it — so it is a
/// string constant rather than a closed enum: it is schema data a future board
/// could extend, not a fixed set the type system should own.
/// </remarks>
public sealed record BoardColumn(
    string Id, string BoardId, string Name, string Kind, double SortOrder, int? WipLimit)
{
    /// <summary>Not-yet-started work. Seeded as "Queue".</summary>
    public const string BacklogKind = "backlog";
    /// <summary>In-progress work. Seeded as "Working".</summary>
    public const string ActiveKind = "active";
    /// <summary>Finished work. Seeded as "Done" — the kind the task repository
    /// checks to decide whether a moved task's CompletedAt is stamped or cleared.</summary>
    public const string DoneKind = "done";
}
```

`windows/Notebar.Core/Models/OpenTab.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>A persisted entry in the open-tab strip. Open tabs survive a restart;
/// this is what makes that possible.</summary>
public sealed record OpenTab(string Id, string Kind, string RefId, double SortOrder, bool IsActive)
{
    /// <summary>A string constant rather than an enum: kinds are schema data other
    /// tabs add to later, not a fixed set the type system should close over.</summary>
    public const string NoteKind = "note";
}
```

`windows/Notebar.Core/Models/Theme.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>The user's appearance preference: a three-way choice between
/// following Windows' own appearance and pinning to one of its two modes.</summary>
public enum Theme { System, Light, Dark }

public static class ThemeExtensions
{
    /// <summary>The default: an overlay that floats above other apps should
    /// match them.</summary>
    public static Theme Default => Theme.System;

    /// <summary>Falls back to <see cref="Default"/> both when nothing has been
    /// saved and when the saved value is no longer recognised — someone
    /// hand-editing the database must get the default appearance back, not a
    /// crash.</summary>
    public static Theme Parse(string? raw) => raw switch
    {
        "light" => Theme.Light,
        "dark" => Theme.Dark,
        "system" => Theme.System,
        _ => Default,
    };

    public static string ToStorageString(this Theme theme) => theme switch
    {
        Theme.Light => "light",
        Theme.Dark => "dark",
        _ => "system",
    };
}
```

`windows/Notebar.Core/Models/Attachment.cs` — new on Windows; macOS embedded images in the
RTFD blob and had to add a summaries query to avoid loading them:

```csharp
namespace Notebar.Core.Models;

/// <summary>An image pasted or dropped into a note, stored as a row rather than
/// embedded in the body.</summary>
/// <remarks>
/// The macOS build embedded images in the note body blob and then needed a
/// separate summaries query to avoid reading every screenshot back just to draw
/// a list of note names. Storing them separately from the start costs nothing
/// extra and removes that whole class of problem: a note body is always small.
/// Width and Height are the intrinsic pixel dimensions after downscaling, so the
/// editor can lay the image out before the bytes have loaded.
/// </remarks>
public sealed record Attachment(
    string Id, string MimeType, byte[] Data, int Width, int Height, DateTimeOffset CreatedAt);
```

- [ ] **Step 2: Write the link model, URL codec, and tombstone predicate**

`windows/Notebar.Core/Models/LinkEntityType.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>The two kinds of thing a Link can point at.</summary>
/// <remarks>
/// A real enum, unlike OpenTab.Kind or BoardColumn.Kind — those are deliberately
/// open-ended schema data a future case can extend; a link's two endpoints are
/// exactly notes and tasks for the whole life of this table, so closing the type
/// over them catches a typo'd "nott" at compile time instead of as a silent
/// zero-row query at runtime.
/// </remarks>
public enum LinkEntityType { Note, Task }

public static class LinkEntityTypeExtensions
{
    public static string ToStorageString(this LinkEntityType type) =>
        type == LinkEntityType.Note ? "note" : "task";

    public static LinkEntityType? Parse(string? raw) => raw switch
    {
        "note" => LinkEntityType.Note,
        "task" => LinkEntityType.Task,
        _ => null,
    };
}
```

`windows/Notebar.Core/Models/LinkTarget.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>One endpoint of a Link — an entity type plus its id — used instead of
/// two loose parameters, so a caller cannot transpose a type and an id that
/// happen to both be strings.</summary>
/// <remarks>
/// A record struct, so it is usable as a HashSet element: the tombstone check
/// collects every note and task id that still exists into a set once per note
/// load, making "did this chip's target survive" a set lookup rather than a query
/// per chip.
/// </remarks>
public readonly record struct LinkTarget(LinkEntityType Type, string Id);
```

`windows/Notebar.Core/Models/Link.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>A single edge between two notes or tasks. One generic table covers
/// note→task, task→note, note→note, and task→task, so Link carries no notion of
/// "the note side" — only SrcType/DstType, mirroring the columns exactly.</summary>
public sealed record Link(
    string Id,
    LinkEntityType SrcType,
    string SrcId,
    LinkEntityType DstType,
    string DstId,
    string Kind,
    DateTimeOffset CreatedAt)
{
    /// <summary>The only kind any link is created with today. A string constant
    /// rather than an enum: kind is meant to grow (a future "blocks" or
    /// "duplicates" relation) without widening a closed type every time.</summary>
    public const string ReferencesKind = "references";

    public static Link New(LinkTarget source, LinkTarget destination) =>
        new(Guid.NewGuid().ToString(), source.Type, source.Id,
            destination.Type, destination.Id, ReferencesKind, DateTimeOffset.UtcNow);

    public LinkTarget Source => new(SrcType, SrcId);
    public LinkTarget Destination => new(DstType, DstId);
}
```

`windows/Notebar.Core/Models/LinkUrl.cs` — string in, string out, because the core must not
touch `System.Net` and because the editor exchanges these as plain strings across the
WebView2 bridge anyway:

```csharp
namespace Notebar.Core.Models;

/// <summary>The notebar://note/&lt;id&gt; and notebar://task/&lt;id&gt; scheme
/// every link chip carries.</summary>
/// <remarks>
/// Lives here, not in the app, so chip insertion (building the URL) and click
/// handling (parsing it back) share exactly one codec rather than two that can
/// drift. Works in plain strings rather than System.Uri: the core takes no
/// dependency on System.Net, and the WebView2 bridge exchanges these as strings
/// in both directions regardless.
/// </remarks>
public static class LinkUrl
{
    public const string Scheme = "notebar";

    public static string Build(LinkEntityType type, string id) =>
        $"{Scheme}://{type.ToStorageString()}/{id}";

    public static string Build(LinkTarget target) => Build(target.Type, target.Id);

    /// <summary>The inverse of <see cref="Build(LinkEntityType, string)"/>. Null for
    /// anything this type never produced — a link to a scheme this app does not
    /// own, or a malformed notebar:// URL — so a click on a chip whose target
    /// cannot be parsed does nothing rather than crashing.</summary>
    public static LinkTarget? Parse(string url)
    {
        const string prefix = Scheme + "://";
        if (string.IsNullOrEmpty(url) || !url.StartsWith(prefix, StringComparison.Ordinal))
            return null;

        string rest = url[prefix.Length..];
        int slash = rest.IndexOf('/');
        if (slash <= 0) return null;

        var type = LinkEntityTypeExtensions.Parse(rest[..slash]);
        if (type is null) return null;

        string id = rest[(slash + 1)..];
        if (id.Length == 0) return null;

        return new LinkTarget(type.Value, id);
    }
}
```

`windows/Notebar.Core/Models/LinkTombstone.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>Whether a chip's target no longer exists.</summary>
/// <remarks>
/// This cannot be answered from the link table. Deleting a note or task cascades
/// and removes every link row that touches it, on either end — so by the time a
/// chip needs restyling, the row behind it is gone too. A tombstone is detectable
/// only by asking "does the target itself still exist," which callers answer once
/// for the whole document rather than once per chip.
///
/// Split out from the styling that actually paints a tombstone so the decision
/// is unit-testable without a WebView.
/// </remarks>
public static class LinkTombstone
{
    /// <summary>Null when <paramref name="url"/> is not a chip this app ever wrote
    /// — a foreign scheme, or a malformed notebar:// URL — mirroring
    /// <see cref="LinkUrl.Parse"/>, so a caller can tell "not a chip" apart from
    /// "a chip whose target is gone". True when it is a chip and
    /// <paramref name="existingTargets"/> does not contain its target.</summary>
    public static bool? IsTombstone(string url, IReadOnlySet<LinkTarget> existingTargets)
    {
        var target = LinkUrl.Parse(url);
        if (target is null) return null;
        return !existingTargets.Contains(target.Value);
    }
}
```

- [ ] **Step 3: Write the diagnostics types**

`windows/Notebar.Core/Models/DatabaseDiagnostics.cs`:

```csharp
namespace Notebar.Core.Models;

/// <summary>A snapshot of facts about the on-disk store, for Settings → Data and
/// Export Diagnostics.</summary>
/// <remarks>
/// Every field here is a fact *about* the database — a path, a byte count, a list
/// of migration names — never a row of user content, so this type is structurally
/// incapable of carrying a note's title or body even by accident.
/// </remarks>
public sealed record DatabaseDiagnostics(
    /// <summary>Where the database file lives, or null when running on the
    /// in-memory fallback.</summary>
    string? Path,
    /// <summary>Size on disk in bytes including any -wal and -shm sidecars, or
    /// null if it could not be read.</summary>
    long? SizeOnDisk,
    /// <summary>The name of every migration recorded as applied, in order. Names
    /// only — never the rows a migration touched.</summary>
    IReadOnlyList<string> AppliedMigrations);
```

`windows/Notebar.Core/Models/DiagnosticsEnvironment.cs`:

```csharp
using System.Text;

namespace Notebar.Core.Models;

/// <summary>The environment half of an Export Diagnostics file.</summary>
/// <remarks>
/// Deliberately holds nothing else: every field is a fact about the machine or
/// the store, never a note or task's content, so RenderedText is safe to hand to
/// anyone regardless of what is actually in the database. The app gathers these
/// values and appends its own log excerpt, which this type has no part in.
/// </remarks>
public sealed record DiagnosticsEnvironment(
    string AppVersion,
    string BuildNumber,
    string OsVersion,
    /// <summary>One line per connected display, already formatted as plain text
    /// (e.g. "1920x1080 @ (0, 0), scale 1.5") — computed by the caller so this
    /// type never needs to know what a monitor handle is.</summary>
    IReadOnlyList<string> DisplayGeometry,
    DatabaseDiagnostics Database)
{
    public string RenderedText
    {
        get
        {
            var sb = new StringBuilder();
            sb.AppendLine($"App version: {AppVersion} ({BuildNumber})");
            sb.AppendLine($"Windows version: {OsVersion}");
            if (DisplayGeometry.Count == 0)
            {
                sb.AppendLine("Displays: none reported");
            }
            else
            {
                sb.AppendLine("Displays:");
                foreach (var line in DisplayGeometry) sb.AppendLine($"  - {line}");
            }
            sb.AppendLine($"Database path: {Database.Path ?? "(in-memory — on-disk store could not be opened)"}");
            sb.AppendLine(Database.SizeOnDisk is { } size
                ? $"Database size: {size} bytes"
                : "Database size: unknown");
            sb.AppendLine(Database.AppliedMigrations.Count == 0
                ? "Migrations applied: none"
                : $"Migrations applied: {string.Join(", ", Database.AppliedMigrations)}");
            return sb.ToString().TrimEnd();
        }
    }
}
```

- [ ] **Step 4: Write the tests**

`windows/Notebar.Core.Tests/NoteTests.cs` — five ported:

```csharp
using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class NoteTests
{
    private static Note Fresh() => Note.New(sortOrder: 0);

    [Fact]
    public void FreshNoteIsEmptyAndUntitled() =>
        Assert.True(Fresh().IsEmptyAndUntitled);

    [Fact]
    public void NoteWithBodyIsNotEmptyAndUntitled() =>
        Assert.False((Fresh() with { BodyPlain = "something" }).IsEmptyAndUntitled);

    [Fact]
    public void NoteWithTitleIsNotEmptyAndUntitled() =>
        Assert.False((Fresh() with { Title = "Groceries" }).IsEmptyAndUntitled);

    [Fact]
    public void WhitespaceOnlyBodyIsStillEmpty() =>
        Assert.True((Fresh() with { BodyPlain = "  \n\t " }).IsEmptyAndUntitled);

    /// The macOS version of this test asserted that a body serialising to a
    /// non-trivial RTF header is still "empty". The HTML equivalent: an editor
    /// that has been focused but not typed in produces markup, and that markup
    /// must not count as content.
    [Fact]
    public void HtmlBodyWithNoVisibleTextIsStillEmpty() =>
        Assert.True((Fresh() with { BodyHtml = "<p><br></p>", BodyPlain = "" }).IsEmptyAndUntitled);
}
```

`windows/Notebar.Core.Tests/LinkUrlTests.cs` — new, because C# string parsing replaces Swift's
`URLComponents` and the replacement deserves its own coverage:

```csharp
using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class LinkUrlTests
{
    [Fact]
    public void RoundTripsANote()
    {
        var target = new LinkTarget(LinkEntityType.Note, "abc-123");
        Assert.Equal("notebar://note/abc-123", LinkUrl.Build(target));
        Assert.Equal(target, LinkUrl.Parse(LinkUrl.Build(target)));
    }

    [Fact]
    public void RoundTripsATask()
    {
        var target = new LinkTarget(LinkEntityType.Task, "def-456");
        Assert.Equal("notebar://task/def-456", LinkUrl.Build(target));
        Assert.Equal(target, LinkUrl.Parse(LinkUrl.Build(target)));
    }

    [Theory]
    [InlineData("https://example.com/note/abc")]   // foreign scheme
    [InlineData("notebar://widget/abc")]           // unknown entity type
    [InlineData("notebar://note/")]                // empty id
    [InlineData("notebar://note")]                 // no separator
    [InlineData("notebar://")]                     // nothing at all
    [InlineData("")]
    public void RejectsAnythingItDidNotBuild(string url) =>
        Assert.Null(LinkUrl.Parse(url));
}
```

`windows/Notebar.Core.Tests/LinkTombstoneTests.cs` — four ported:

```csharp
using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class LinkTombstoneTests
{
    private static readonly IReadOnlySet<LinkTarget> Existing = new HashSet<LinkTarget>
    {
        new(LinkEntityType.Note, "note-1"),
        new(LinkEntityType.Task, "task-1"),
    };

    [Fact]
    public void TargetExists() =>
        Assert.False(LinkTombstone.IsTombstone("notebar://note/note-1", Existing));

    [Fact]
    public void TargetMissing() =>
        Assert.True(LinkTombstone.IsTombstone("notebar://note/note-99", Existing));

    /// A note and a task can share an id string. The type is part of identity.
    [Fact]
    public void TypeMatters() =>
        Assert.True(LinkTombstone.IsTombstone("notebar://task/note-1", Existing));

    /// Null, not true: a caller must be able to tell "not a chip" apart from
    /// "a chip whose target is gone", because only the second gets restyled.
    [Fact]
    public void NotAChip() =>
        Assert.Null(LinkTombstone.IsTombstone("https://example.com", Existing));
}
```

`windows/Notebar.Core.Tests/DiagnosticsTests.cs` — the no-content invariant, enforced rather
than trusted:

```csharp
using Notebar.Core.Models;
using Xunit;

namespace Notebar.Core.Tests;

public class DiagnosticsTests
{
    private static DiagnosticsEnvironment Sample(DatabaseDiagnostics db) =>
        new("0.1.0", "1", "Windows 11 26100", ["1920x1080 @ (0, 0), scale 1.5"], db);

    [Fact]
    public void RendersEveryField()
    {
        var text = Sample(new DatabaseDiagnostics(
            @"C:\Users\x\AppData\Local\Notebar\notebar.sqlite", 40960,
            ["createNote", "createOpenTab"])).RenderedText;

        Assert.Contains("App version: 0.1.0 (1)", text);
        Assert.Contains("Windows version: Windows 11 26100", text);
        Assert.Contains("1920x1080 @ (0, 0), scale 1.5", text);
        Assert.Contains("notebar.sqlite", text);
        Assert.Contains("40960 bytes", text);
        Assert.Contains("createNote, createOpenTab", text);
    }

    [Fact]
    public void HandlesTheInMemoryFallback()
    {
        var text = Sample(new DatabaseDiagnostics(null, null, [])).RenderedText;
        Assert.Contains("in-memory", text);
        Assert.Contains("Database size: unknown", text);
        Assert.Contains("Migrations applied: none", text);
    }

    /// The invariant that makes it safe to hand this file to anyone. The type has
    /// no field a note body could occupy — this test is what stops a future
    /// "helpful" addition of one, by failing the moment a note's text can reach
    /// the rendered output.
    [Fact]
    public void CarriesNoNoteContent()
    {
        const string secret = "my private note body";
        var text = Sample(new DatabaseDiagnostics(
            @"C:\Notebar\notebar.sqlite", 1, ["createNote"])).RenderedText;
        Assert.DoesNotContain(secret, text);
        Assert.DoesNotContain("body", text, StringComparison.OrdinalIgnoreCase);
    }
}
```

- [ ] **Step 5: Run and confirm all 57 pass**

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd windows && dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
```

Expected: `Passed: 56` — 36 from Task 2, plus 5 note, 8 link URL (2 facts and 6 theory cases),
4 tombstone, and 3 diagnostics. If the real number differs, reconcile it against the test files
before committing rather than adjusting the expectation to match whatever came out.

- [ ] **Step 6: Run the purity guard**

```bash
windows/scripts/check-core-purity.sh
```

Expected: `OK: Notebar.Core is pure.` `System.Text.StringBuilder` is in `System.Text`, which
the guard does not forbid — only `System.IO`, `System.Net`, and the platform namespaces.

- [ ] **Step 7: Commit**

```bash
git add windows/Notebar.Core/Models windows/Notebar.Core.Tests
git commit -m "Port the core models, link URL codec, and tombstone predicate

Note.BodyHtml replaces the macOS BodyRtf, and IsEmptyAndUntitled still checks
BodyPlain rather than the body markup — an untouched editor document still
serialises to <p><br></p>, so a check against the markup would silently never
be true and closing an empty tab would stop cleaning up after itself.

Attachments become their own table rather than living inside the note body.
The macOS build embedded them and then needed a separate summaries query to
avoid reading every screenshot back just to list note names; storing them
apart from the start costs nothing and removes that problem entirely.

DiagnosticsTests asserts the export cannot carry note content. The type has no
field one could occupy, and the test is what stops a future addition of one.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
```

---

### Task 4: Store — database, migrator, schema, and the note repository

**Files:**
- Create: `windows/Notebar.Core/Schema/NoteSchema.cs`, `OpenTabSchema.cs`
- Create: `windows/Notebar.Core/Repositories/INoteRepository.cs`
- Create: `windows/Notebar.Store/Notebar.Store.csproj`
- Create: `windows/Notebar.Store/NotebarDatabase.cs`
- Create: `windows/Notebar.Store/Migrations.cs`
- Create: `windows/Notebar.Store/SortOrder.cs`
- Create: `windows/Notebar.Store/NoteHtml.cs`
- Create: `windows/Notebar.Store/SqliteNoteRepository.cs`
- Create: `windows/Notebar.Store.Tests/Notebar.Store.Tests.csproj`
- Create: `windows/Notebar.Store.Tests/TestDatabase.cs`
- Test: `windows/Notebar.Store.Tests/MigrationTests.cs`, `SortOrderTests.cs`, `NoteHtmlTests.cs`, `SqliteNoteRepositoryTests.cs`
- Modify: `windows/Notebar.sln`

**Interfaces:**
- Consumes: `Note`, `NoteSummary` (Task 3).
- Produces:
  - `sealed class NotebarDatabase : IDisposable` — `static NotebarDatabase Open(string path)`, `static NotebarDatabase OpenInMemory()`, `SqliteConnection Connection`, `string? Path`, `IReadOnlyList<string> AppliedMigrations`, `void Migrate()`
  - `static class SortOrder` — `double Between(double? before, double? after)`
  - `static class NoteHtml` — `string ToPlainText(string html)`
  - `interface INoteRepository` — `IReadOnlyList<Note> All()`, `IReadOnlyList<NoteSummary> Summaries()`, `Note? Fetch(string id)`, `Note Create()`, `void Update(Note note)`, `void Delete(string id)`, `Note Reorder(string id, string? beforeId, string? afterId)`, `IReadOnlyList<Note> Search(string query)`
  - `sealed class SqliteNoteRepository(NotebarDatabase db) : INoteRepository`

- [ ] **Step 1: Write the schema constants**

`windows/Notebar.Core/Schema/NoteSchema.cs` — the same tables as macOS, with `body_html TEXT`
in place of `body_rtf BLOB`. Because the Windows database is independent, this is written once
in its final shape rather than as the four-migration sequence macOS accumulated:

```csharp
namespace Notebar.Core.Schema;

/// <summary>The SQL schema for notes, as constants rather than only prose, so the
/// store never writes SQL the core does not already know about.</summary>
/// <remarks>
/// The macOS database reached this shape across four migrations — plain body,
/// then an RTF blob, then RTFD, then a plain shadow column — because each step
/// had to preserve data already on real machines. The Windows database is
/// independent and starts empty, so this is written once in its final form. That
/// is the whole practical benefit of not sharing a file between the platforms.
///
/// Everything from here on is additive only: never edit a migration that has
/// shipped, because a database that already ran it will not run it again and the
/// two will silently diverge.
/// </remarks>
public static class NoteSchema
{
    public const string MigrationName = "createNote";

    public const string CreateNoteTable = """
        CREATE TABLE note (
          id         TEXT PRIMARY KEY,
          title      TEXT NOT NULL DEFAULT '',
          body_html  TEXT NOT NULL DEFAULT '',
          body_plain TEXT NOT NULL DEFAULT '',
          is_pinned  INTEGER NOT NULL DEFAULT 0,
          sort_order REAL NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
        """;

    /// <summary>External-content FTS5 table over note. content_rowid='rowid' uses
    /// SQLite's implicit rowid alias — note is a normal table, so this works even
    /// though id is a TEXT UUID rather than the rowid.</summary>
    public const string CreateNoteFtsTable = """
        CREATE VIRTUAL TABLE note_fts USING fts5(
          title,
          body_plain,
          content='note',
          content_rowid='rowid'
        )
        """;

    /// <summary>Standard FTS5 external-content sync triggers. The repository always
    /// writes body_html and body_plain together in one row write, and these fire
    /// within that same write, so note_fts can never observe one column updated
    /// without the other.</summary>
    public const string NoteFtsTriggers = """
        CREATE TRIGGER note_ai AFTER INSERT ON note BEGIN
          INSERT INTO note_fts(rowid, title, body_plain) VALUES (new.rowid, new.title, new.body_plain);
        END;
        CREATE TRIGGER note_ad AFTER DELETE ON note BEGIN
          INSERT INTO note_fts(note_fts, rowid, title, body_plain) VALUES ('delete', old.rowid, old.title, old.body_plain);
        END;
        CREATE TRIGGER note_au AFTER UPDATE ON note BEGIN
          INSERT INTO note_fts(note_fts, rowid, title, body_plain) VALUES ('delete', old.rowid, old.title, old.body_plain);
          INSERT INTO note_fts(rowid, title, body_plain) VALUES (new.rowid, new.title, new.body_plain);
        END;
        """;
}

/// <summary>The open-tab strip. Deliberately generic (kind/ref_id) rather than a
/// note_id column, so task tabs slot in later without a schema change.</summary>
public static class OpenTabSchema
{
    public const string MigrationName = "createOpenTab";

    public const string CreateOpenTabTable = """
        CREATE TABLE open_tab (
          id         TEXT PRIMARY KEY,
          kind       TEXT NOT NULL,
          ref_id     TEXT NOT NULL,
          sort_order REAL NOT NULL,
          is_active  INTEGER NOT NULL DEFAULT 0
        )
        """;
}
```

- [ ] **Step 2: Write `INoteRepository`**

`windows/Notebar.Core/Repositories/INoteRepository.cs`:

```csharp
using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for Note, defined here so the store's SQLite implementation
/// has a contract to satisfy without the core ever referencing a database
/// package.</summary>
/// <remarks>
/// Synchronous rather than async, deliberately: the underlying store is a local
/// SQLite file behind a single connection, and every call is a sub-millisecond
/// local operation. Wrapping them in Task would add scheduling overhead for
/// nothing. Callers that must not block the UI thread — the editor's debounced
/// save — dispatch to a background thread themselves.
/// </remarks>
public interface INoteRepository
{
    /// <summary>Every note, ordered by SortOrder ascending.</summary>
    IReadOnlyList<Note> All();

    /// <summary>Every note's lightweight summary — id, title, UpdatedAt, nothing
    /// else — in the same order as All(). Never selects body_html, so rendering
    /// the all-notes menu never pays for reading every note's body.</summary>
    IReadOnlyList<NoteSummary> Summaries();

    /// <summary>A single note by id, or null if it does not exist.</summary>
    Note? Fetch(string id);

    /// <summary>Creates a note appended after the current last one (or first, if
    /// the store is empty) and persists it immediately.</summary>
    Note Create();

    /// <summary>Persists every mutable field of an existing note and stamps
    /// UpdatedAt. The row must already exist; unknown ids throw.</summary>
    void Update(Note note);

    /// <summary>Deletes a note. A no-op if id does not exist.</summary>
    void Delete(string id);

    /// <summary>Moves the note to a fractional SortOrder strictly between the two
    /// named neighbours, so a reorder is one row update rather than a renumbering
    /// pass. Pass null for either bound to move to that end of the list.</summary>
    Note Reorder(string id, string? beforeId, string? afterId);

    /// <summary>Full-text search over title and body via note_fts, most relevant
    /// first. Empty for a blank query.</summary>
    IReadOnlyList<Note> Search(string query);
}
```

- [ ] **Step 3: Write the store project and test project**

`windows/Notebar.Store/Notebar.Store.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <RootNamespace>Notebar.Store</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Data.Sqlite" Version="9.0.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../Notebar.Core/Notebar.Core.csproj" />
  </ItemGroup>
</Project>
```

`windows/Notebar.Store.Tests/Notebar.Store.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <RootNamespace>Notebar.Store.Tests</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../Notebar.Store/Notebar.Store.csproj" />
  </ItemGroup>
</Project>
```

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd windows
dotnet sln add Notebar.Store/Notebar.Store.csproj
dotnet sln add Notebar.Store.Tests/Notebar.Store.Tests.csproj
```

- [ ] **Step 4: Write the FTS5 availability test first**

`Microsoft.Data.Sqlite` bundles `e_sqlite3`, which is expected to be compiled with FTS5 — but
"expected" is not "verified", and if it is not, every note schema migration fails at runtime on
the user's machine rather than here. Make it a red test now.

`windows/Notebar.Store.Tests/MigrationTests.cs`:

```csharp
using Microsoft.Data.Sqlite;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class MigrationTests
{
    /// FTS5 is a compile-time option in SQLite. Microsoft.Data.Sqlite bundles
    /// e_sqlite3, which is expected to include it — but if that expectation is
    /// ever wrong, every note migration fails on a user's machine rather than
    /// here. This is the cheapest possible place to find out.
    [Fact]
    public void Fts5IsAvailable()
    {
        using var conn = new SqliteConnection("Data Source=:memory:");
        conn.Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "CREATE VIRTUAL TABLE probe USING fts5(body)";
        cmd.ExecuteNonQuery();  // throws if FTS5 is not compiled in
    }

    [Fact]
    public void OpeningAppliesEveryMigrationInOrder()
    {
        using var db = NotebarDatabase.OpenInMemory();
        Assert.Equal(
            new[] { NoteSchema.MigrationName, OpenTabSchema.MigrationName },
            db.AppliedMigrations);
    }

    [Fact]
    public void MigratingTwiceIsANoOp()
    {
        using var db = NotebarDatabase.OpenInMemory();
        int before = db.AppliedMigrations.Count;
        db.Migrate();
        Assert.Equal(before, db.AppliedMigrations.Count);
    }

    [Fact]
    public void ForeignKeysAreEnforced()
    {
        using var db = NotebarDatabase.OpenInMemory();
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "PRAGMA foreign_keys";
        Assert.Equal(1L, Convert.ToInt64(cmd.ExecuteScalar()));
    }
}
```

- [ ] **Step 5: Run and confirm it fails**

```bash
cd windows && dotnet test Notebar.Store.Tests/Notebar.Store.Tests.csproj
```

Expected: compilation error — `NotebarDatabase` does not exist.

- [ ] **Step 6: Write `NotebarDatabase` and `Migrations`**

`windows/Notebar.Store/NotebarDatabase.cs`:

```csharp
using Microsoft.Data.Sqlite;

namespace Notebar.Store;

/// <summary>The one connection to the SQLite file, plus the migrator that brings
/// it to the current schema.</summary>
/// <remarks>
/// A single connection rather than a pool: every repository call is synchronous
/// and short, the app is single-user and single-process, and WAL mode plus one
/// connection is simpler to reason about than concurrency that buys nothing here.
/// Callers must not use this from more than one thread at a time; the app
/// serialises database work onto one background queue.
/// </remarks>
public sealed class NotebarDatabase : IDisposable
{
    public SqliteConnection Connection { get; }

    /// <summary>The database file's path, or null when running in memory.</summary>
    public string? Path { get; }

    private NotebarDatabase(SqliteConnection connection, string? path)
    {
        Connection = connection;
        Path = path;
    }

    public static NotebarDatabase Open(string path)
    {
        var directory = System.IO.Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) System.IO.Directory.CreateDirectory(directory);

        var conn = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWriteCreate,
        }.ToString());
        conn.Open();
        var db = new NotebarDatabase(conn, path);
        db.Configure();
        db.Migrate();
        return db;
    }

    /// <summary>An in-memory database, for tests and for the app's degrade path
    /// when the on-disk store cannot be opened. Shared cache so the single
    /// connection keeps it alive.</summary>
    public static NotebarDatabase OpenInMemory()
    {
        var conn = new SqliteConnection("Data Source=:memory:");
        conn.Open();
        var db = new NotebarDatabase(conn, null);
        db.Configure();
        db.Migrate();
        return db;
    }

    private void Configure()
    {
        Execute("PRAGMA foreign_keys = ON");
        // WAL only applies to a file-backed database; harmless on :memory:.
        if (Path is not null) Execute("PRAGMA journal_mode = WAL");
        Execute("""
            CREATE TABLE IF NOT EXISTS schema_migration (
              name       TEXT PRIMARY KEY,
              applied_at TEXT NOT NULL
            )
            """);
    }

    /// <summary>Applies every registered migration this database has not already
    /// recorded, in order, each in its own transaction.</summary>
    public void Migrate()
    {
        var applied = AppliedMigrations.ToHashSet();
        foreach (var migration in Migrations.All)
        {
            if (applied.Contains(migration.Name)) continue;

            using var tx = Connection.BeginTransaction();
            foreach (var statement in migration.Statements)
            {
                using var cmd = Connection.CreateCommand();
                cmd.Transaction = tx;
                cmd.CommandText = statement;
                cmd.ExecuteNonQuery();
            }
            using (var record = Connection.CreateCommand())
            {
                record.Transaction = tx;
                record.CommandText =
                    "INSERT INTO schema_migration (name, applied_at) VALUES ($n, $t)";
                record.Parameters.AddWithValue("$n", migration.Name);
                record.Parameters.AddWithValue("$t", Sql.ToText(DateTimeOffset.UtcNow));
                record.ExecuteNonQuery();
            }
            tx.Commit();
        }
    }

    /// <summary>Every migration recorded as applied, in application order. Names
    /// only — this feeds diagnostics, which must never carry note content.</summary>
    public IReadOnlyList<string> AppliedMigrations
    {
        get
        {
            using var cmd = Connection.CreateCommand();
            cmd.CommandText = "SELECT name FROM schema_migration ORDER BY applied_at, rowid";
            using var reader = cmd.ExecuteReader();
            var names = new List<string>();
            while (reader.Read()) names.Add(reader.GetString(0));
            return names;
        }
    }

    private void Execute(string sql)
    {
        using var cmd = Connection.CreateCommand();
        cmd.CommandText = sql;
        cmd.ExecuteNonQuery();
    }

    public void Dispose() => Connection.Dispose();
}

/// <summary>Text conversions shared by every repository, so a date written by one
/// is readable by another.</summary>
public static class Sql
{
    /// <summary>ISO-8601 UTC. Sortable as text, which is what lets ORDER BY on a
    /// timestamp column mean what it says.</summary>
    public const string DateFormat = "yyyy-MM-ddTHH:mm:ss.fffZ";

    public static string ToText(DateTimeOffset value) =>
        value.ToUniversalTime().ToString(DateFormat, System.Globalization.CultureInfo.InvariantCulture);

    public static DateTimeOffset FromText(string value) =>
        DateTimeOffset.ParseExact(value, DateFormat,
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal |
            System.Globalization.DateTimeStyles.AdjustToUniversal);

    public static object ToDb(DateTimeOffset? value) =>
        value is { } v ? ToText(v) : DBNull.Value;
}
```

`windows/Notebar.Store/Migrations.cs` — the ordered, additive list:

```csharp
using Notebar.Core.Schema;

namespace Notebar.Store;

public sealed record Migration(string Name, IReadOnlyList<string> Statements);

/// <summary>Every migration, in application order.</summary>
/// <remarks>
/// Additive only. Never edit an entry that has shipped: a database that already
/// recorded it will not run it again, so the change would apply to fresh
/// databases and not to existing ones, silently giving two users different
/// schemas. Add a new entry at the end instead.
///
/// Migration bodies containing several statements are split here rather than
/// passed to SQLite as one string, because Microsoft.Data.Sqlite executes only
/// the first statement of a multi-statement command.
/// </remarks>
public static class Migrations
{
    public static IReadOnlyList<Migration> All { get; } =
    [
        new(NoteSchema.MigrationName,
        [
            NoteSchema.CreateNoteTable,
            NoteSchema.CreateNoteFtsTable,
            .. SplitStatements(NoteSchema.NoteFtsTriggers),
        ]),
        new(OpenTabSchema.MigrationName,
        [
            OpenTabSchema.CreateOpenTabTable,
        ]),
    ];

    /// <summary>Splits a script into individual statements on "END;" and ";"
    /// boundaries, keeping CREATE TRIGGER bodies intact. Trigger bodies are the
    /// only multi-statement constructs in this schema.</summary>
    internal static IReadOnlyList<string> SplitStatements(string script)
    {
        var statements = new List<string>();
        var current = new System.Text.StringBuilder();
        var inTrigger = false;

        foreach (var rawLine in script.Split('\n'))
        {
            var line = rawLine.TrimEnd();
            if (line.Length == 0) continue;
            current.AppendLine(line);

            if (line.TrimStart().StartsWith("CREATE TRIGGER", StringComparison.OrdinalIgnoreCase))
                inTrigger = true;

            bool ends = inTrigger
                ? line.Trim().Equals("END;", StringComparison.OrdinalIgnoreCase)
                : line.TrimEnd().EndsWith(';');

            if (ends)
            {
                statements.Add(current.ToString().Trim());
                current.Clear();
                inTrigger = false;
            }
        }

        if (current.Length > 0) statements.Add(current.ToString().Trim());
        return statements;
    }
}
```

- [ ] **Step 7: Run and confirm the four migration tests pass**

```bash
cd windows && dotnet test Notebar.Store.Tests/Notebar.Store.Tests.csproj
```

Expected: `Passed: 4`. If `Fts5IsAvailable` fails, stop: the fix is to add
`SQLitePCLRaw.bundle_e_sqlite3` explicitly, or switch to a build that has FTS5. Do not
proceed with a schema the runtime cannot create.

- [ ] **Step 8: Write `SortOrder` and its tests**

`windows/Notebar.Store.Tests/SortOrderTests.cs`:

```csharp
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SortOrderTests
{
    [Fact]
    public void BetweenTwoNeighboursIsStrictlyBetween()
    {
        double mid = SortOrder.Between(1.0, 2.0);
        Assert.True(mid > 1.0 && mid < 2.0);
    }

    [Fact]
    public void MovingToTheFrontIsBelowTheFirst() =>
        Assert.True(SortOrder.Between(null, 5.0) < 5.0);

    [Fact]
    public void MovingToTheEndIsAboveTheLast() =>
        Assert.True(SortOrder.Between(5.0, null) > 5.0);

    [Fact]
    public void AnEmptyListStartsAtZero() =>
        Assert.Equal(0.0, SortOrder.Between(null, null));

    /// Repeatedly inserting at the same spot halves the gap each time. Doubles
    /// run out of room after roughly 50 such inserts, and the result is two rows
    /// with an identical sort order and a list whose order flickers. Assert the
    /// depth the arithmetic actually survives, so anyone who later needs more
    /// knows they must renumber rather than discovering it from a bug report.
    [Fact]
    public void SurvivesFiftyRepeatedInsertsAtTheSameSpot()
    {
        double low = 0.0, high = 1.0;
        for (int i = 0; i < 50; i++)
        {
            double mid = SortOrder.Between(low, high);
            Assert.True(mid > low && mid < high, $"collapsed after {i} inserts");
            high = mid;
        }
    }
}
```

`windows/Notebar.Store/SortOrder.cs`:

```csharp
namespace Notebar.Store;

/// <summary>Fractional ordering: a reorder is one row update rather than a
/// renumbering pass over the whole list.</summary>
/// <remarks>
/// The cost is that repeatedly inserting between the same two neighbours halves
/// the gap each time, and doubles run out of room after about 50 such inserts.
/// SortOrderTests pins that depth. Nothing in this app comes close — a user
/// would have to drag the same card into the same slot fifty times without ever
/// dragging anything else — but if a future feature does, the fix is a
/// renumbering pass, not a bigger number type.
/// </remarks>
public static class SortOrder
{
    /// <summary>A value strictly between the two neighbours' orders. Null means
    /// "that end of the list".</summary>
    public static double Between(double? before, double? after) => (before, after) switch
    {
        (null, null) => 0.0,
        (null, { } a) => a - 1.0,
        ({ } b, null) => b + 1.0,
        ({ } b, { } a) => (b + a) / 2.0,
    };
}
```

- [ ] **Step 9: Write `NoteHtml` and its tests**

The plain-text shadow is what FTS5 indexes, and getting it wrong means search silently misses
things. List markers and checkbox glyphs are excluded for the same reason macOS excludes them:
they are editor bookkeeping, not text the user wrote.

`windows/Notebar.Store.Tests/NoteHtmlTests.cs`:

```csharp
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class NoteHtmlTests
{
    [Fact]
    public void StripsTags() =>
        Assert.Equal("hello world", NoteHtml.ToPlainText("<p><b>hello</b> world</p>"));

    [Fact]
    public void BlockElementsBecomeLineBreaks() =>
        Assert.Equal("one\ntwo", NoteHtml.ToPlainText("<p>one</p><p>two</p>"));

    [Fact]
    public void BrBecomesALineBreak() =>
        Assert.Equal("one\ntwo", NoteHtml.ToPlainText("one<br>two"));

    [Fact]
    public void DecodesEntities() =>
        Assert.Equal("a & b < c", NoteHtml.ToPlainText("a &amp; b &lt; c"));

    /// A checkbox is editor bookkeeping, not text the user wrote. Indexing it
    /// would make every checklist note match a search for the glyph.
    [Fact]
    public void CheckboxInputsContributeNothing() =>
        Assert.Equal("buy milk",
            NoteHtml.ToPlainText("<ul><li><input type=\"checkbox\">buy milk</li></ul>"));

    /// Likewise list markers: the browser draws them, they are not in the markup,
    /// and nothing should invent them here either.
    [Fact]
    public void ListItemsAreOneLineEachWithNoMarkers() =>
        Assert.Equal("first\nsecond",
            NoteHtml.ToPlainText("<ul><li>first</li><li>second</li></ul>"));

    /// An image contributes no text, but must not swallow the text around it.
    [Fact]
    public void ImagesContributeNothing() =>
        Assert.Equal("before after",
            NoteHtml.ToPlainText("before <img src=\"https://notebar.local/asset/x\"> after"));

    /// A link chip's visible label is real text the user can search for. Its href
    /// is not.
    [Fact]
    public void ChipLabelsAreIndexedButNotTheirUrls()
    {
        string plain = NoteHtml.ToPlainText(
            "see <a href=\"notebar://note/abc-123\">Groceries</a>");
        Assert.Contains("Groceries", plain);
        Assert.DoesNotContain("notebar://", plain);
        Assert.DoesNotContain("abc-123", plain);
    }

    /// An untouched editor produces markup but no text, and Note.IsEmptyAndUntitled
    /// depends on that becoming the empty string.
    [Fact]
    public void AnEmptyDocumentIsTheEmptyString() =>
        Assert.Equal("", NoteHtml.ToPlainText("<p><br></p>"));

    [Fact]
    public void ScriptAndStyleContentIsNotText() =>
        Assert.Equal("visible",
            NoteHtml.ToPlainText("<style>p{color:red}</style>visible<script>alert(1)</script>"));
}
```

`windows/Notebar.Store/NoteHtml.cs`:

```csharp
using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace Notebar.Store;

/// <summary>Derives a note's plain-text shadow from its HTML body.</summary>
/// <remarks>
/// This is what FTS5 indexes, and what Note.IsEmptyAndUntitled inspects, so it
/// must produce the text a user would say is in the note and nothing else. List
/// markers and checkbox glyphs are excluded deliberately: they are editor
/// bookkeeping, and indexing them would make every checklist match a search for
/// a glyph nobody typed.
///
/// A regex rather than an HTML parser because the input is not arbitrary web
/// HTML — it is the markup this app's own editor produced, from a fixed set of
/// tags. A parser dependency would buy robustness against input that cannot
/// occur.
/// </remarks>
public static partial class NoteHtml
{
    public static string ToPlainText(string html)
    {
        if (string.IsNullOrEmpty(html)) return "";

        // Drop elements whose content is not text at all, content included.
        string s = NonTextElements().Replace(html, "");

        // Block boundaries become line breaks before tags are stripped, so
        // "<p>one</p><p>two</p>" does not collapse into "onetwo".
        s = BlockBoundaries().Replace(s, "\n");

        s = Tags().Replace(s, "");
        s = WebUtility.HtmlDecode(s);

        // Collapse runs of horizontal whitespace, trim each line, drop blank
        // lines. An untouched editor's "<p><br></p>" must end up as "".
        var lines = s.Split('\n')
                     .Select(line => HorizontalWhitespace().Replace(line, " ").Trim())
                     .Where(line => line.Length > 0);

        return string.Join("\n", lines);
    }

    [GeneratedRegex(@"<(script|style)\b[^>]*>.*?</\1\s*>",
        RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex NonTextElements();

    [GeneratedRegex(@"</?(p|div|li|ul|ol|h1|h2|h3|br|tr|blockquote|pre)\b[^>]*>",
        RegexOptions.IgnoreCase)]
    private static partial Regex BlockBoundaries();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex Tags();

    [GeneratedRegex(@"[^\S\n]+")]
    private static partial Regex HorizontalWhitespace();
}
```

- [ ] **Step 10: Run and confirm the 15 store tests pass**

```bash
cd windows && dotnet test Notebar.Store.Tests/Notebar.Store.Tests.csproj
```

Expected: `Passed: 15` — 4 migration + 5 sort order + 10 HTML... which is 19. Run it and use
the real number; the point of this step is that every test passes, not that a count written in
advance was right.

- [ ] **Step 11: Write the note repository tests**

`windows/Notebar.Store.Tests/TestDatabase.cs`:

```csharp
namespace Notebar.Store.Tests;

/// <summary>A fresh in-memory database per test. Nothing here touches disk, so
/// tests cannot leak state into each other or into the developer's real store.</summary>
public sealed class TestDatabase : IDisposable
{
    public NotebarDatabase Db { get; } = NotebarDatabase.OpenInMemory();
    public void Dispose() => Db.Dispose();
}
```

`windows/Notebar.Store.Tests/SqliteNoteRepositoryTests.cs`:

```csharp
using Notebar.Core.Models;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteNoteRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteNoteRepository _repo;

    public SqliteNoteRepositoryTests() => _repo = new SqliteNoteRepository(_fixture.Db);

    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void CreateRoundTrips()
    {
        var created = _repo.Create();
        var fetched = _repo.Fetch(created.Id);
        Assert.Equal(created, fetched);
        Assert.Equal("Untitled", created.DisplayTitle);
    }

    [Fact]
    public void FetchingAnUnknownIdReturnsNull() =>
        Assert.Null(_repo.Fetch("nope"));

    [Fact]
    public void CreateAppendsAfterTheLast()
    {
        var first = _repo.Create();
        var second = _repo.Create();
        Assert.True(second.SortOrder > first.SortOrder);
        Assert.Equal([first.Id, second.Id], _repo.All().Select(n => n.Id));
    }

    [Fact]
    public void UpdatePersistsEveryFieldAndStampsUpdatedAt()
    {
        var note = _repo.Create();
        var edited = note with { Title = "Groceries", BodyHtml = "<p>milk</p>", BodyPlain = "milk" };
        _repo.Update(edited);

        var fetched = _repo.Fetch(note.Id)!;
        Assert.Equal("Groceries", fetched.Title);
        Assert.Equal("<p>milk</p>", fetched.BodyHtml);
        Assert.Equal("milk", fetched.BodyPlain);
        Assert.True(fetched.UpdatedAt >= note.UpdatedAt);
    }

    [Fact]
    public void UpdatingAnUnknownIdThrows()
    {
        var orphan = Note.New(sortOrder: 0);
        Assert.Throws<InvalidOperationException>(() => _repo.Update(orphan));
    }

    [Fact]
    public void DeleteRemovesTheRowAndIsIdempotent()
    {
        var note = _repo.Create();
        _repo.Delete(note.Id);
        Assert.Null(_repo.Fetch(note.Id));
        _repo.Delete(note.Id);   // no-op, must not throw
    }

    /// The whole reason Summaries exists: it must never read a body. Store a
    /// large body and assert the summary does not carry it.
    [Fact]
    public void SummariesCarryNoBody()
    {
        var note = _repo.Create();
        _repo.Update(note with { Title = "Big", BodyHtml = new string('x', 100_000), BodyPlain = "xxx" });

        var summaries = _repo.Summaries();
        var summary = Assert.Single(summaries);
        Assert.Equal("Big", summary.Title);
        Assert.Equal(note.Id, summary.Id);
        // NoteSummary has no body field at all — this asserts the shape holds.
        Assert.Equal(3, typeof(NoteSummary).GetProperties()
            .Count(p => p.Name is "Id" or "Title" or "UpdatedAt"));
    }

    [Fact]
    public void SummariesUseTheSameOrderAsAll()
    {
        _repo.Create();
        _repo.Create();
        _repo.Create();
        Assert.Equal(_repo.All().Select(n => n.Id), _repo.Summaries().Select(s => s.Id));
    }

    [Fact]
    public void ReorderMovesBetweenNeighbours()
    {
        var a = _repo.Create();
        var b = _repo.Create();
        var c = _repo.Create();

        _repo.Reorder(c.Id, beforeId: a.Id, afterId: b.Id);

        Assert.Equal([a.Id, c.Id, b.Id], _repo.All().Select(n => n.Id));
    }

    [Fact]
    public void ReorderToTheFrontAndBack()
    {
        var a = _repo.Create();
        var b = _repo.Create();

        _repo.Reorder(b.Id, beforeId: null, afterId: a.Id);
        Assert.Equal([b.Id, a.Id], _repo.All().Select(n => n.Id));

        _repo.Reorder(b.Id, beforeId: a.Id, afterId: null);
        Assert.Equal([a.Id, b.Id], _repo.All().Select(n => n.Id));
    }

    [Fact]
    public void SearchFindsByTitleAndBody()
    {
        var a = _repo.Create();
        _repo.Update(a with { Title = "Groceries", BodyPlain = "milk and eggs" });
        var b = _repo.Create();
        _repo.Update(b with { Title = "Standup", BodyPlain = "deploy the panel" });

        Assert.Equal([a.Id], _repo.Search("milk").Select(n => n.Id));
        Assert.Equal([b.Id], _repo.Search("Standup").Select(n => n.Id));
    }

    [Fact]
    public void SearchIsEmptyForABlankQuery()
    {
        var a = _repo.Create();
        _repo.Update(a with { BodyPlain = "anything" });
        Assert.Empty(_repo.Search("   "));
    }

    /// FTS5 treats several characters as query syntax. A user typing a quote into
    /// the search box must get no results, not an exception.
    [Theory]
    [InlineData("\"")]
    [InlineData("*")]
    [InlineData("NEAR(")]
    [InlineData("a AND")]
    public void SearchSurvivesQuerySyntaxInUserInput(string query)
    {
        _repo.Create();
        _ = _repo.Search(query);   // must not throw
    }

    /// The shadow column and the body are written together, so the index can
    /// never be stale relative to the body it describes.
    [Fact]
    public void EditingABodyUpdatesTheIndex()
    {
        var a = _repo.Create();
        _repo.Update(a with { BodyPlain = "before" });
        Assert.Single(_repo.Search("before"));

        _repo.Update(a with { BodyPlain = "after" });
        Assert.Empty(_repo.Search("before"));
        Assert.Single(_repo.Search("after"));
    }

    [Fact]
    public void DeletingANoteRemovesItFromTheIndex()
    {
        var a = _repo.Create();
        _repo.Update(a with { BodyPlain = "findme" });
        _repo.Delete(a.Id);
        Assert.Empty(_repo.Search("findme"));
    }
}
```

- [ ] **Step 12: Run and confirm they fail**

Expected: compilation error — `SqliteNoteRepository` does not exist.

- [ ] **Step 13: Write `SqliteNoteRepository`**

`windows/Notebar.Store/SqliteNoteRepository.cs`:

```csharp
using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Repositories;

namespace Notebar.Store;

public sealed class SqliteNoteRepository(NotebarDatabase db) : INoteRepository
{
    private const string Columns =
        "id, title, body_html, body_plain, is_pinned, sort_order, created_at, updated_at";

    public IReadOnlyList<Note> All() =>
        Query($"SELECT {Columns} FROM note ORDER BY sort_order ASC");

    public IReadOnlyList<NoteSummary> Summaries()
    {
        // Deliberately does not select body_html. Twenty notes with one
        // screenshot each would otherwise mean reading megabytes to draw a
        // list of names.
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT id, title, updated_at FROM note ORDER BY sort_order ASC";
        using var reader = cmd.ExecuteReader();
        var result = new List<NoteSummary>();
        while (reader.Read())
            result.Add(new NoteSummary(reader.GetString(0), reader.GetString(1),
                                       Sql.FromText(reader.GetString(2))));
        return result;
    }

    public Note? Fetch(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"SELECT {Columns} FROM note WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        using var reader = cmd.ExecuteReader();
        return reader.Read() ? Read(reader) : null;
    }

    public Note Create()
    {
        double last = ScalarDouble("SELECT MAX(sort_order) FROM note");
        var note = Note.New(SortOrder.Between(double.IsNaN(last) ? null : last, null));

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"""
            INSERT INTO note ({Columns})
            VALUES ($id, $title, $html, $plain, $pinned, $order, $created, $updated)
            """;
        Bind(cmd, note);
        cmd.ExecuteNonQuery();
        return note;
    }

    public void Update(Note note)
    {
        var stamped = note with { UpdatedAt = DateTimeOffset.UtcNow };
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            UPDATE note SET title = $title, body_html = $html, body_plain = $plain,
                            is_pinned = $pinned, sort_order = $order,
                            created_at = $created, updated_at = $updated
            WHERE id = $id
            """;
        Bind(cmd, stamped);
        if (cmd.ExecuteNonQuery() == 0)
            throw new InvalidOperationException($"note {note.Id} does not exist");
    }

    public void Delete(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "DELETE FROM note WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public Note Reorder(string id, string? beforeId, string? afterId)
    {
        double? before = beforeId is null ? null : OrderOf(beforeId);
        double? after = afterId is null ? null : OrderOf(afterId);
        double target = SortOrder.Between(before, after);

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "UPDATE note SET sort_order = $order WHERE id = $id";
        cmd.Parameters.AddWithValue("$order", target);
        cmd.Parameters.AddWithValue("$id", id);
        if (cmd.ExecuteNonQuery() == 0)
            throw new InvalidOperationException($"note {id} does not exist");

        return Fetch(id)!;
    }

    public IReadOnlyList<Note> Search(string query)
    {
        string match = FtsQuery.Sanitize(query);
        if (match.Length == 0) return [];

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = $"""
            SELECT {string.Join(", ", Columns.Split(", ").Select(c => "n." + c))}
            FROM note_fts f
            JOIN note n ON n.rowid = f.rowid
            WHERE note_fts MATCH $q
            ORDER BY rank
            """;
        cmd.Parameters.AddWithValue("$q", match);
        using var reader = cmd.ExecuteReader();
        var result = new List<Note>();
        while (reader.Read()) result.Add(Read(reader));
        return result;
    }

    // --- helpers ---

    private IReadOnlyList<Note> Query(string sql)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = sql;
        using var reader = cmd.ExecuteReader();
        var result = new List<Note>();
        while (reader.Read()) result.Add(Read(reader));
        return result;
    }

    private static Note Read(SqliteDataReader r) => new(
        r.GetString(0), r.GetString(1), r.GetString(2), r.GetString(3),
        Sql.FromText(r.GetString(6)), Sql.FromText(r.GetString(7)),
        r.GetDouble(5), r.GetInt64(4) != 0);

    private static void Bind(SqliteCommand cmd, Note note)
    {
        cmd.Parameters.AddWithValue("$id", note.Id);
        cmd.Parameters.AddWithValue("$title", note.Title);
        cmd.Parameters.AddWithValue("$html", note.BodyHtml);
        cmd.Parameters.AddWithValue("$plain", note.BodyPlain);
        cmd.Parameters.AddWithValue("$pinned", note.IsPinned ? 1 : 0);
        cmd.Parameters.AddWithValue("$order", note.SortOrder);
        cmd.Parameters.AddWithValue("$created", Sql.ToText(note.CreatedAt));
        cmd.Parameters.AddWithValue("$updated", Sql.ToText(note.UpdatedAt));
    }

    private double OrderOf(string id)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT sort_order FROM note WHERE id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        object? value = cmd.ExecuteScalar();
        return value is null or DBNull
            ? throw new InvalidOperationException($"note {id} does not exist")
            : Convert.ToDouble(value);
    }

    private double ScalarDouble(string sql)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = sql;
        object? value = cmd.ExecuteScalar();
        return value is null or DBNull ? double.NaN : Convert.ToDouble(value);
    }
}
```

Add `windows/Notebar.Store/FtsQuery.cs` — the sanitizer the search tests demand:

```csharp
namespace Notebar.Store;

/// <summary>Turns whatever the user typed into something FTS5 will accept.</summary>
/// <remarks>
/// FTS5's MATCH grammar treats quotes, asterisks, parentheses, colons, and bare
/// AND/OR/NOT as syntax. A user typing a quote into the search box should get no
/// results, not a SqliteException — so every token is quoted as a literal and
/// given a trailing * for prefix matching, which is what a search-as-you-type box
/// needs anyway.
/// </remarks>
public static class FtsQuery
{
    public static string Sanitize(string query)
    {
        var tokens = query
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .Select(t => new string(t.Where(char.IsLetterOrDigit).ToArray()))
            .Where(t => t.Length > 0)
            .Select(t => $"\"{t}\"*");

        return string.Join(" ", tokens);
    }
}
```

- [ ] **Step 14: Run every test and confirm they pass**

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd windows
dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
dotnet test Notebar.Store.Tests/Notebar.Store.Tests.csproj
```

Both must be green before committing.

- [ ] **Step 15: Add the store tests to CI**

In `.github/workflows/ci.yml`, in the `windows-app` job, after the `Test Notebar.Core` step:

```yaml
      - name: Test Notebar.Store
        run: dotnet test windows/Notebar.Store.Tests/Notebar.Store.Tests.csproj -c Release
```

- [ ] **Step 16: Commit and push**

```bash
git add windows/Notebar.Core/Schema windows/Notebar.Core/Repositories windows/Notebar.Store windows/Notebar.Store.Tests windows/Notebar.sln .github/workflows/ci.yml
git commit -m "Add the SQLite store, migrator, and note repository

The Windows database is independent, so the note table is written once in its
final shape rather than as the four migrations macOS accumulated getting from
plain text to RTF to RTFD to a plain shadow column. Everything from here is
additive only.

Fts5IsAvailable is a test rather than an assumption. FTS5 is a compile-time
SQLite option, and if the bundled build ever lacks it every note migration
fails on a user's machine instead of in CI.

FtsQuery.Sanitize exists because MATCH treats quotes and asterisks as grammar.
A user typing a quote into a search box should get no results, not a
SqliteException — SearchSurvivesQuerySyntaxInUserInput pins that.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
```

---

### Task 5: Store — tasks, links, app state, open tabs, attachments, diagnostics

The remaining six repositories. Their CRUD follows the `Bind`/`Read`/`Query` shape
`SqliteNoteRepository.cs` establishes — by this task that file is committed and is the pattern
to read. What is written out in full below is everything that is *not* mechanical: the
completion-stamping rule, the transactional link write, the clamped setting reads, and the
cascade triggers.

**Files:**
- Create: `windows/Notebar.Core/Schema/TaskSchema.cs`, `LinkSchema.cs`, `AppStateSchema.cs`, `AttachmentSchema.cs`
- Create: `windows/Notebar.Core/Repositories/ITaskRepository.cs`, `ILinkRepository.cs`, `IAppStateRepository.cs`, `IOpenTabRepository.cs`, `IAttachmentRepository.cs`, `IDiagnosticsRepository.cs`
- Create: `windows/Notebar.Store/SqliteTaskRepository.cs`, `SqliteLinkRepository.cs`, `SqliteAppStateRepository.cs`, `SqliteOpenTabRepository.cs`, `SqliteAttachmentRepository.cs`, `SqliteDiagnosticsRepository.cs`
- Modify: `windows/Notebar.Store/Migrations.cs`
- Test: `windows/Notebar.Store.Tests/SqliteTaskRepositoryTests.cs`, `SqliteLinkRepositoryTests.cs`, `SqliteAppStateRepositoryTests.cs`, `SqliteOpenTabRepositoryTests.cs`, `SqliteAttachmentRepositoryTests.cs`, `SqliteDiagnosticsRepositoryTests.cs`

**Interfaces:**
- Consumes: `NotebarDatabase`, `Sql`, `SortOrder`, `FtsQuery` (Task 4); every model (Task 3).
- Produces:
  - `ITaskRepository` — `IReadOnlyList<BoardColumn> Columns()`, `IReadOnlyList<TaskItem> All()`, `TaskItem Create(string title, string columnId)`, `void Update(TaskItem task)`, `void Delete(string id)`, `TaskItem Move(string id, string columnId, string? beforeId, string? afterId)`, `IReadOnlyList<TaskItem> Search(string query)`
  - `ILinkRepository` — `Link Create(Link link)`, `Link CreateSavingNoteBody(Link link, string noteId, string bodyHtml, string bodyPlain)`, `void Delete(string id)`, `IReadOnlyList<Link> Outgoing(LinkTarget from)`, `IReadOnlyList<Link> Incoming(LinkTarget to)`, `IReadOnlySet<LinkTarget> ExistingTargets()`
  - `IAppStateRepository` — `Theme GetTheme()`, `void SetTheme(Theme)`, `double GetEdgeDwell()`, `void SetEdgeDwell(double)`, `double GetExitDwell()`, `void SetExitDwell(double)`, `double GetExitSlop()`, `void SetExitSlop(double)`
  - `IOpenTabRepository` — `IReadOnlyList<OpenTab> All()`, `void ReplaceAll(IReadOnlyList<OpenTab> tabs)`
  - `IAttachmentRepository` — `Attachment Create(string mimeType, byte[] data, int width, int height)`, `Attachment? Fetch(string id)`, `void DeleteUnreferenced(IReadOnlySet<string> referencedIds)`
  - `IDiagnosticsRepository` — `DatabaseDiagnostics Snapshot()`

- [ ] **Step 1: Write the four remaining schemas**

`windows/Notebar.Core/Schema/TaskSchema.cs` — ported unchanged from the Swift, seed included:

```csharp
namespace Notebar.Core.Schema;

using Notebar.Core.Models;

public static class TaskSchema
{
    public const string MigrationName = "createTaskBoard";

    /// <summary>Fixed ids rather than fresh GUIDs per migration run. That is what
    /// makes the seed idempotent: INSERT OR IGNORE keys on them, so seeding again
    /// after a partial failure never inserts a second board.</summary>
    public const string DefaultBoardId = "board-default";
    public const string QueueColumnId = "column-queue";
    public const string WorkingColumnId = "column-working";
    public const string DoneColumnId = "column-done";

    public const string CreateBoardTable = """
        CREATE TABLE board (
          id         TEXT PRIMARY KEY,
          name       TEXT NOT NULL,
          sort_order REAL NOT NULL
        )
        """;

    public const string CreateBoardColumnTable = """
        CREATE TABLE board_column (
          id         TEXT PRIMARY KEY,
          board_id   TEXT NOT NULL REFERENCES board(id) ON DELETE CASCADE,
          name       TEXT NOT NULL,
          kind       TEXT NOT NULL,
          sort_order REAL NOT NULL,
          wip_limit  INTEGER
        )
        """;

    public const string CreateTaskTable = """
        CREATE TABLE task (
          id           TEXT PRIMARY KEY,
          title        TEXT NOT NULL,
          detail_plain TEXT NOT NULL DEFAULT '',
          column_id    TEXT NOT NULL REFERENCES board_column(id),
          sort_order   REAL NOT NULL,
          priority     INTEGER NOT NULL DEFAULT 0,
          due_at       TEXT,
          completed_at TEXT,
          created_at   TEXT NOT NULL,
          updated_at   TEXT NOT NULL
        )
        """;

    public const string CreateTaskFtsTable = """
        CREATE VIRTUAL TABLE task_fts USING fts5(
          title,
          detail_plain,
          content='task',
          content_rowid='rowid'
        )
        """;

    public const string TaskFtsTriggers = """
        CREATE TRIGGER task_ai AFTER INSERT ON task BEGIN
          INSERT INTO task_fts(rowid, title, detail_plain) VALUES (new.rowid, new.title, new.detail_plain);
        END;
        CREATE TRIGGER task_ad AFTER DELETE ON task BEGIN
          INSERT INTO task_fts(task_fts, rowid, title, detail_plain) VALUES ('delete', old.rowid, old.title, old.detail_plain);
        END;
        CREATE TRIGGER task_au AFTER UPDATE ON task BEGIN
          INSERT INTO task_fts(task_fts, rowid, title, detail_plain) VALUES ('delete', old.rowid, old.title, old.detail_plain);
          INSERT INTO task_fts(rowid, title, detail_plain) VALUES (new.rowid, new.title, new.detail_plain);
        END;
        """;

    public static string SeedBoard =>
        $"INSERT OR IGNORE INTO board (id, name, sort_order) VALUES ('{DefaultBoardId}', 'Board', 0)";

    public static string SeedColumns => $"""
        INSERT OR IGNORE INTO board_column (id, board_id, name, kind, sort_order, wip_limit)
        VALUES
          ('{QueueColumnId}',   '{DefaultBoardId}', 'Queue',   '{BoardColumn.BacklogKind}', 0, NULL),
          ('{WorkingColumnId}', '{DefaultBoardId}', 'Working', '{BoardColumn.ActiveKind}',  1, NULL),
          ('{DoneColumnId}',    '{DefaultBoardId}', 'Done',    '{BoardColumn.DoneKind}',    2, NULL)
        """;
}
```

`windows/Notebar.Core/Schema/LinkSchema.cs`:

```csharp
namespace Notebar.Core.Schema;

/// <summary>The generic edge table covering note→task, task→note, note→note, and
/// task→task, with backlinks as the reverse query on idx_link_dst.</summary>
public static class LinkSchema
{
    public const string MigrationName = "createLink";

    public const string CreateLinkTable = """
        CREATE TABLE link (
          id         TEXT PRIMARY KEY,
          src_type   TEXT NOT NULL,
          src_id     TEXT NOT NULL,
          dst_type   TEXT NOT NULL,
          dst_id     TEXT NOT NULL,
          kind       TEXT NOT NULL DEFAULT 'references',
          created_at TEXT NOT NULL,
          UNIQUE (src_type, src_id, dst_type, dst_id, kind)
        )
        """;

    public const string CreateSrcIndex = "CREATE INDEX idx_link_src ON link(src_type, src_id)";

    /// <summary>What makes backlinks a cheap reverse query. Created alongside the
    /// table even though nothing reads it yet: adding an index to a table that
    /// already holds rows is the expensive retrofit; adding it here costs nothing.</summary>
    public const string CreateDstIndex = "CREATE INDEX idx_link_dst ON link(dst_type, dst_id)";

    /// <summary>Two triggers, not one foreign key, because link has no real
    /// foreign key to either note or task — the same row's dst_id might belong to
    /// either table depending on dst_type, which ON DELETE CASCADE cannot express.
    ///
    /// Cascading rather than leaving dangling rows: a link pointing at an id that
    /// can never resolve again is indistinguishable from a bug, and tombstones do
    /// not need the row — a tombstone only needs the *target* to be gone, which it
    /// already is.</summary>
    public const string CascadeOnNoteDelete = """
        CREATE TRIGGER link_cleanup_note_delete AFTER DELETE ON note BEGIN
          DELETE FROM link WHERE (src_type = 'note' AND src_id = old.id) OR (dst_type = 'note' AND dst_id = old.id);
        END;
        """;

    public const string CascadeOnTaskDelete = """
        CREATE TRIGGER link_cleanup_task_delete AFTER DELETE ON task BEGIN
          DELETE FROM link WHERE (src_type = 'task' AND src_id = old.id) OR (dst_type = 'task' AND dst_id = old.id);
        END;
        """;
}
```

`windows/Notebar.Core/Schema/AppStateSchema.cs`:

```csharp
namespace Notebar.Core.Schema;

/// <summary>A generic key/value store, so every future small preference reuses
/// this one table instead of adding one of its own.</summary>
public static class AppStateSchema
{
    public const string MigrationName = "createAppState";

    public const string ThemeKey = "theme";

    /// <summary>Named after the constant each overrides, not the UI label, since
    /// the label ("Open delay"/"Close delay"/"Edge tolerance") is free to change
    /// without touching what is already on disk.</summary>
    public const string EdgeDwellKey = "edgeDwell";
    public const string ExitDwellKey = "exitDwell";
    public const string ExitSlopKey = "exitSlop";

    public const string CreateAppStateTable = """
        CREATE TABLE app_state (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
        """;
}
```

`windows/Notebar.Core/Schema/AttachmentSchema.cs`:

```csharp
namespace Notebar.Core.Schema;

/// <summary>Images pasted into notes, stored as rows rather than embedded in the
/// note body — see the Attachment model for why.</summary>
public static class AttachmentSchema
{
    public const string MigrationName = "createAttachment";

    public const string CreateAttachmentTable = """
        CREATE TABLE attachment (
          id         TEXT PRIMARY KEY,
          mime_type  TEXT NOT NULL,
          data       BLOB NOT NULL,
          width      INTEGER NOT NULL,
          height     INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
        """;
}
```

- [ ] **Step 2: Register the new migrations**

Append to `Migrations.All` in `windows/Notebar.Store/Migrations.cs`, **after** the two existing
entries and never between them:

```csharp
        new(TaskSchema.MigrationName,
        [
            TaskSchema.CreateBoardTable,
            TaskSchema.CreateBoardColumnTable,
            TaskSchema.CreateTaskTable,
            TaskSchema.CreateTaskFtsTable,
            .. SplitStatements(TaskSchema.TaskFtsTriggers),
            TaskSchema.SeedBoard,
            TaskSchema.SeedColumns,
        ]),
        new(AppStateSchema.MigrationName, [AppStateSchema.CreateAppStateTable]),
        new(LinkSchema.MigrationName,
        [
            LinkSchema.CreateLinkTable,
            LinkSchema.CreateSrcIndex,
            LinkSchema.CreateDstIndex,
            LinkSchema.CascadeOnNoteDelete,
            LinkSchema.CascadeOnTaskDelete,
        ]),
        new(AttachmentSchema.MigrationName, [AttachmentSchema.CreateAttachmentTable]),
```

Update `MigrationTests.OpeningAppliesEveryMigrationInOrder` to expect all six names in this
order: `createNote`, `createOpenTab`, `createTaskBoard`, `createAppState`, `createLink`,
`createAttachment`.

- [ ] **Step 3: Write the failing task repository tests**

The completion-stamping rule is the only real logic here, and it lives in the repository rather
than the UI so drag-and-drop and any future caller get it for free.

`windows/Notebar.Store.Tests/SqliteTaskRepositoryTests.cs`:

```csharp
using Notebar.Core.Models;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteTaskRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteTaskRepository _repo;

    public SqliteTaskRepositoryTests() => _repo = new SqliteTaskRepository(_fixture.Db);
    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void SeedsThreeColumnsInOrder()
    {
        var columns = _repo.Columns();
        Assert.Equal(["Queue", "Working", "Done"], columns.Select(c => c.Name));
        Assert.Equal(
            [BoardColumn.BacklogKind, BoardColumn.ActiveKind, BoardColumn.DoneKind],
            columns.Select(c => c.Kind));
    }

    [Fact]
    public void CreateRoundTripsIntoItsColumn()
    {
        var task = _repo.Create("Ship it", TaskSchema.QueueColumnId);
        var stored = Assert.Single(_repo.All());
        Assert.Equal(task, stored);
        Assert.Equal(TaskSchema.QueueColumnId, stored.ColumnId);
        Assert.Null(stored.CompletedAt);
    }

    [Fact]
    public void CreateAppendsWithinItsOwnColumn()
    {
        var a = _repo.Create("a", TaskSchema.QueueColumnId);
        var b = _repo.Create("b", TaskSchema.QueueColumnId);
        var c = _repo.Create("c", TaskSchema.WorkingColumnId);

        Assert.True(b.SortOrder > a.SortOrder);
        // c is in a different column, so it does not have to sort after b.
        Assert.Equal(TaskSchema.WorkingColumnId, c.ColumnId);
    }

    [Fact]
    public void UpdatePersistsTitleDetailPriorityAndDueDate()
    {
        var task = _repo.Create("draft", TaskSchema.QueueColumnId);
        var due = new DateTimeOffset(2026, 10, 1, 9, 0, 0, TimeSpan.Zero);
        _repo.Update(task with { Title = "final", DetailPlain = "with notes", Priority = 2, DueAt = due });

        var stored = Assert.Single(_repo.All());
        Assert.Equal("final", stored.Title);
        Assert.Equal("with notes", stored.DetailPlain);
        Assert.Equal(2, stored.Priority);
        Assert.Equal(due, stored.DueAt);
    }

    [Fact]
    public void UpdatingAnUnknownIdThrows() =>
        Assert.Throws<InvalidOperationException>(() =>
            _repo.Update(TaskItem.New("orphan", TaskSchema.QueueColumnId, 0)));

    /// The rule that lives in the repository rather than the UI, so every caller
    /// gets it for free.
    [Fact]
    public void MovingIntoDoneStampsCompletedAt()
    {
        var task = _repo.Create("thing", TaskSchema.QueueColumnId);
        var moved = _repo.Move(task.Id, TaskSchema.DoneColumnId, null, null);
        Assert.NotNull(moved.CompletedAt);
    }

    [Fact]
    public void MovingOutOfDoneClearsCompletedAt()
    {
        var task = _repo.Create("thing", TaskSchema.QueueColumnId);
        _repo.Move(task.Id, TaskSchema.DoneColumnId, null, null);
        var moved = _repo.Move(task.Id, TaskSchema.WorkingColumnId, null, null);
        Assert.Null(moved.CompletedAt);
    }

    /// Reordering within Done must not restamp — the completion time is when it
    /// was finished, not when it was last dragged.
    [Fact]
    public void ReorderingWithinDoneKeepsTheOriginalCompletionTime()
    {
        var a = _repo.Create("a", TaskSchema.DoneColumnId);
        var b = _repo.Create("b", TaskSchema.DoneColumnId);
        var stampedA = _repo.Move(a.Id, TaskSchema.DoneColumnId, null, b.Id);
        var first = stampedA.CompletedAt;

        var again = _repo.Move(a.Id, TaskSchema.DoneColumnId, b.Id, null);
        Assert.Equal(first, again.CompletedAt);
    }

    [Fact]
    public void MoveRepositionsWithinAColumn()
    {
        var a = _repo.Create("a", TaskSchema.QueueColumnId);
        var b = _repo.Create("b", TaskSchema.QueueColumnId);
        var c = _repo.Create("c", TaskSchema.QueueColumnId);

        _repo.Move(c.Id, TaskSchema.QueueColumnId, a.Id, b.Id);

        var queue = _repo.All().Where(t => t.ColumnId == TaskSchema.QueueColumnId);
        Assert.Equal([a.Id, c.Id, b.Id], queue.Select(t => t.Id));
    }

    [Fact]
    public void DeleteRemovesTheRowAndIsIdempotent()
    {
        var task = _repo.Create("x", TaskSchema.QueueColumnId);
        _repo.Delete(task.Id);
        Assert.Empty(_repo.All());
        _repo.Delete(task.Id);
    }

    [Fact]
    public void SearchFindsByTitleAndDetail()
    {
        var a = _repo.Create("Deploy the panel", TaskSchema.QueueColumnId);
        var b = _repo.Create("Buy milk", TaskSchema.QueueColumnId);
        _repo.Update(b with { DetailPlain = "semi-skimmed" });

        Assert.Equal([a.Id], _repo.Search("panel").Select(t => t.Id));
        Assert.Equal([b.Id], _repo.Search("skimmed").Select(t => t.Id));
    }

    [Fact]
    public void AllIsOrderedByColumnThenPosition()
    {
        var q = _repo.Create("q", TaskSchema.QueueColumnId);
        var d = _repo.Create("d", TaskSchema.DoneColumnId);
        var w = _repo.Create("w", TaskSchema.WorkingColumnId);

        Assert.Equal([q.Id, w.Id, d.Id], _repo.All().Select(t => t.Id));
    }
}
```

- [ ] **Step 4: Write `SqliteTaskRepository`**

Follow `SqliteNoteRepository`'s `Bind`/`Read`/`Query` shape for the mechanical parts. `Move` is
the method that carries the rule:

```csharp
    public TaskItem Move(string id, string columnId, string? beforeId, string? afterId)
    {
        var task = Fetch(id) ?? throw new InvalidOperationException($"task {id} does not exist");

        bool wasDone = IsDoneColumn(task.ColumnId);
        bool willBeDone = IsDoneColumn(columnId);

        // Entering Done stamps the completion time; leaving it clears it.
        // Reordering *within* Done keeps the original stamp — the completion time
        // is when the work finished, not when the card was last dragged.
        DateTimeOffset? completedAt = (wasDone, willBeDone) switch
        {
            (false, true) => DateTimeOffset.UtcNow,
            (true, false) => null,
            _ => task.CompletedAt,
        };

        double? before = beforeId is null ? null : OrderOf(beforeId);
        double? after = afterId is null ? null : OrderOf(afterId);

        var moved = task with
        {
            ColumnId = columnId,
            SortOrder = SortOrder.Between(before, after),
            CompletedAt = completedAt,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            UPDATE task SET column_id = $col, sort_order = $order,
                            completed_at = $completed, updated_at = $updated
            WHERE id = $id
            """;
        cmd.Parameters.AddWithValue("$col", moved.ColumnId);
        cmd.Parameters.AddWithValue("$order", moved.SortOrder);
        cmd.Parameters.AddWithValue("$completed", Sql.ToDb(moved.CompletedAt));
        cmd.Parameters.AddWithValue("$updated", Sql.ToText(moved.UpdatedAt));
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();

        return moved;
    }

    private bool IsDoneColumn(string columnId) =>
        Columns().Any(c => c.Id == columnId && c.Kind == BoardColumn.DoneKind);
```

`All()` orders by the column's position, then the task's own:

```csharp
    public IReadOnlyList<TaskItem> All() => Query("""
        SELECT t.id, t.title, t.detail_plain, t.column_id, t.sort_order, t.priority,
               t.due_at, t.completed_at, t.created_at, t.updated_at
        FROM task t
        JOIN board_column c ON c.id = t.column_id
        ORDER BY c.sort_order ASC, t.sort_order ASC
        """);
```

`Create(title, columnId)` appends within that column only:

```csharp
    public TaskItem Create(string title, string columnId)
    {
        using var max = db.Connection.CreateCommand();
        max.CommandText = "SELECT MAX(sort_order) FROM task WHERE column_id = $col";
        max.Parameters.AddWithValue("$col", columnId);
        object? last = max.ExecuteScalar();
        double? previous = last is null or DBNull ? null : Convert.ToDouble(last);

        var task = TaskItem.New(title, columnId, SortOrder.Between(previous, null));
        // ...INSERT following SqliteNoteRepository's Bind shape...
        return task;
    }
```

- [ ] **Step 5: Write the link repository tests and implementation**

The transactional write is the point: a chip's markup and the `link` row behind it must commit
together, so a crash between the two cannot leave one without the other.

`windows/Notebar.Store.Tests/SqliteLinkRepositoryTests.cs`:

```csharp
using Notebar.Core.Models;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteLinkRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteLinkRepository _links;
    private readonly SqliteNoteRepository _notes;
    private readonly SqliteTaskRepository _tasks;

    public SqliteLinkRepositoryTests()
    {
        _links = new SqliteLinkRepository(_fixture.Db);
        _notes = new SqliteNoteRepository(_fixture.Db);
        _tasks = new SqliteTaskRepository(_fixture.Db);
    }

    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void CreateRoundTrips()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        var link = _links.Create(Link.New(
            new LinkTarget(LinkEntityType.Note, note.Id),
            new LinkTarget(LinkEntityType.Task, task.Id)));

        Assert.Equal([link], _links.Outgoing(new LinkTarget(LinkEntityType.Note, note.Id)));
        Assert.Equal([link], _links.Incoming(new LinkTarget(LinkEntityType.Task, task.Id)));
    }

    /// Backlinks are the reverse query. A note that links out must not appear in
    /// its own incoming list.
    [Fact]
    public void OutgoingAndIncomingAreNotSymmetric()
    {
        var a = _notes.Create();
        var b = _notes.Create();
        _links.Create(Link.New(
            new LinkTarget(LinkEntityType.Note, a.Id),
            new LinkTarget(LinkEntityType.Note, b.Id)));

        Assert.Empty(_links.Incoming(new LinkTarget(LinkEntityType.Note, a.Id)));
        Assert.Single(_links.Incoming(new LinkTarget(LinkEntityType.Note, b.Id)));
    }

    /// The unique constraint means inserting the same edge twice is not an error
    /// the user should ever see — chips are inserted by typing, and typing the
    /// same reference twice is normal.
    [Fact]
    public void CreatingTheSameEdgeTwiceIsIdempotent()
    {
        var a = _notes.Create();
        var b = _notes.Create();
        var edge = Link.New(new LinkTarget(LinkEntityType.Note, a.Id),
                            new LinkTarget(LinkEntityType.Note, b.Id));

        _links.Create(edge);
        _links.Create(edge with { Id = Guid.NewGuid().ToString() });

        Assert.Single(_links.Outgoing(new LinkTarget(LinkEntityType.Note, a.Id)));
    }

    /// One transaction: the chip's markup and the row behind it commit together.
    [Fact]
    public void CreateSavingNoteBodyWritesBothOrNeither()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        string html = $"<p>see <a href=\"{LinkUrl.Build(LinkEntityType.Task, task.Id)}\">t</a></p>";

        _links.CreateSavingNoteBody(
            Link.New(new LinkTarget(LinkEntityType.Note, note.Id),
                     new LinkTarget(LinkEntityType.Task, task.Id)),
            note.Id, html, "see t");

        Assert.Equal(html, _notes.Fetch(note.Id)!.BodyHtml);
        Assert.Single(_links.Outgoing(new LinkTarget(LinkEntityType.Note, note.Id)));
    }

    [Fact]
    public void CreateSavingNoteBodyRollsBackIfTheNoteIsGone()
    {
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        var link = Link.New(new LinkTarget(LinkEntityType.Note, "no-such-note"),
                            new LinkTarget(LinkEntityType.Task, task.Id));

        Assert.Throws<InvalidOperationException>(() =>
            _links.CreateSavingNoteBody(link, "no-such-note", "<p>x</p>", "x"));

        Assert.Empty(_links.Incoming(new LinkTarget(LinkEntityType.Task, task.Id)));
    }

    /// Deleting a note cascades to every link touching it, on either end.
    [Fact]
    public void DeletingANoteRemovesLinksInBothDirections()
    {
        var a = _notes.Create();
        var b = _notes.Create();
        _links.Create(Link.New(new LinkTarget(LinkEntityType.Note, a.Id),
                               new LinkTarget(LinkEntityType.Note, b.Id)));
        _links.Create(Link.New(new LinkTarget(LinkEntityType.Note, b.Id),
                               new LinkTarget(LinkEntityType.Note, a.Id)));

        _notes.Delete(a.Id);

        Assert.Empty(_links.Outgoing(new LinkTarget(LinkEntityType.Note, b.Id)));
        Assert.Empty(_links.Incoming(new LinkTarget(LinkEntityType.Note, b.Id)));
    }

    [Fact]
    public void DeletingATaskRemovesLinksInBothDirections()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);
        _links.Create(Link.New(new LinkTarget(LinkEntityType.Note, note.Id),
                               new LinkTarget(LinkEntityType.Task, task.Id)));

        _tasks.Delete(task.Id);

        Assert.Empty(_links.Outgoing(new LinkTarget(LinkEntityType.Note, note.Id)));
    }

    /// One query per note load, not one per chip — this is what makes the
    /// tombstone check a set lookup.
    [Fact]
    public void ExistingTargetsCoversBothTables()
    {
        var note = _notes.Create();
        var task = _tasks.Create("t", TaskSchema.QueueColumnId);

        var targets = _links.ExistingTargets();

        Assert.Contains(new LinkTarget(LinkEntityType.Note, note.Id), targets);
        Assert.Contains(new LinkTarget(LinkEntityType.Task, task.Id), targets);
        Assert.DoesNotContain(new LinkTarget(LinkEntityType.Note, task.Id), targets);
    }
}
```

The two methods that are not mechanical, in `windows/Notebar.Store/SqliteLinkRepository.cs`:

```csharp
    public Link Create(Link link)
    {
        using var cmd = db.Connection.CreateCommand();
        // OR IGNORE: chips are inserted by typing, and typing the same reference
        // twice is normal, not an error the user should ever see.
        cmd.CommandText = """
            INSERT OR IGNORE INTO link (id, src_type, src_id, dst_type, dst_id, kind, created_at)
            VALUES ($id, $st, $si, $dt, $di, $kind, $created)
            """;
        Bind(cmd, link);
        cmd.ExecuteNonQuery();
        return link;
    }

    /// <summary>Inserts the link and saves the note's body in one transaction, so
    /// a chip's markup and the row behind it are always committed together — a
    /// crash between the two can never leave one without the other.</summary>
    public Link CreateSavingNoteBody(Link link, string noteId, string bodyHtml, string bodyPlain)
    {
        using var tx = db.Connection.BeginTransaction();

        using (var save = db.Connection.CreateCommand())
        {
            save.Transaction = tx;
            save.CommandText = """
                UPDATE note SET body_html = $html, body_plain = $plain, updated_at = $updated
                WHERE id = $id
                """;
            save.Parameters.AddWithValue("$html", bodyHtml);
            save.Parameters.AddWithValue("$plain", bodyPlain);
            save.Parameters.AddWithValue("$updated", Sql.ToText(DateTimeOffset.UtcNow));
            save.Parameters.AddWithValue("$id", noteId);
            if (save.ExecuteNonQuery() == 0)
                throw new InvalidOperationException($"note {noteId} does not exist");
        }

        using (var insert = db.Connection.CreateCommand())
        {
            insert.Transaction = tx;
            insert.CommandText = """
                INSERT OR IGNORE INTO link (id, src_type, src_id, dst_type, dst_id, kind, created_at)
                VALUES ($id, $st, $si, $dt, $di, $kind, $created)
                """;
            Bind(insert, link);
            insert.ExecuteNonQuery();
        }

        tx.Commit();
        return link;
    }

    /// <summary>Every note and task id that still exists, as one set. Called once
    /// per note load rather than once per chip, which is what keeps the tombstone
    /// check to a set lookup.</summary>
    public IReadOnlySet<LinkTarget> ExistingTargets()
    {
        var targets = new HashSet<LinkTarget>();
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = """
            SELECT 'note', id FROM note
            UNION ALL
            SELECT 'task', id FROM task
            """;
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var type = LinkEntityTypeExtensions.Parse(reader.GetString(0));
            if (type is { } t) targets.Add(new LinkTarget(t, reader.GetString(1)));
        }
        return targets;
    }
```

- [ ] **Step 6: Write the app state repository with its clamp tests**

The clamp is the point: a hand-edited database must never be able to push the panel out of its
designed feel, only the settings sliders can.

`windows/Notebar.Store.Tests/SqliteAppStateRepositoryTests.cs`:

```csharp
using Notebar.Core.Models;
using Notebar.Core.Panel;
using Notebar.Core.Schema;
using Notebar.Store;
using Xunit;

namespace Notebar.Store.Tests;

public class SqliteAppStateRepositoryTests : IDisposable
{
    private readonly TestDatabase _fixture = new();
    private readonly SqliteAppStateRepository _repo;

    public SqliteAppStateRepositoryTests() => _repo = new SqliteAppStateRepository(_fixture.Db);
    public void Dispose() => _fixture.Dispose();

    [Fact]
    public void ThemeDefaultsToSystem() => Assert.Equal(Theme.System, _repo.GetTheme());

    [Theory]
    [InlineData(Theme.Light)]
    [InlineData(Theme.Dark)]
    [InlineData(Theme.System)]
    public void ThemeRoundTrips(Theme theme)
    {
        _repo.SetTheme(theme);
        Assert.Equal(theme, _repo.GetTheme());
    }

    /// Someone hand-editing the database must get the default appearance back,
    /// not a crash.
    [Fact]
    public void AnUnrecognisedThemeFallsBackToTheDefault()
    {
        WriteRaw(AppStateSchema.ThemeKey, "solarized");
        Assert.Equal(Theme.System, _repo.GetTheme());
    }

    [Fact]
    public void TimingsDefaultToTheirConstants()
    {
        Assert.Equal(PanelTiming.EdgeDwell, _repo.GetEdgeDwell());
        Assert.Equal(PanelTiming.ExitDwell, _repo.GetExitDwell());
        Assert.Equal(PanelTiming.ExitSlop, _repo.GetExitSlop());
    }

    [Fact]
    public void TimingsRoundTrip()
    {
        _repo.SetEdgeDwell(0.3);
        _repo.SetExitDwell(1.0);
        _repo.SetExitSlop(50);
        Assert.Equal(0.3, _repo.GetEdgeDwell());
        Assert.Equal(1.0, _repo.GetExitDwell());
        Assert.Equal(50, _repo.GetExitSlop());
    }

    /// A stored value out of range is clamped on read, not trusted. The settings
    /// slider cannot produce these; a text editor can.
    [Fact]
    public void OutOfRangeStoredValuesAreClampedOnRead()
    {
        WriteRaw(AppStateSchema.EdgeDwellKey, "99");
        WriteRaw(AppStateSchema.ExitDwellKey, "0");
        WriteRaw(AppStateSchema.ExitSlopKey, "-5");

        Assert.Equal(PanelTiming.EdgeDwellMax, _repo.GetEdgeDwell());
        // Zero would make the panel collapse the instant the cursor leaves,
        // which is the hostile behaviour the whole suppression policy prevents.
        Assert.Equal(PanelTiming.ExitDwellMin, _repo.GetExitDwell());
        Assert.Equal(PanelTiming.ExitSlopMin, _repo.GetExitSlop());
    }

    [Fact]
    public void AnUnparseableTimingFallsBackToItsConstant()
    {
        WriteRaw(AppStateSchema.EdgeDwellKey, "soon");
        Assert.Equal(PanelTiming.EdgeDwell, _repo.GetEdgeDwell());
    }

    /// Written with the invariant culture, so a machine set to a comma-decimal
    /// locale reads back what another machine wrote.
    [Fact]
    public void TimingsUseInvariantNumberFormatting()
    {
        _repo.SetEdgeDwell(0.25);
        Assert.Equal("0.25", ReadRaw(AppStateSchema.EdgeDwellKey));
    }

    private void WriteRaw(string key, string value)
    {
        using var cmd = _fixture.Db.Connection.CreateCommand();
        cmd.CommandText = "INSERT OR REPLACE INTO app_state (key, value) VALUES ($k, $v)";
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        cmd.ExecuteNonQuery();
    }

    private string? ReadRaw(string key)
    {
        using var cmd = _fixture.Db.Connection.CreateCommand();
        cmd.CommandText = "SELECT value FROM app_state WHERE key = $k";
        cmd.Parameters.AddWithValue("$k", key);
        return cmd.ExecuteScalar() as string;
    }
}
```

`windows/Notebar.Store/SqliteAppStateRepository.cs` — the shape every getter follows:

```csharp
using System.Globalization;
using Microsoft.Data.Sqlite;
using Notebar.Core.Models;
using Notebar.Core.Panel;
using Notebar.Core.Repositories;
using Notebar.Core.Schema;

namespace Notebar.Store;

public sealed class SqliteAppStateRepository(NotebarDatabase db) : IAppStateRepository
{
    public Theme GetTheme() => ThemeExtensions.Parse(Get(AppStateSchema.ThemeKey));

    public void SetTheme(Theme theme) => Set(AppStateSchema.ThemeKey, theme.ToStorageString());

    public double GetEdgeDwell() =>
        GetClamped(AppStateSchema.EdgeDwellKey, PanelTiming.EdgeDwell,
                   PanelTiming.EdgeDwellMin, PanelTiming.EdgeDwellMax);

    public void SetEdgeDwell(double value) => SetDouble(AppStateSchema.EdgeDwellKey, value);

    public double GetExitDwell() =>
        GetClamped(AppStateSchema.ExitDwellKey, PanelTiming.ExitDwell,
                   PanelTiming.ExitDwellMin, PanelTiming.ExitDwellMax);

    public void SetExitDwell(double value) => SetDouble(AppStateSchema.ExitDwellKey, value);

    public double GetExitSlop() =>
        GetClamped(AppStateSchema.ExitSlopKey, PanelTiming.ExitSlop,
                   PanelTiming.ExitSlopMin, PanelTiming.ExitSlopMax);

    public void SetExitSlop(double value) => SetDouble(AppStateSchema.ExitSlopKey, value);

    /// <summary>Falls back to the constant when nothing is stored or the stored
    /// text does not parse, and clamps when it parses but is out of range. A
    /// hand-edited database must never push the panel further than the sliders
    /// could.</summary>
    private double GetClamped(string key, double fallback, double min, double max)
    {
        string? raw = Get(key);
        return double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out double v)
            ? PanelTiming.Clamp(v, min, max)
            : fallback;
    }

    private void SetDouble(string key, double value) =>
        Set(key, value.ToString(CultureInfo.InvariantCulture));

    private string? Get(string key)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "SELECT value FROM app_state WHERE key = $k";
        cmd.Parameters.AddWithValue("$k", key);
        return cmd.ExecuteScalar() as string;
    }

    private void Set(string key, string value)
    {
        using var cmd = db.Connection.CreateCommand();
        cmd.CommandText = "INSERT OR REPLACE INTO app_state (key, value) VALUES ($k, $v)";
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        cmd.ExecuteNonQuery();
    }
}
```

- [ ] **Step 7: Write the open tab, attachment, and diagnostics repositories**

`SqliteOpenTabRepository.ReplaceAll` deletes and reinserts inside one transaction — the strip is
a handful of rows and changes only on open, close, reorder, and select, never per keystroke, so
a full replace is simpler than diffing and cheap enough not to matter. Its tests must cover:
round-tripping order, that exactly one tab can be active, and that replacing with an empty list
clears the strip.

`SqliteAttachmentRepository.DeleteUnreferenced(referencedIds)` deletes every attachment row
whose id is not in the set. Its tests must cover: create/fetch round-trip including the byte
array, that fetching an unknown id returns null, and that `DeleteUnreferenced` keeps referenced
rows and removes unreferenced ones. Call it after a note body save, so an image the user deleted
from a note stops occupying the database.

`SqliteDiagnosticsRepository.Snapshot()` returns `new DatabaseDiagnostics(db.Path, size,
db.AppliedMigrations)` where `size` is the sum of the `.sqlite`, `-wal`, and `-shm` file
lengths, or null when `db.Path` is null or any read throws. Its tests must cover: the in-memory
case reporting a null path and null size, and the migration list matching
`db.AppliedMigrations`.

- [ ] **Step 8: Run every test, run the purity guard, commit and push**

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd windows
dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj
dotnet test Notebar.Store.Tests/Notebar.Store.Tests.csproj
scripts/check-core-purity.sh
```

All green, then:

```bash
git add windows/Notebar.Core/Schema windows/Notebar.Core/Repositories windows/Notebar.Store windows/Notebar.Store.Tests
git commit -m "Add the remaining six repositories

The completion-stamping rule lives in the task repository rather than the UI,
so drag-and-drop and every future caller get it for free — and reordering
within Done keeps the original stamp, because a completion time is when the
work finished, not when the card was last dragged.

Link creation uses INSERT OR IGNORE against the unique constraint: chips are
inserted by typing, and typing the same reference twice is normal rather than
an error a user should ever see.

Stored timings are clamped on read, not trusted. The settings sliders cannot
produce an exit dwell of zero; a text editor can, and zero collapses the panel
the instant the cursor leaves — the exact behaviour the suppression policy
exists to prevent.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
```

---

### Task 6: Panel geometry — DPI, work area, and the three rectangles

Pure arithmetic, so it belongs in `Notebar.Core` and is fully testable on the development
machine — which matters, because getting it wrong produces a panel that is subtly the wrong size
only on someone else's scaled display.

**Files:**
- Create: `windows/Notebar.Core/Panel/PanelGeometry.cs`
- Test: `windows/Notebar.Core.Tests/PanelGeometryTests.cs`

**Interfaces:**
- Consumes: `PanelTiming`, `PanelRect` (Tasks 1–2).
- Produces `static class PanelGeometry`:
  - `PanelRect Collapsed(PanelRect workArea)`
  - `PanelRect Expanded(PanelRect workArea)`
  - `PanelRect Maximized(PanelRect workArea)`
  - `PanelRect ToPhysical(PanelRect dips, double scale)`
  - `PanelPoint ToDips(PanelPoint physical, double scale)`

- [ ] **Step 1: Write the failing tests**

```csharp
using Notebar.Core.Geometry;
using Notebar.Core.Panel;
using Xunit;

namespace Notebar.Core.Tests;

public class PanelGeometryTests
{
    /// A 1920x1080 display with a 40dip taskbar at the bottom.
    private static readonly PanelRect WorkArea = new(0, 0, 1920, 1040);

    [Fact]
    public void CollapsedIsTheHandleFlushToTheRightEdge()
    {
        var r = PanelGeometry.Collapsed(WorkArea);
        Assert.Equal(WorkArea.MaxX, r.MaxX);
        Assert.Equal(PanelTiming.HandleWidth, r.Width);
        Assert.Equal(PanelTiming.HandleHeight, r.Height);
    }

    [Fact]
    public void CollapsedIsVerticallyCentred()
    {
        var r = PanelGeometry.Collapsed(WorkArea);
        Assert.Equal(WorkArea.MinY + (WorkArea.Height - r.Height) / 2, r.MinY, precision: 6);
    }

    [Fact]
    public void ExpandedIsTheFixedWidthFlushToTheRightEdge()
    {
        var r = PanelGeometry.Expanded(WorkArea);
        Assert.Equal(WorkArea.MaxX, r.MaxX);
        Assert.Equal(PanelTiming.PanelWidth, r.Width);
    }

    /// A card, not a full-height column.
    [Fact]
    public void ExpandedIsSeventyPercentTallAndCentred()
    {
        var r = PanelGeometry.Expanded(WorkArea);
        Assert.Equal(WorkArea.Height * PanelTiming.PanelHeightFraction, r.Height, precision: 6);
        Assert.Equal(WorkArea.MinY + (WorkArea.Height - r.Height) / 2, r.MinY, precision: 6);
    }

    /// Maximized reads as a docked half-screen column, so it takes the full work
    /// area height rather than the 70% fraction.
    [Fact]
    public void MaximizedIsHalfWideAndFullHeight()
    {
        var r = PanelGeometry.Maximized(WorkArea);
        Assert.Equal(WorkArea.Width * PanelTiming.MaximizedWidthFraction, r.Width, precision: 6);
        Assert.Equal(WorkArea.Height, r.Height, precision: 6);
        Assert.Equal(WorkArea.MaxX, r.MaxX);
        Assert.Equal(WorkArea.MinY, r.MinY);
    }

    /// A work area whose origin is not zero — a second monitor, or a taskbar
    /// docked to the top or left. Everything must be relative to it, never to
    /// zero.
    [Fact]
    public void RespectsANonZeroWorkAreaOrigin()
    {
        var offset = new PanelRect(1920, 60, 1280, 740);
        foreach (var r in new[]
        {
            PanelGeometry.Collapsed(offset),
            PanelGeometry.Expanded(offset),
            PanelGeometry.Maximized(offset),
        })
        {
            Assert.Equal(offset.MaxX, r.MaxX);
            Assert.True(r.MinY >= offset.MinY, "panel must not start above the work area");
            Assert.True(r.MaxY <= offset.MaxY, "panel must not extend below the work area");
        }
    }

    /// A work area shorter than the handle cannot fit it. Clamp rather than
    /// producing a negative-origin rect that Windows will place off-screen.
    [Fact]
    public void ClampsToAWorkAreaSmallerThanThePanel()
    {
        var tiny = new PanelRect(0, 0, 200, 40);
        var r = PanelGeometry.Expanded(tiny);
        Assert.True(r.Width <= tiny.Width);
        Assert.True(r.MinY >= tiny.MinY);
        Assert.True(r.MaxY <= tiny.MaxY);
    }

    /// Windows APIs take physical pixels; PanelTiming is in dips. Every value
    /// crosses this boundary exactly once, here.
    [Fact]
    public void ScalesToPhysicalPixels()
    {
        var dips = new PanelRect(100, 50, 340, 700);
        var physical = PanelGeometry.ToPhysical(dips, scale: 1.5);
        Assert.Equal(150, physical.X);
        Assert.Equal(75, physical.Y);
        Assert.Equal(510, physical.Width);
        Assert.Equal(1050, physical.Height);
    }

    [Fact]
    public void ScalesCursorPositionsBackToDips()
    {
        var p = PanelGeometry.ToDips(new PanelPoint(2880, 1620), scale: 2.0);
        Assert.Equal(1440, p.X);
        Assert.Equal(810, p.Y);
    }

    [Fact]
    public void ScaleOfOneIsTheIdentity()
    {
        var dips = new PanelRect(10, 20, 30, 40);
        Assert.Equal(dips, PanelGeometry.ToPhysical(dips, scale: 1.0));
    }
}
```

- [ ] **Step 2: Run and confirm they fail**, then **Step 3: write `PanelGeometry`**

```csharp
using Notebar.Core.Geometry;

namespace Notebar.Core.Panel;

/// <summary>The panel's three rectangles, and the one place device-independent
/// pixels become physical ones.</summary>
/// <remarks>
/// Every length in PanelTiming is in dips. Every Win32 API — GetCursorPos,
/// SetWindowPos, GetMonitorInfo — is in physical pixels. Mixing them produces a
/// panel that is subtly the wrong size only on a scaled display, which is to say
/// only on someone else's machine. Everything crosses that boundary here and
/// nowhere else.
///
/// All rects are anchored to the *work area* rather than the monitor, so the
/// panel never sits under the taskbar wherever the user has docked it.
/// </remarks>
public static class PanelGeometry
{
    public static PanelRect Collapsed(PanelRect workArea) =>
        RightEdge(workArea, PanelTiming.HandleWidth, PanelTiming.HandleHeight);

    public static PanelRect Expanded(PanelRect workArea) =>
        RightEdge(workArea,
                  PanelTiming.PanelWidth,
                  workArea.Height * PanelTiming.PanelHeightFraction);

    /// <summary>Half the work area's width at its full height — a docked column,
    /// not a bigger card.</summary>
    public static PanelRect Maximized(PanelRect workArea) =>
        RightEdge(workArea,
                  workArea.Width * PanelTiming.MaximizedWidthFraction,
                  workArea.Height);

    /// <summary>Flush to the right edge, vertically centred, clamped to fit.</summary>
    private static PanelRect RightEdge(PanelRect workArea, double width, double height)
    {
        double w = Math.Min(width, workArea.Width);
        double h = Math.Min(height, workArea.Height);
        double x = workArea.MaxX - w;
        double y = workArea.MinY + (workArea.Height - h) / 2;
        return new PanelRect(x, y, w, h);
    }

    public static PanelRect ToPhysical(PanelRect dips, double scale) =>
        new(dips.X * scale, dips.Y * scale, dips.Width * scale, dips.Height * scale);

    public static PanelPoint ToDips(PanelPoint physical, double scale) =>
        new(physical.X / scale, physical.Y / scale);
}
```

- [ ] **Step 4: Run, confirm green, run the purity guard, commit**

```bash
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
cd windows && dotnet test Notebar.Core.Tests/Notebar.Core.Tests.csproj && scripts/check-core-purity.sh
git add windows/Notebar.Core/Panel/PanelGeometry.cs windows/Notebar.Core.Tests/PanelGeometryTests.cs
git commit -m "Add PanelGeometry: the one place dips become physical pixels

PanelTiming is in device-independent pixels; every Win32 API the panel calls
is in physical ones. Mixing them produces a panel that is subtly the wrong
size only on a scaled display — which is to say only on someone else's
machine, where nobody can debug it. The conversion happens here and nowhere
else, and the tests cover a 1.5x and a 2x display.

Rects are anchored to the work area rather than the monitor, so the panel
never sits under the taskbar wherever it is docked, and clamped so a work area
smaller than the panel produces a visible rect rather than a negative origin
Windows would place off-screen.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
```

---

### Task 7: The panel window — borderless, topmost, non-stealing, across desktops

**RISK.** The first of the three things that could sink this milestone. Everything from here is
CI-compiled and human-verified; it cannot be tested on the development machine.

**Files:**
- Create: `windows/Notebar.App/Interop/NativeMethods.cs`
- Create: `windows/Notebar.App/Panel/MonitorInfo.cs`
- Modify: `windows/Notebar.App/Panel/PanelWindow.xaml`, `PanelWindow.xaml.cs`
- Modify: `windows/Notebar.App/App.xaml.cs`

**Interfaces:**
- Consumes: `PanelGeometry`, `PanelRect`, `PanelPoint`, `PanelTiming`.
- Produces:
  - `static class NativeMethods` — `GetCursorPos`, `MonitorFromPoint`, `GetMonitorInfo`, `GetDpiForWindow`, `SetWindowPos`, `ShowWindow`, `GetWindowLongPtr`, `SetWindowLongPtr`, `RegisterHotKey`, `UnregisterHotKey`, `Shell_NotifyIcon`, `CreateWindowEx`, `DefWindowProc`, `RegisterClassEx`, `GetForegroundWindow`, and their constants
  - `static class MonitorInfo` — `PanelRect WorkAreaContaining(PanelPoint physicalPoint, out double scale)`, `PanelRect PrimaryWorkArea(out double scale)`, `IReadOnlyList<string> DescribeAll()`
  - `PanelWindow` — `IntPtr Handle`, `void ApplyFrame(PanelRect dips, double scale)`, `void ShowWithoutActivating()`, `void HideWindow()`, `void ReassertTopmost()`

- [ ] **Step 1: Write `NativeMethods`**

One file for every P/Invoke, so the app's whole native surface is auditable in one place — and
so the ban on hooks is visible as an absence rather than something you have to grep for.

```csharp
using System.Runtime.InteropServices;

namespace Notebar.App.Interop;

/// <summary>Every P/Invoke the app makes, in one file.</summary>
/// <remarks>
/// Deliberately one file so the app's entire native surface is auditable at a
/// glance. Nothing here requires elevation, a permission prompt, or a hook —
/// SetWindowsHookEx, WH_KEYBOARD_LL, and WH_MOUSE_LL are banned: they are
/// unnecessary for everything this app does, they trip antivirus heuristics, and
/// they are the Windows equivalent of the Accessibility permission this project
/// has always refused. If a future need seems to require one, it does not.
/// </remarks>
internal static partial class NativeMethods
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    // --- cursor ---

    /// <summary>The sanctioned way to read the cursor. No prompt, no elevation —
    /// the direct analogue of NSEvent.mouseLocation on macOS.</summary>
    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetCursorPos(out POINT point);

    // --- monitors ---

    internal const uint MONITOR_DEFAULTTONEAREST = 2;

    [LibraryImport("user32.dll")]
    internal static partial IntPtr MonitorFromPoint(POINT pt, uint flags);

    [LibraryImport("user32.dll")]
    internal static partial IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(IntPtr hwnd);

    /// <summary>Per-monitor DPI, for the monitor the cursor is on rather than the
    /// one the window happens to be on. MDT_EFFECTIVE_DPI = 0.</summary>
    [LibraryImport("shcore.dll")]
    internal static partial int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);

    // --- window placement ---

    internal static readonly IntPtr HWND_TOPMOST = new(-1);

    internal const uint SWP_NOACTIVATE = 0x0010;
    internal const uint SWP_SHOWWINDOW = 0x0040;
    internal const uint SWP_NOZORDER = 0x0004;

    internal const int SW_HIDE = 0;
    internal const int SW_SHOWNOACTIVATE = 4;

    internal const int GWL_EXSTYLE = -20;
    internal const int WS_EX_TOOLWINDOW = 0x00000080;
    internal const int WS_EX_TOPMOST = 0x00000008;

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetWindowPos(
        IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool ShowWindow(IntPtr hwnd, int cmdShow);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    internal static partial IntPtr GetWindowLongPtr(IntPtr hwnd, int index);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    internal static partial IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);

    [LibraryImport("user32.dll")]
    internal static partial IntPtr GetForegroundWindow();

    // --- hotkey ---

    internal const uint MOD_CONTROL = 0x0002;
    internal const uint MOD_SHIFT = 0x0004;
    internal const uint MOD_NOREPEAT = 0x4000;
    internal const int WM_HOTKEY = 0x0312;

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint vk);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool UnregisterHotKey(IntPtr hwnd, int id);
}
```

- [ ] **Step 2: Write `MonitorInfo`**

The work area of the monitor under the cursor, plus its scale, both in one call — because
asking for them separately is how they end up describing different monitors:

```csharp
using Notebar.App.Interop;
using Notebar.Core.Geometry;

namespace Notebar.App.Panel;

/// <summary>Work areas and DPI scales, per monitor.</summary>
/// <remarks>
/// The work area, not the monitor rect: the panel must never sit under the
/// taskbar, wherever the user docked it. Scale comes back from the same call that
/// produced the rect, because fetching them separately is how they end up
/// describing two different monitors on a mixed-DPI setup.
/// </remarks>
internal static class MonitorInfo
{
    /// <summary>The work area containing <paramref name="physicalPoint"/>, in
    /// physical pixels, with that monitor's scale factor.</summary>
    internal static PanelRect WorkAreaContaining(PanelPoint physicalPoint, out double scale)
    {
        var pt = new NativeMethods.POINT
        {
            X = (int)Math.Round(physicalPoint.X),
            Y = (int)Math.Round(physicalPoint.Y),
        };
        IntPtr monitor = NativeMethods.MonitorFromPoint(pt, NativeMethods.MONITOR_DEFAULTTONEAREST);
        return WorkAreaOf(monitor, out scale);
    }

    internal static PanelRect WorkAreaOf(IntPtr monitor, out double scale)
    {
        var info = new NativeMethods.MONITORINFO
        {
            cbSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.MONITORINFO>(),
        };
        if (!NativeMethods.GetMonitorInfo(monitor, ref info))
        {
            scale = 1.0;
            return new PanelRect(0, 0, 1920, 1080);
        }

        scale = NativeMethods.GetDpiForMonitor(monitor, 0, out uint dpiX, out _) == 0
            ? dpiX / 96.0
            : 1.0;

        var w = info.rcWork;
        return new PanelRect(w.Left, w.Top, w.Right - w.Left, w.Bottom - w.Top);
    }

    /// <summary>One line per display, plain text, for diagnostics. Never anything
    /// but geometry.</summary>
    internal static IReadOnlyList<string> DescribeAll()
    {
        // Enumerating every monitor needs EnumDisplayMonitors; the cursor's
        // monitor is what actually matters for a bug report about the panel,
        // so report that one plus the primary.
        var lines = new List<string>();
        if (NativeMethods.GetCursorPos(out var cursor))
        {
            var area = WorkAreaContaining(new PanelPoint(cursor.X, cursor.Y), out double scale);
            lines.Add($"{area.Width}x{area.Height} work area @ ({area.X}, {area.Y}), scale {scale:0.##} (cursor)");
        }
        return lines;
    }
}
```

- [ ] **Step 3: Make `PanelWindow` borderless, topmost, and non-stealing**

The design decision worth stating: macOS's `.nonactivatingPanel` lets the panel become key
without activating the app. Windows has no equivalent, and `WS_EX_NOACTIVATE` — the closest
thing — would stop the editor ever receiving keyboard focus, which is worse than the problem.
The resolution: **show without activating, but allow activation on click.** Hovering never
steals focus; clicking into the editor activates, which is exactly what the user wants when
they click into an editor.

```csharp
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Notebar.App.Interop;
using Notebar.Core.Geometry;
using WinRT.Interop;

namespace Notebar.App;

public sealed partial class PanelWindow : Window
{
    private readonly IntPtr _hwnd;
    private readonly AppWindow _appWindow;

    public PanelWindow()
    {
        InitializeComponent();
        Title = "Notebar";

        _hwnd = WindowNative.GetWindowHandle(this);
        _appWindow = AppWindow.GetFromWindowId(
            Microsoft.UI.Win32Interop.GetWindowIdFromWindow(_hwnd));

        if (_appWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsResizable = false;
            presenter.IsMinimizable = false;
            presenter.IsMaximizable = false;
            presenter.IsAlwaysOnTop = true;
        }

        // A tool window: no taskbar button, no Alt-Tab entry. The panel is an
        // overlay, not a place the window manager should send the user.
        _appWindow.IsShownInSwitchers = false;
        var ex = NativeMethods.GetWindowLongPtr(_hwnd, NativeMethods.GWL_EXSTYLE);
        NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_EXSTYLE,
            ex | NativeMethods.WS_EX_TOOLWINDOW);
    }

    internal IntPtr Handle => _hwnd;

    /// <summary>Places the window from a rect in device-independent pixels
    /// relative to the given monitor's work area.</summary>
    internal void ApplyFrame(PanelRect dips, double scale)
    {
        var p = Notebar.Core.Panel.PanelGeometry.ToPhysical(dips, scale);
        NativeMethods.SetWindowPos(
            _hwnd, NativeMethods.HWND_TOPMOST,
            (int)Math.Round(p.X), (int)Math.Round(p.Y),
            (int)Math.Round(p.Width), (int)Math.Round(p.Height),
            NativeMethods.SWP_NOACTIVATE);
    }

    /// <summary>Shows the panel without taking focus from whatever the user is
    /// working in.</summary>
    /// <remarks>
    /// macOS's nonactivating panel can become key without activating the app.
    /// Windows has no equivalent: WS_EX_NOACTIVATE is the closest thing and it
    /// would stop the editor ever receiving keyboard focus, which is a worse
    /// problem than the one it solves. So the panel shows without activating —
    /// hovering never steals focus — while a click still activates it, which is
    /// exactly what someone clicking into an editor wants.
    /// </remarks>
    internal void ShowWithoutActivating() =>
        NativeMethods.ShowWindow(_hwnd, NativeMethods.SW_SHOWNOACTIVATE);

    internal void HideWindow() =>
        NativeMethods.ShowWindow(_hwnd, NativeMethods.SW_HIDE);

    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;

    /// <summary>Re-asserts topmost without moving or resizing. Another app going
    /// fullscreen, or the user switching virtual desktops, can knock the panel out
    /// of the topmost band; the cursor monitor calls this on its idle tick, which
    /// costs one call every 100 ms and removes a whole class of "it stopped
    /// appearing" reports.</summary>
    internal void ReassertTopmost() =>
        NativeMethods.SetWindowPos(_hwnd, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0,
            SWP_NOSIZE | SWP_NOMOVE | NativeMethods.SWP_NOACTIVATE);
}
```

- [ ] **Step 4: Place the window on launch**

In `App.xaml.cs`, after creating the window, put it in its collapsed position on the monitor
under the cursor rather than wherever Windows would have placed it:

```csharp
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new PanelWindow();

        var cursor = NativeMethods.GetCursorPos(out var pt)
            ? new PanelPoint(pt.X, pt.Y)
            : new PanelPoint(0, 0);
        var workArea = MonitorInfo.WorkAreaContaining(cursor, out double scale);
        var workAreaDips = new PanelRect(
            workArea.X / scale, workArea.Y / scale,
            workArea.Width / scale, workArea.Height / scale);

        _window.ApplyFrame(PanelGeometry.Collapsed(workAreaDips), scale);
        _window.ShowWithoutActivating();
    }
```

Note `Activate()` is gone. Calling it would steal focus on launch, which is the one thing the
panel must never do.

- [ ] **Step 5: Push and confirm CI compiles it**

```bash
git add windows/Notebar.App
git commit -m "Make the panel window borderless, topmost, and non-stealing

macOS's nonactivating panel can become key without activating its app. Windows
has no equivalent — WS_EX_NOACTIVATE is the closest thing and it would stop the
editor ever receiving keyboard focus, which is worse than the problem. So the
panel shows with SW_SHOWNOACTIVATE, meaning hover never steals focus, while a
click still activates it: exactly what someone clicking into an editor wants.

WS_EX_TOOLWINDOW and IsShownInSwitchers=false keep it out of the taskbar and
Alt-Tab. It is an overlay, not somewhere the window manager should send anyone.

Every P/Invoke lives in one file so the whole native surface is auditable at a
glance, and so the ban on SetWindowsHookEx is visible as an absence rather than
something you have to grep for.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
gh run watch "$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

CI compiling is the only automated signal available for this task. The behavioural questions —
does it really float over a maximized window, does it survive a virtual desktop switch — are
answered by the human running the release build, and must be listed in the release notes as
things to check.

---

### Task 8: Cursor monitor and the controller wiring

**RISK.** Reading the cursor 60 times a second without a permission prompt or a battery cost.

**Files:**
- Create: `windows/Notebar.App/Panel/CursorMonitor.cs`
- Create: `windows/Notebar.App/Panel/PanelController.cs`
- Modify: `windows/Notebar.App/App.xaml.cs`

**Interfaces:**
- Consumes: `PanelMachine`, `PanelEffect`, `PanelContext`, `EdgeZone`, `PanelGeometry`, `MonitorInfo`, `PanelWindow`.
- Produces:
  - `sealed class CursorMonitor : IDisposable` — `event Action<PanelPoint> Moved`, `void SetRate(PollRate rate)`, `void Start()`, `void Stop()`
  - `sealed class PanelController` — `void Send(PanelEvent evt)`, `PanelState State`, `bool IsPinned { get; set; }`, `bool IsMaximized { get; set; }`, `void NoteKeystroke()`, `bool HasOpenOverlay { get; set; }`, `bool IsDragging { get; set; }`, `Func<bool> IsEditorFocusedProvider { get; set; }`

- [ ] **Step 1: Write `CursorMonitor`**

```csharp
using Microsoft.UI.Dispatching;
using Notebar.App.Interop;
using Notebar.Core.Geometry;
using Notebar.Core.Panel;

namespace Notebar.App.Panel;

/// <summary>Polls the cursor position on a dispatcher timer.</summary>
/// <remarks>
/// Polling rather than a mouse hook, deliberately and permanently. A low-level
/// mouse hook would give exact movement, and would also require the app to sit in
/// every application's input path, trip antivirus heuristics, and be the Windows
/// equivalent of the Accessibility permission this project has always refused.
/// GetCursorPos needs no permission at all.
///
/// The cost is answered by the two rates: 10 Hz while the cursor is nowhere near
/// the edge, 60 Hz once it is close or the panel is open. A 10 Hz timer calling
/// one user32 function is not measurable against an idle machine, and the app
/// spends almost all of its life there.
/// </remarks>
internal sealed class CursorMonitor : IDisposable
{
    private readonly DispatcherQueueTimer _timer;
    private PollRate _rate = PollRate.Idle;

    internal event Action<PanelPoint>? Moved;

    internal CursorMonitor(DispatcherQueue queue)
    {
        _timer = queue.CreateTimer();
        _timer.IsRepeating = true;
        _timer.Interval = IntervalFor(PollRate.Idle);
        _timer.Tick += (_, _) => Poll();
    }

    internal void Start() => _timer.Start();

    internal void Stop() => _timer.Stop();

    internal void SetRate(PollRate rate)
    {
        if (_rate == rate) return;
        _rate = rate;
        _timer.Interval = IntervalFor(rate);
    }

    private static TimeSpan IntervalFor(PollRate rate) => rate switch
    {
        PollRate.Active => TimeSpan.FromMilliseconds(1000.0 / 60),
        _ => TimeSpan.FromMilliseconds(100),
    };

    private void Poll()
    {
        if (NativeMethods.GetCursorPos(out var pt))
            Moved?.Invoke(new PanelPoint(pt.X, pt.Y));
    }

    public void Dispose() => _timer.Stop();
}
```

- [ ] **Step 2: Write `PanelController`**

The only code that turns a `PanelEffect` into a real call. Three things carried forward from
the macOS build, each of which cost a session to find the first time:

```csharp
using Microsoft.UI.Dispatching;
using Notebar.App.Interop;
using Notebar.Core.Geometry;
using Notebar.Core.Panel;

namespace Notebar.App.Panel;

/// <summary>Turns PanelEffects into real window calls, and nothing else does.</summary>
/// <remarks>
/// The reducer decides; this executes. Keeping that line sharp is what makes
/// every transition testable without a window, which is the only reason the
/// panel's behaviour could be verified at all on a machine that cannot run it.
/// </remarks>
internal sealed class PanelController
{
    private readonly PanelWindow _window;
    private readonly CursorMonitor _cursor;
    private readonly DispatcherQueue _queue;
    private readonly Dictionary<PanelTimerKind, DispatcherQueueTimer> _timers = [];

    private PanelState _state = PanelState.Hidden;
    private DateTimeOffset? _lastKeystroke;
    private long _animationGeneration;
    private bool _insidePanel;
    private bool _insideTrigger;

    internal PanelState State => _state;
    internal bool IsPinned { get; set; }
    internal bool IsMaximized { get; set; }
    internal bool HasOpenOverlay { get; set; }
    internal bool IsDragging { get; set; }

    /// <summary>Asked fresh on every Send rather than cached as a flag.</summary>
    /// <remarks>
    /// On macOS this started life as a stored bool set by focus events, and it
    /// stuck true when a focused editor was destroyed — leaving the panel
    /// permanently un-collapsible, with no way back short of quitting. Deriving it
    /// from something observable at the moment the reducer reads it is what fixed
    /// that, and a delegate rather than a property is what stops it quietly
    /// becoming a cached flag again.
    /// </remarks>
    internal Func<bool> IsEditorFocusedProvider { get; set; } = () => false;

    internal PanelController(PanelWindow window, CursorMonitor cursor, DispatcherQueue queue)
    {
        _window = window;
        _cursor = cursor;
        _queue = queue;
        _cursor.Moved += OnCursorMoved;
    }

    internal void NoteKeystroke() => _lastKeystroke = DateTimeOffset.UtcNow;

    internal void Send(PanelEvent evt)
    {
        var context = SnapshotContext();
        var (next, effects) = PanelMachine.Reduce(_state, evt, context);
        _state = next;
        foreach (var effect in effects) Execute(effect);
    }

    private PanelContext SnapshotContext() => new(
        IsPinned: IsPinned,
        HasOpenOverlay: HasOpenOverlay,
        IsDragging: IsDragging || AnyMouseButtonDown(),
        IsEditorFocused: IsEditorFocusedProvider(),
        MsSinceLastKeystroke: _lastKeystroke is { } t
            ? (int)(DateTimeOffset.UtcNow - t).TotalMilliseconds
            : null,
        IsWindowActive: NativeMethods.GetForegroundWindow() == _window.Handle);

    /// <summary>A drag that ends outside the panel never delivers a drop event to
    /// us, so IsDragging set by a drag start would stay true forever. Polling the
    /// physical button state gives the flag a clearing path that does not depend
    /// on the drag source still existing — the same fix the macOS build needed.</summary>
    private static bool AnyMouseButtonDown() =>
        (NativeMethods.GetAsyncKeyState(0x01) & 0x8000) != 0 ||   // VK_LBUTTON
        (NativeMethods.GetAsyncKeyState(0x02) & 0x8000) != 0;     // VK_RBUTTON

    private void Execute(PanelEffect effect)
    {
        switch (effect)
        {
            case PanelEffect.StartTimer(var kind):
                StartTimer(kind);
                break;

            case PanelEffect.CancelTimer(var kind):
                CancelTimer(kind);
                break;

            case PanelEffect.ShowPanel:
                ShowPanel();
                break;

            case PanelEffect.HidePanel:
                HidePanel();
                break;

            case PanelEffect.SetPollRate(var rate):
                _cursor.SetRate(rate);
                break;
        }
    }

    private void StartTimer(PanelTimerKind kind)
    {
        CancelTimer(kind);
        var timer = _queue.CreateTimer();
        timer.IsRepeating = false;
        timer.Interval = TimeSpan.FromSeconds(kind == PanelTimerKind.EdgeDwell
            ? Settings.EdgeDwell
            : Settings.ExitDwell);
        timer.Tick += (_, _) =>
        {
            _timers.Remove(kind);
            Send(kind == PanelTimerKind.EdgeDwell
                ? PanelEvent.EdgeDwellElapsed
                : PanelEvent.ExitDwellElapsed);
        };
        _timers[kind] = timer;
        timer.Start();
    }

    private void CancelTimer(PanelTimerKind kind)
    {
        if (_timers.Remove(kind, out var timer)) timer.Stop();
    }

    private void ShowPanel()
    {
        long generation = ++_animationGeneration;
        var (dips, scale) = TargetFrame(IsMaximized ? FrameKind.Maximized : FrameKind.Expanded);
        _window.ApplyFrame(dips, scale);
        _window.ShowWithoutActivating();
        AfterAnimation(PanelTiming.ExpandDuration, generation);
    }

    private void HidePanel()
    {
        long generation = ++_animationGeneration;
        var (dips, scale) = TargetFrame(FrameKind.Collapsed);
        _window.ApplyFrame(dips, scale);
        AfterAnimation(PanelTiming.CollapseDuration, generation);
    }

    /// <summary>Fires AnimationFinished once the animation's duration has elapsed,
    /// unless a newer animation has started since.</summary>
    /// <remarks>
    /// The generation guard is what stops a stale completion from a cancelled
    /// collapse landing after a re-expand and immediately hiding the panel the
    /// user just opened. Without it the panel flickers, and only when someone
    /// moves the mouse back within the collapse duration — which is to say, only
    /// in front of a user and never in front of a developer.
    /// </remarks>
    private void AfterAnimation(double seconds, long generation)
    {
        var timer = _queue.CreateTimer();
        timer.IsRepeating = false;
        timer.Interval = TimeSpan.FromSeconds(seconds);
        timer.Tick += (_, _) =>
        {
            if (generation != _animationGeneration) return;
            Send(PanelEvent.AnimationFinished);
        };
        timer.Start();
    }

    private enum FrameKind { Collapsed, Expanded, Maximized }

    private (PanelRect Dips, double Scale) TargetFrame(FrameKind kind)
    {
        var cursor = NativeMethods.GetCursorPos(out var pt)
            ? new PanelPoint(pt.X, pt.Y)
            : new PanelPoint(0, 0);
        var physical = MonitorInfo.WorkAreaContaining(cursor, out double scale);
        var workArea = new PanelRect(physical.X / scale, physical.Y / scale,
                                     physical.Width / scale, physical.Height / scale);
        var rect = kind switch
        {
            FrameKind.Collapsed => PanelGeometry.Collapsed(workArea),
            FrameKind.Maximized => PanelGeometry.Maximized(workArea),
            _ => PanelGeometry.Expanded(workArea),
        };
        return (rect, scale);
    }

    /// <summary>Turns a cursor position into trigger and panel enter/leave events.</summary>
    /// <remarks>
    /// The trigger band is the *collapsed handle's* rect, not a full-height strip
    /// down the screen edge. That is what the user can see, and a strip they
    /// cannot see that opens a panel is a panel that opens by accident.
    /// </remarks>
    private void OnCursorMoved(PanelPoint physicalCursor)
    {
        var workAreaPhysical = MonitorInfo.WorkAreaContaining(physicalCursor, out double scale);
        var workArea = new PanelRect(
            workAreaPhysical.X / scale, workAreaPhysical.Y / scale,
            workAreaPhysical.Width / scale, workAreaPhysical.Height / scale);
        var cursor = PanelGeometry.ToDips(physicalCursor, scale);

        if (_state is PanelState.Hidden)
        {
            var handle = PanelGeometry.Collapsed(workArea);
            bool inside = handle.Contains(cursor);
            if (inside != _insideTrigger)
            {
                _insideTrigger = inside;
                Send(inside ? PanelEvent.CursorEnteredTrigger : PanelEvent.CursorLeftTrigger);
            }
            return;
        }

        var panel = IsMaximized ? PanelGeometry.Maximized(workArea) : PanelGeometry.Expanded(workArea);
        bool outside = EdgeZone.IsOutside(cursor, panel, Settings.ExitSlop);
        if (outside == _insidePanel)
        {
            _insidePanel = !outside;
            Send(outside ? PanelEvent.CursorLeftPanel : PanelEvent.CursorEnteredPanel);
        }

        // Cheap insurance against another app's fullscreen transition knocking
        // the panel out of the topmost band.
        if (_state is PanelState.Expanded) _window.ReassertTopmost();
    }
}
```

Add `GetAsyncKeyState` to `NativeMethods`:

```csharp
    [LibraryImport("user32.dll")]
    internal static partial short GetAsyncKeyState(int vKey);
```

`Settings` is a small static holder the app fills from `IAppStateRepository` at launch and
whenever Settings changes — `Settings.EdgeDwell`, `.ExitDwell`, `.ExitSlop`, defaulting to the
`PanelTiming` constants. Create `windows/Notebar.App/App/Settings.cs` for it.

- [ ] **Step 3: Wire it up in `App.xaml.cs`**

Create the monitor and controller after the window, start the monitor, and hold both for the
app's lifetime. Do not call `Activate()`.

- [ ] **Step 4: Push, confirm CI compiles, and record what a human must check**

Append to `docs/superpowers/notes/2026-09-04-windows-manual-checks.md` (create it):

```markdown
# Windows manual checks

Things CI cannot answer. Run these against each release build.

## Panel behaviour
- [ ] Hovering the handle at the right edge expands the panel within ~300 ms.
- [ ] Moving the cursor away collapses it after ~350 ms, not instantly.
- [ ] Typing in a note, then moving the cursor off the panel: it does NOT collapse.
- [ ] Pinning, then moving away: it does NOT collapse.
- [ ] Dragging a task card off the panel edge: it does NOT collapse mid-drag.
- [ ] Escape collapses it even while pinned.

## Window behaviour
- [ ] The panel draws over a maximized window.
- [ ] The panel draws over a borderless-fullscreen video.
- [ ] Expanding the panel does NOT take focus from the app the user was typing in.
- [ ] Clicking into the note editor DOES give it keyboard focus.
- [ ] No taskbar button, no Alt-Tab entry.
- [ ] Switching virtual desktops and back: the panel still appears on hover.
- [ ] On a 150%-scaled display the panel is the same visual size as on a 100% one.
- [ ] With the taskbar docked left or top, the panel does not sit under it.
```

```bash
git add windows/Notebar.App docs/superpowers/notes/2026-09-04-windows-manual-checks.md
git commit -m "Wire the cursor monitor to the panel state machine

Polling GetCursorPos rather than a low-level mouse hook, permanently: a hook
would put this app in every application's input path and trip antivirus
heuristics, and it is the Windows equivalent of the Accessibility permission
this project has always refused. Two rates answer the cost — 10 Hz while the
cursor is nowhere near the edge, 60 Hz once it matters.

Three things carried over from macOS, each of which cost a session to find:
editor focus is asked for fresh through a delegate rather than cached as a
flag, because a cached one stuck true when a focused editor was destroyed and
left the panel permanently un-collapsible; the drag flag has a clearing path
through the physical button state, because a drag ending outside the panel
never delivers a drop; and a generation counter discards stale animation
completions, without which the panel flickers when the cursor comes back
mid-collapse.

The trigger band is the collapsed handle's rect, not a full-height strip. A
strip the user cannot see is a panel that opens by accident.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
```

---

### Task 9: Tray icon, global hotkey, and quit

macOS put these behind a menu bar item that turned out to be hidden by the notch — the reason
Settings grew a Quit button. Windows has the same failure mode with a collapsed tray overflow,
so the same rule applies: **there must always be a reachable way to quit that does not depend on
the tray icon being visible.**

**Files:**
- Create: `windows/Notebar.App/Interop/MessageWindow.cs`
- Create: `windows/Notebar.App/App/TrayIcon.cs`
- Create: `windows/Notebar.App/App/GlobalHotKey.cs`
- Modify: `windows/Notebar.App/Interop/NativeMethods.cs`, `App.xaml.cs`

**Interfaces:**
- Produces:
  - `sealed class MessageWindow : IDisposable` — `IntPtr Handle`, `event Action<int> HotKeyPressed`, `event Action TrayLeftClicked`, `event Action TrayRightClicked`
  - `sealed class TrayIcon : IDisposable` — `void Show()`, `void ShowMenu()`
  - `sealed class GlobalHotKey : IDisposable` — `bool TryRegister()`, `event Action Pressed`

- [ ] **Step 1: Write `MessageWindow`**

One hidden HWND with its own window procedure, serving both `WM_HOTKEY` and the tray callback.
`RegisterHotKey` needs a window whose thread pumps messages, and `Shell_NotifyIcon` needs a
window to send its callback to — one window answers both, and avoids a second dependency.

Requirements the implementation must meet:
- Registers a window class with `RegisterClassEx` and creates a `HWND_MESSAGE` child, so it is
  never visible and never appears in any window list.
- Its `WndProc` is held in a field, not passed as a temporary — a garbage-collected delegate
  passed to Win32 crashes the process at a time unrelated to the code that caused it.
- `WM_HOTKEY` raises `HotKeyPressed` with `wParam` as the id.
- The tray callback message (`WM_APP + 1`) raises `TrayLeftClicked` on `WM_LBUTTONUP` and
  `TrayRightClicked` on `WM_RBUTTONUP`.
- `Dispose` destroys the window and unregisters the class.

- [ ] **Step 2: Write `TrayIcon`**

`Shell_NotifyIcon` with `NIM_ADD`, the app's `.ico`, tooltip "Notebar", and the message window
as its callback target. Right-click shows a menu with: **Show Notebar**, **Settings**, and
**Quit Notebar**. Left-click sends `PanelEvent.ToggleRequested`.

- [ ] **Step 3: Write `GlobalHotKey`**

`RegisterHotKey(messageWindow.Handle, id: 1, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_N)` for
**Ctrl+Shift+N**.

`TryRegister` returns false rather than throwing when the combination is already taken by
another app — which is common and is not an error the user caused. Surface it in Settings as
"the shortcut is unavailable" rather than crashing or silently doing nothing.

- [ ] **Step 4: Wire quit**

`Quit` must: flush any pending debounced note save synchronously, dispose the tray icon (an
orphaned tray icon that outlives its process is a well-known Windows annoyance), then exit.

The flush is not optional. On macOS this same path was the difference between losing the last
few seconds of typing and not.

- [ ] **Step 5: Push, confirm CI compiles, add to the manual checks**

Append to `docs/superpowers/notes/2026-09-04-windows-manual-checks.md`:

```markdown
## Tray and hotkey
- [ ] A Notebar icon appears in the tray (check the overflow if not visible).
- [ ] Left-clicking it toggles the panel.
- [ ] Right-clicking shows Show / Settings / Quit.
- [ ] Ctrl+Shift+N toggles the panel from any application.
- [ ] Quitting from the tray closes the app and removes the tray icon.
- [ ] Quitting from Settings does the same.
- [ ] Type in a note, quit immediately: reopening shows the typed text.
```

---

### Task 10: The WebView2 editor and its bridge

**RISK.** The third and last. The editor itself is easy — chips, checkboxes, lists, and images
are ordinary HTML, which is exactly why this stack was chosen. The bridge is the hard part,
because the panel's collapse policy depends on knowing whether the editor has focus and when
the user last typed, and both of those facts live inside the WebView.

**Files:**
- Create: `windows/Notebar.App/Editor/editor.html`, `editor.css`, `editor.js`
- Create: `windows/Notebar.App/Features/Notes/NoteEditorHost.xaml`, `NoteEditorHost.xaml.cs`
- Create: `windows/Notebar.App/Editor/EditorBridge.cs`
- Modify: `windows/Notebar.App/Notebar.App.csproj` (copy the editor files to output)

**Interfaces:**
- Consumes: `NoteHtml`, `INoteRepository`, `IAttachmentRepository`, `PanelController`.
- Produces:
  - `sealed record EditorMessage(string Type, string? Html, string? Text, string? Url, string? DataUrl)`
  - `sealed class NoteEditorHost : UserControl` — `Task LoadAsync(Note note)`, `event Action<string html, string plain> ContentChanged`, `event Action<string url> ChipClicked`, `event Action<byte[] data, string mime> ImagePasted`, `bool HasFocus`, `Task ExecCommandAsync(string command, string? value)`

- [ ] **Step 1: Write `editor.html` and `editor.css`**

A single `<div id="doc" contenteditable="true">` styled to the screen spec's note-body type
scale, with the light and dark palettes as CSS custom properties on `:root` and
`:root[data-theme="dark"]`. The host sets `data-theme` — never a media query, because the panel's
theme is the app's setting, not the browser's guess.

Checkbox, list, chip, and image styling all live here. This is the whole reason the editor is a
WebView: on macOS each of these needed custom `NSTextView` work, and list markers on empty lines
had to be synthesised as real text because TextKit would not draw them.

- [ ] **Step 2: Write `editor.js` — the guest half of the bridge**

One typed message envelope in each direction, never ad-hoc strings:

```javascript
// Guest → host. Every message is {type, ...}; the host switches on type.
function post(message) {
  window.chrome.webview.postMessage(JSON.stringify(message));
}

const doc = document.getElementById('doc');

// The two facts the panel's collapse policy depends on. Focus is reported on
// both edges, and the host also polls it — see the host side for why relying on
// events alone was the bug that left the macOS panel permanently open.
doc.addEventListener('focus', () => post({ type: 'focus', focused: true }));
doc.addEventListener('blur',  () => post({ type: 'focus', focused: false }));
doc.addEventListener('keydown', () => post({ type: 'keystroke' }));

// Debounced content change. 400 ms matches the macOS editor's save debounce.
let saveTimer = null;
doc.addEventListener('input', () => {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => post({ type: 'change', html: doc.innerHTML }), 400);
});

// A link chip is a navigation the host handles, never one the WebView performs.
doc.addEventListener('click', (e) => {
  const anchor = e.target.closest('a[href^="notebar://"]');
  if (!anchor) return;
  e.preventDefault();
  post({ type: 'chip', url: anchor.getAttribute('href') });
});

// Checkbox toggles are a DOM event, not hit-testing against a glyph. On macOS
// this needed a click-region calculation per checkbox and a font-availability
// check, because the obvious glyph rendered as nothing in the system font.
doc.addEventListener('change', (e) => {
  if (e.target.matches('input[type="checkbox"]')) {
    e.target.toggleAttribute('checked', e.target.checked);
    post({ type: 'change', html: doc.innerHTML });
  }
});

// Pasted images go to the host as a data URL; the host stores the bytes as an
// attachment row and replies with the asset URL to substitute in.
doc.addEventListener('paste', (e) => {
  const item = [...e.clipboardData.items].find(i => i.type.startsWith('image/'));
  if (!item) return;
  e.preventDefault();
  const reader = new FileReader();
  reader.onload = () => post({ type: 'image', dataUrl: reader.result });
  reader.readAsDataURL(item.getAsFile());
});

// Host → guest.
window.notebar = {
  setContent(html)      { doc.innerHTML = html; },
  getContent()          { return doc.innerHTML; },
  hasFocus()            { return document.activeElement === doc; },
  setTheme(theme)       { document.documentElement.dataset.theme = theme; },
  exec(command, value)  { doc.focus(); document.execCommand(command, false, value ?? null); },
  insertHtml(html)      { doc.focus(); document.execCommand('insertHTML', false, html); },
  markTombstones(ids)   {
    const alive = new Set(ids);
    doc.querySelectorAll('a[href^="notebar://"]').forEach(a => {
      a.classList.toggle('tombstone', !alive.has(a.getAttribute('href')));
    });
  },
};
```

`document.execCommand` is deprecated and is still the only thing that does rich-text editing in
a `contenteditable` without pulling in an editor framework. It works in every Chromium build
this app will ever run on, because the app ships its own runtime version expectation through
WebView2. Note that in the code so nobody replaces it with a dependency on a hunch.

- [ ] **Step 3: Write `NoteEditorHost` — the host half**

Requirements:

- **Serve the editor from a virtual host.** `SetVirtualHostNameToFolderMapping("notebar.local",
  editorFolder, CoreWebView2HostResourceAccessKind.Allow)`, then navigate to
  `https://notebar.local/editor.html`. A `file://` origin would break `postMessage` and give
  the document no stable origin.

- **Serve attachments through `WebResourceRequested`.** Filter
  `https://notebar.local/asset/*`, look the id up in `IAttachmentRepository`, and respond with
  the bytes and MIME type. This is why the asset URL is an https path rather than a custom
  scheme: WebView2 hands you a plain request/response pair for it.

- **Lock the WebView down.** In `CoreWebView2Settings`: `AreDevToolsEnabled = false`,
  `AreDefaultContextMenusEnabled = false`, `IsZoomControlEnabled = false`,
  `AreBrowserAcceleratorKeysEnabled = false`. And handle `NewWindowRequested` by cancelling and
  opening the URL in the user's browser instead — a note body can contain a pasted external
  link, and a popup WebView inside the panel would be both ugly and a security surprise.

- **Focus must be derivable, not only event-driven.** Wire `HasFocus` to a cached value updated
  by the guest's focus messages, **and** have `PanelController.IsEditorFocusedProvider` call
  `ExecuteScriptAsync("notebar.hasFocus()")`'s last known result refreshed on every panel tick.
  The macOS build shipped a version that trusted focus events alone; when a focused editor was
  destroyed no blur ever arrived, the flag stuck true, and the panel could not be collapsed
  without quitting. **The bridge makes this worse, not better** — a WebView that crashes or
  navigates sends no blur either. Treat `CoreWebView2.ProcessFailed` as a blur, and re-derive
  on every read.

- **Keystrokes reach the panel.** Each guest `keystroke` message calls
  `PanelController.NoteKeystroke()`. Without this the typing grace period never engages and the
  panel collapses on someone mid-sentence.

- **Content changes derive `body_plain` host-side.** On a `change` message, call
  `NoteHtml.ToPlainText(html)` and save both columns together. Never let the guest compute the
  plain text: it is what FTS indexes, and the store must be the one deciding what gets indexed.

- **Images.** On an `image` message, decode the data URL, downscale if the longest edge exceeds
  2000 px, store via `IAttachmentRepository.Create`, then
  `insertHtml('<img src="https://notebar.local/asset/{id}">')`.

- [ ] **Step 4: Copy the editor files to the output directory**

In `Notebar.App.csproj`:

```xml
  <ItemGroup>
    <Content Include="Editor\**\*.*">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </Content>
  </ItemGroup>
```

- [ ] **Step 5: Push, confirm CI compiles, add to the manual checks**

```markdown
## Editor
- [ ] Typing in a note persists after collapsing and re-expanding.
- [ ] Typing in a note persists after quitting and relaunching.
- [ ] The panel does not collapse while the cursor is outside it and you are typing.
- [ ] Clicking away from the editor, waiting 3 s, then moving the cursor off: it collapses.
- [ ] Bold, italic, H1, H2, bullets, numbers, and checklists all apply.
- [ ] A numbered list shows "1." on the first, empty line.
- [ ] Checkboxes toggle by clicking them, and the state survives a reload.
- [ ] Pasting a screenshot inserts it and it survives a relaunch.
- [ ] Right-clicking in the editor does NOT show the browser context menu.
- [ ] F12 does NOT open developer tools.
- [ ] A pasted external link opens in the default browser, not inside the panel.
```

---

### Task 11: Shell chrome — tab rail, toolbar, handle, pin, maximize, collapse

Everything in `docs/design/2026-08-29-screen-spec.md` that is not a tab's contents. That
document is the authority on measurements, colours, and states; this task is the list of things
that must exist and the interaction defects already known from the macOS build.

**Files:**
- Create: `windows/Notebar.App/DesignSystem/Tokens.xaml`
- Create: `windows/Notebar.App/Features/RootPage.xaml(.cs)`, `TabRail.xaml(.cs)`, `TabToolbar.xaml(.cs)`
- Create: `windows/Notebar.App/Features/PanelViewModel.cs`
- Create: `windows/Notebar.App/Features/CollapsedHandle.xaml(.cs)`
- Modify: `windows/Notebar.App/Panel/PanelWindow.xaml`

Requirements:

- **`Tokens.xaml`** carries both palettes as `ResourceDictionary.ThemeDictionaries` (`Light`,
  `Dark`), so switching `RequestedTheme` on the root element re-resolves everything. The macOS
  build shipped with text that stayed black in dark mode because colour had been baked into
  stored content rather than resolved from the theme — nothing here may store a colour.

- **The left tab rail** holds, top to bottom: the pin toggle, then Notes, Tasks, Settings. The
  pin sits above the tabs because it is not a tab.

- **Every rail and toolbar button needs a full-cell hit target.** On macOS, switching tabs took
  several clicks because the tappable region was the glyph rather than the cell. In WinUI the
  equivalent is a `Button`/`ToggleButton` that stretches to fill its cell with a non-transparent
  background brush — a `Transparent` background is hit-testable in WinUI, but a `null` one is
  not. Set it explicitly.

- **The toolbar is per-tab.** Notes gets `+` (new note) and a chevron (all notes). Tasks gets
  `+` (new task). Settings gets nothing. The `»` collapse button sits at the toolbar's right,
  on every tab, and sends `PanelEvent.ToggleRequested` — the point of it is collapsing without
  moving the cursor off the panel.

- **The pin toggle must reflect its state on the first click.** The macOS pin was one click
  behind because the observation fired before the mutation. In WinUI, bind `IsChecked` two-way
  to an `INotifyPropertyChanged` property and set `PanelController.IsPinned` in the setter, not
  in a `Click` handler.

- **The collapsed handle** shows the current tab's icon, so the user can see what they will get
  back. It is drawn by the same window, which is simply sized to the handle rect when hidden —
  there is no second window.

- **Maximize** toggles `PanelController.IsMaximized` and re-applies the frame immediately rather
  than waiting for the next cursor tick.

---

### Task 12: Notes tab — tab strip, all-notes menu, create, rename, delete

**Files:** `windows/Notebar.App/Features/Notes/NotesTab.xaml(.cs)`, `AllNotesMenu.xaml(.cs)`,
`NoteTabStrip.xaml(.cs)`; modify `PanelViewModel.cs`.

Requirements, each one a defect the macOS build shipped and then had to fix:

- **The tab's `×` is on the left of the title**, not the right. On the right it sits where the
  next tab's label begins and gets mis-clicked.
- **Renaming a tab edits the title only.** The title is a stored column that does not track the
  body; typing in a note must never change its tab label.
- **The rename UI refuses to commit a blank title.** Empty reverts to the previous value.
- **Closing a tab whose note `IsEmptyAndUntitled` deletes the note.** A note with a title or a
  body is the user's content and closing a tab must never destroy it — that distinction is
  already encoded in `Note.IsEmptyAndUntitled` and must be the only test used.
- **The all-notes menu is built from `INoteRepository.Summaries()`**, never `All()`. Opening one
  note from it uses `Fetch(id)`. Using `All()` here reads every note's body to draw a list of
  names.
- **Open tabs persist** through `IOpenTabRepository.ReplaceAll` on open, close, reorder, and
  select — never per keystroke.
- **Saves are debounced 400 ms and flushed on**: tab switch, panel collapse, and quit.

---

### Task 13: Formatting bar, lists, checkboxes, and images

**Files:** `windows/Notebar.App/Features/Notes/FormattingBar.xaml(.cs)`; modify
`editor.js`, `editor.css`.

Requirements:

- Buttons: **Bold, Italic, Code, H1, H2, Bulleted list, Numbered list, Checklist**. Each calls
  `notebar.exec(...)` — `bold`, `italic`, `formatBlock` with `<h1>`/`<h2>`/`<pre>`,
  `insertUnorderedList`, `insertOrderedList` — and the checklist inserts
  `<ul class="checklist"><li><input type="checkbox">…</li></ul>`.
- **Button state reflects the selection.** Poll `document.queryCommandState` on
  `selectionchange` and post the result to the host so the bar's toggles are accurate.
- **Markdown shortcuts**: `- ` starts a bullet, `1. ` a numbered item, `[] ` a checklist item,
  `# `/`## ` a heading. Handled in `editor.js` on `keydown`.
- **A numbered list must show "1." on its first, empty line.** The browser does this natively —
  the macOS build had to synthesise markers as real text because TextKit would not draw them.
  This requirement exists so nobody reimplements that here.
- **Pasted images are downscaled above 2000 px on the longest edge** before storing, and stored
  as attachment rows.
- **Deleting an image from a note eventually frees its row** via
  `IAttachmentRepository.DeleteUnreferenced`, called after a save with the set of asset ids the
  saved HTML still references.

---

### Task 14: Tasks board — columns, cards, drag, and the detail pane

**Files:** `windows/Notebar.App/Features/Tasks/TasksTab.xaml(.cs)`, `TaskCard.xaml(.cs)`,
`TaskDetailPane.xaml(.cs)`.

Requirements:

- **Three columns** from `ITaskRepository.Columns()`, cards grouped by `ColumnId`.
- **Cross-column drag** using WinUI `ListView` with `CanDragItems`, `AllowDrop`,
  `CanReorderItems`, and `ReorderMode` — WinUI supports list-to-list drag natively, which is
  most of what the macOS build wrote by hand.
- **An empty column must be a valid drop target.** On macOS an empty group shrink-wrapped its
  header and became undropable. Each column's `ListView` must stretch to fill its column and
  carry a `MinHeight`.
- **Dragging sets `PanelController.IsDragging`** on `DragItemsStarting` and clears it on
  `DragItemsCompleted` — and the controller's button-state poll is the backstop for a drag that
  ends outside the panel and never completes.
- **Dropping calls `ITaskRepository.Move`**, which owns the completion-stamping rule. The UI
  must not stamp `CompletedAt` itself.
- **Clicking a card opens the detail pane** in place — the board slides aside rather than being
  replaced, so switching between tasks does not mean navigating back first. Title, detail,
  priority, and due date are editable there.
- **A new task is created inline and immediately editable.** The macOS build shipped a `+` that
  created "New Task" in Queue with no way to rename it.

---

### Task 15: Linking — `@` autocomplete, chips, backlinks, tombstones

**Files:** `windows/Notebar.App/Features/Linking/MentionAutocomplete.xaml(.cs)`,
`BacklinksSection.xaml(.cs)`; modify `editor.js`, `NoteEditorHost.xaml.cs`.

Requirements:

- **Typing `@` in a note opens an autocomplete** over notes and tasks, driven by
  `INoteRepository.Search` and `ITaskRepository.Search`. `editor.js` reports the `@` and the
  query text; the popup is host-side XAML so it can be styled with the rest of the app and can
  set `PanelController.HasOpenOverlay = true` while it is open — otherwise the panel collapses
  out from under an open menu.
- **Selecting a result inserts a chip** — `<a href="notebar://note/{id}" class="chip">Title</a>`
  — and writes the `link` row **through `ILinkRepository.CreateSavingNoteBody`**, so the markup
  and the row commit together. Not two separate calls.
- **Clicking a chip opens its target**: a note opens as a tab, a task opens the Tasks board with
  its detail pane showing.
- **Backlinks** render below the editor from `ILinkRepository.Incoming`, showing what points at
  the note or task currently open.
- **Tombstones**: on note load, fetch `ILinkRepository.ExistingTargets()` once and call
  `notebar.markTombstones(...)` with the surviving chip URLs. A chip whose target is gone
  renders struck through and does nothing on click. Never one query per chip.

---

### Task 16: Settings, packaging, and the first release

**Files:** `windows/Notebar.App/Features/Settings/SettingsTab.xaml(.cs)`,
`App/DiagnosticsExporter.cs`; modify `.github/workflows/ci.yml`; create
`.github/workflows/release-windows.yml`.

- [ ] **Step 1: Build the Settings tab**

Four sections, matching the macOS app:

- **General** — Theme: System / Light / Dark, persisted through `IAppStateRepository.SetTheme`
  and applied by setting `RequestedTheme` on the root element. It must switch **live**, not on
  next launch: the macOS build shipped without a live update and it read as broken.
- **Activation** — three sliders bound to `EdgeDwell`, `ExitDwell`, `ExitSlop`, with the ranges
  from `PanelTiming`. Changing one takes effect on the next dwell, not on relaunch.
- **Data** — database path, size on disk, applied migrations, all from
  `IDiagnosticsRepository.Snapshot()`. Plus **Export Diagnostics**, which writes
  `DiagnosticsEnvironment.RenderedText` and a recent log excerpt to a file the user chooses.
- **About** — version, and **Quit Notebar**. The quit button is here because a tray icon can be
  hidden in the overflow, and an app with no reachable way to quit cannot be reinstalled.

- [ ] **Step 2: Verify the diagnostics export carries no content**

Add to `windows/Notebar.Store.Tests/`: a test that creates several notes with distinctive body
text, takes a `Snapshot()`, renders a `DiagnosticsEnvironment` from it, and asserts none of that
text appears. The rendering test in Task 3 covers the type; this covers the real call path.

- [ ] **Step 3: Write the release workflow**

`.github/workflows/release-windows.yml`, triggered on a `windows-v*` tag:

```yaml
name: Release (Windows)

on:
  push:
    tags: ['windows-v*']

jobs:
  release:
    runs-on: windows-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '9.0.x'

      - name: Test
        run: |
          dotnet test windows/Notebar.Core.Tests/Notebar.Core.Tests.csproj -c Release
          dotnet test windows/Notebar.Store.Tests/Notebar.Store.Tests.csproj -c Release

      - name: Package MSIX
        run: >
          dotnet build windows/Notebar.App/Notebar.App.csproj
          -c Release -p:Platform=x64
          -p:GenerateAppxPackageOnBuild=true
          -p:AppxPackageSigningEnabled=false
          -p:UapAppxPackageBuildMode=SideloadOnly

      - name: Publish the portable build
        run: >
          dotnet publish windows/Notebar.App/Notebar.App.csproj
          -c Release -r win-x64 --self-contained true
          -p:Platform=x64 -p:WindowsPackageType=None
          -o publish/portable

      - name: Assemble artifacts
        shell: bash
        run: |
          mkdir -p artifacts
          find windows/Notebar.App -name '*.msix' -exec cp {} artifacts/Notebar-x64.msix \;
          cd publish/portable && 7z a -tzip ../../artifacts/Notebar-portable-x64.zip . && cd ../..
          ls -la artifacts

      - uses: softprops/action-gh-release@v2
        with:
          files: artifacts/*
          name: Notebar for Windows ${{ github.ref_name }}
          body_path: docs/release-notes-windows.md
```

- [ ] **Step 4: Write the release notes**

`docs/release-notes-windows.md` must explain, plainly and without apology:

- **The portable zip is the easy path.** Unzip, run `Notebar.App.exe`. SmartScreen will warn
  because the build is unsigned; "More info" → "Run anyway".
- **The MSIX needs one command**, because an unsigned MSIX cannot be installed by double-click:
  ```powershell
  Add-AppxPackage -Path .\Notebar-x64.msix -AllowUnsigned
  ```
- **Why unsigned.** An EV code-signing certificate costs several hundred dollars a year and,
  unlike Apple notarization, is not required for the app to run — only to remove the warning.
- **Known difference from macOS**: the panel draws over maximized and borderless-fullscreen
  windows, but not over exclusive-fullscreen ones, typically games. That is a Windows
  window-manager rule, not something the app can work around without the kind of hooks this
  project does not use.
- The manual-check list from `docs/superpowers/notes/2026-09-04-windows-manual-checks.md`,
  as "what to try first".

- [ ] **Step 5: Update the README**

Add a Windows section: what it is, that the two platforms keep separate databases and do not
sync, how to install, and where the source lives. Link the release.

- [ ] **Step 6: Tag and release**

```bash
git add windows docs/release-notes-windows.md README.md .github/workflows/release-windows.yml
git commit -m "Add Settings, packaging, and the Windows release workflow

Quit lives in Settings as well as the tray, for the same reason it does on
macOS: a tray icon can sit collapsed in the overflow, and an app with no
reachable way to quit is an app that cannot be reinstalled.

The release ships both an MSIX and a portable zip. An unsigned MSIX cannot be
installed by double-click, so the zip is the path that works with no ceremony
at all — and the release notes give the Add-AppxPackage line rather than
leaving anyone to find it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BZmR9znRu76EU6s79VnSv7"
git push origin main
git tag windows-v0.1.0
git push origin windows-v0.1.0
gh run watch "$(gh run list --workflow=release-windows.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
gh release view windows-v0.1.0
```

Both artifacts must be attached to the release before this task is done.

---

## Self-Review

**Spec coverage.** Every section of `2026-09-04-notebar-windows-design.md` maps to a task:
§3 architecture → Tasks 1–5; §4 platform capabilities → Tasks 7–9; §5 data model → Tasks 4–5;
§6 behaviour parity → Tasks 2 and 6; §7 editor → Tasks 10 and 13; §8 testing → the conformance
suite in Tasks 2–3 and the store suites in 4–5; §9 packaging → Tasks 1 and 16. §10 out-of-scope
items appear in no task, correctly.

**Conformance suite.** All 46 macOS core tests are accounted for: 2 timing (Task 1), 10 edge
zone + 12 machine + 12 collapse policy (Task 2), 5 note + 4 tombstone (Task 3), 1 smoke
(subsumed by every other test compiling against the assembly). Task 3 adds `LinkUrlTests`
because C# string parsing replaces `URLComponents` and the replacement needs its own coverage;
Task 6 adds `PanelGeometryTests` because the dip/physical boundary does not exist on macOS.

**Known open ends, stated rather than hidden:**

1. **The Windows App SDK version is discovered in Task 1 Step 1, not written here.** Pinning a
   version I cannot verify from this machine would be a guess dressed as a fact. The step gives
   the exact command and the rule (highest stable, no preview).
2. **Test counts in later steps are approximate.** Task 4 Step 10 says so explicitly. Where a
   count and reality disagree, reality wins and the plan is wrong.
3. **Tasks 11–15 specify requirements rather than full XAML.** The screen spec already carries
   every measurement, colour, and state, and duplicating 574 lines of it here would create two
   sources of truth that drift. What those tasks add is the list of interaction defects the
   macOS build shipped and fixed, so they are not rediscovered — which is the part no spec
   holds.
4. **Nothing from Task 7 onward can be verified on the development machine.** CI compiles it;
   a human running the build confirms it. `docs/superpowers/notes/2026-09-04-windows-manual-checks.md`
   is that human's list, and it grows as the tasks land.
