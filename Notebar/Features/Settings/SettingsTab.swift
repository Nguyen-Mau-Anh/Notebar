import SwiftUI

struct SettingsTab: View {
    var body: some View {
        VStack(spacing: 0) {
            TabToolbar {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
            } right: {
                EmptyView()
            }

            PlaceholderTab(
                symbol: "gearshape",
                title: "Settings",
                detail: "Activation, appearance, and data settings, arriving in M4."
            )
        }
    }
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
