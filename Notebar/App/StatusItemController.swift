import AppKit

/// The menu bar presence. With `LSUIElement` there is no Dock icon, so this is
/// the only way to quit the app or summon the panel by mouse.
@MainActor
final class StatusItemController {

    private let item: NSStatusItem

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "sidebar.right",
                accessibilityDescription: "Notebar"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Show Notebar",
            action: #selector(MenuTarget.toggle),
            keyEquivalent: ""
        )
        let quit = NSMenuItem(
            title: "Quit Notebar",
            action: #selector(MenuTarget.quit),
            keyEquivalent: "q"
        )

        let target = MenuTarget(onToggle: onToggle, onQuit: onQuit)
        toggle.target = target
        quit.target = target
        // The menu holds the only strong reference to the target.
        self.target = target

        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.menu = menu
    }

    private var target: MenuTarget?
}

/// NSMenuItem actions need an Objective-C target, which a Swift closure cannot be.
private final class MenuTarget: NSObject {
    private let onToggle: () -> Void
    private let onQuit: () -> Void

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
    }

    @objc func toggle() { onToggle() }
    @objc func quit() { onQuit() }
}
