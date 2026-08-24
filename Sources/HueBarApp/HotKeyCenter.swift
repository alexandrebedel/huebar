import AppKit
import Carbon.HIToolbox

/// Hotkey global via l'API Carbon (aucune permission d'accessibilité requise).
final class HotKeyCenter {
    static var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?

    /// Enregistre ⌥H.
    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.action?() }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x48554241), id: 1) // "HUBA"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_H), UInt32(optionKey), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }
}
