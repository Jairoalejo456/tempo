import AppKit
import Carbon.HIToolbox

/// Registro de atajos globales mediante la API de Carbon `RegisterEventHotKey`.
///
/// Se eligió esta API en lugar de `NSEvent.addGlobalMonitorForEvents` porque no exige el
/// permiso de Accesibilidad: el sistema entrega el atajo directamente a la aplicación aunque
/// esté en segundo plano. Sigue siendo la vía admitida en macOS actual para atajos globales.
final class HotKeyManager {

    struct Shortcut {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        /// Representación legible, p. ej. "⌥⇧⌘F". Se muestra en el menú y en el README.
        let display: String
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    static let shared = HotKeyManager()

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    // MARK: - Atajos de la aplicación

    static let fullScreenShortcut = Shortcut(
        keyCode: UInt32(kVK_ANSI_F),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey),
        display: "⌥⇧⌘F"
    )

    static let regionShortcut = Shortcut(
        keyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey),
        display: "⌥⇧⌘S"
    )

    // MARK: - Registro

    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            NSLog("[Tempo] No se pudo registrar el atajo \(shortcut.display) (OSStatus \(status)); probablemente ya está en uso por otra aplicación.")
            return false
        }

        registrations[id] = Registration(ref: reference, action: action)
        return true
    }

    func unregisterAll() {
        for (_, registration) in registrations {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    // MARK: - Interno

    private static let signature: OSType = {
        // 'TMPO'
        let chars: [UInt8] = Array("TMPO".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(id: hotKeyID.id)
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(),
                            callback,
                            1,
                            &eventType,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &eventHandler)
    }

    private func handle(id: UInt32) {
        guard let registration = registrations[id] else { return }
        DispatchQueue.main.async {
            registration.action()
        }
    }
}
