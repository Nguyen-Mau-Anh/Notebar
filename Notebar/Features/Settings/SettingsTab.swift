import AppKit
import SwiftUI
import NotebarCore

/// Settings' sectioned list (spec §6.5), built to grow. Appearance, Data,
/// and General are real; Activation stays an inert placeholder row (spec
/// §6.5's one-line description) until its own settings land in a later
/// pass. Deliberately not a settings framework: one section header plus a
/// column of rows is enough for four sections, and adding a fifth is
/// copy-paste, not a new abstraction.
struct SettingsTab: View {
    let model: PanelViewModel

    /// `0.1.0 (1)` — read straight from the bundle rather than
    /// hand-maintained anywhere, so it can never drift from what
    /// `project.yml`'s `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` actually
    /// produced (spec §6.4b).
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var databaseSizeText: String {
        guard let size = model.databaseDiagnostics()?.sizeOnDisk else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabToolbar {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
            } right: {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                    SettingsSection(title: "Appearance") {
                        SettingsRow(title: "Theme") {
                            Picker(
                                "Theme",
                                selection: Binding(
                                    get: { model.theme },
                                    set: { model.setTheme($0) }
                                )
                            ) {
                                Text("System").tag(Theme.system)
                                Text("Light").tag(Theme.light)
                                Text("Dark").tag(Theme.dark)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                    }

                    SettingsSection(title: "Activation") {
                        SettingsComingSoonRow(detail: "Edge trigger, dwell timing, global hotkey.")
                    }

                    SettingsSection(title: "Data") {
                        DataLocationRow(model: model)
                        SettingsRow(title: "Size on disk") {
                            Text(databaseSizeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        SettingsRow(title: "Diagnostics") {
                            Button("Export…") {
                                DiagnosticsExporter.export(model: model)
                            }
                        }
                    }

                    SettingsSection(title: "General") {
                        SettingsRow(title: "Version") {
                            Text(appVersionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        SettingsComingSoonRow(detail: "Launch at login.")
                    }
                }
                .padding(Tokens.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A section header plus a column of rows sharing one rounded background —
/// the "sectioned list" this view is built around.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
        }
    }
}

/// One settings row: a title on the left, an arbitrary control on the right
/// — today only the Theme picker, but the shape any future real control
/// slots into. Applied here rather than to the Theme row alone so Activation,
/// Data, and General inherit the same metrics the moment their placeholder
/// rows grow real controls (spec §6.5).
///
/// At the default 340pt panel the content area is only 283pt wide, and a
/// segmented picker claims the width it wants — with no line limit or
/// priority on the label, the label is what gave, wrapping "Theme" into
/// "The / me". `lineLimit(1)` plus `layoutPriority` over the control fixes
/// that; `.controlSize(.small)` is the right density for a panel this
/// narrow and buys back roughly 20pt on top. `ViewThatFits` is the fallback
/// for a control that still doesn't fit beside its label even then: label
/// above, control below at full width — a fallback, not the default, since
/// vertical space in a 745pt panel is scarcer than it looks once several
/// sections exist.
private struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                label
                Spacer(minLength: Tokens.Space.sm)
                trailing
            }

            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                label
                trailing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .controlSize(.small)
        .padding(Tokens.Space.sm)
    }

    private var label: some View {
        Text(title)
            .font(.system(size: 13))
            .lineLimit(1)
            .layoutPriority(1)
    }
}

/// Data section's first row (spec §6.5): the database's on-disk path, with
/// a *Reveal in Finder* action. Not a plain `SettingsRow` — the path itself
/// needs its own line, since a full filesystem path and a button rarely fit
/// on one line even before `ViewThatFits`'s stacking fallback kicks in, and
/// stacking would visually separate the button from the path it acts on.
/// `.truncationMode(.head)` keeps the filename (the end of the path) visible
/// when it doesn't fit, since that's the part that actually identifies the
/// file — `notebar.sqlite`, not `/Users/…`.
private struct DataLocationRow: View {
    let model: PanelViewModel

    var body: some View {
        let diagnostics = model.databaseDiagnostics()
        let path = diagnostics?.path

        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack {
                Text("Location")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: Tokens.Space.sm)
                Button("Reveal in Finder") {
                    guard let path else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .disabled(path == nil)
            }

            Text(path ?? "Using a temporary in-memory store — the on-disk database couldn't be opened.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .controlSize(.small)
        .padding(Tokens.Space.sm)
    }
}

/// A row for a section that has no control yet — spec §6.5's per-section
/// description, trailing a "Coming soon" tag rather than a chevron:
/// deliberately no click affordance on a row that does nothing yet.
private struct SettingsComingSoonRow: View {
    let detail: String

    var body: some View {
        HStack {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.sm)
            Text("Coming soon")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(Tokens.Space.sm)
    }
}

#Preview("Settings") {
    SettingsTab(model: PanelViewModel()).frame(width: 340, height: 500)
}

/// Shared empty state so all three tabs look deliberate rather than unfinished.
struct PlaceholderTab: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Tokens.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
