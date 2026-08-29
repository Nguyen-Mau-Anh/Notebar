import SwiftUI
import NotebarCore

/// Settings' first real control (spec §6.5): a sectioned list, built to grow
/// — Appearance ships a working Theme picker today; Activation, Data, and
/// General stay inert placeholder rows (carrying the one-line descriptions
/// spec §6.5 already gives them) until their own settings land. Deliberately
/// not a settings framework: one section header plus a column of rows is
/// enough for four sections, and adding a fifth is copy-paste, not a new
/// abstraction.
struct SettingsTab: View {
    let model: PanelViewModel

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
                        SettingsComingSoonRow(detail: "Database location, export.")
                    }

                    SettingsSection(title: "General") {
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
