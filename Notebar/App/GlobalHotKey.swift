import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// Carbon is ancient, but it is the only permission-free way to register a
/// global hotkey on macOS — `NSEvent.addGlobalMonitorForEvents` for key events
/// requires Accessibility permission, which spec section 1 rules out. Every
/// launcher app on the platform does this.
@MainActor
final class GlobalHotKey {

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    // `nonisolated(unsafe)`: `deinit` on a `@MainActor` class is itself
    // nonisolated, so it cannot touch a MainActor-isolated static property.
    // Safe in practice because every `GlobalHotKey` is created and torn down
    // on the main thread (AppDelegate is the only owner).
    fileprivate nonisolated(unsafe) static var callbacks: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `UInt32(kVK_Space)`.
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(cmdKey | shiftKey)`.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.callbacks[id] = handler
        Self.installHandlerIfNeeded()

        // 'NBR1' as a four-character code.
        let hotKeyID = EventHotKeyID(signature: 0x4E42_5231, id: id)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            NSLog("GlobalHotKey: registration failed with status \(status)")
            Self.callbacks[id] = nil
            return nil
        }
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        GlobalHotKey.callbacks[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            nil,
            nil
        )
    }
}

/// A free function, because `InstallEventHandler` takes a C function pointer,
/// which a Swift method or capturing closure cannot be.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GlobalHotKey.callbacks[id]?()
        }
    }
    return noErr
}
