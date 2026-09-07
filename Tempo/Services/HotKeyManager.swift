import AppKit
import Carbon.HIToolbox

/// Registro de atajos globales mediante la API de Carbon `RegisterEventHotKey`.
///
/// Se eligió esta API en lugar de `NSEvent.addGlobalMonitorForEvents` porque no exige el
/// permiso de Accesibilidad: el sistema entrega el atajo directamente a la aplicación aunque
/// esté en segundo plano. Sigue siendo la vía admitida en macOS actual para atajos globales.
final class HotKeyManager {

    /// Acciones que la aplicación puede lanzar desde un atajo global.
    enum Action: String, CaseIterable, Identifiable {
        case captureFullScreen
        case captureRegion

        var id: String { rawValue }

        var title: String {
            switch self {
            case .captureFullScreen: return "Capturar pantalla completa"
            case .captureRegion: return "Capturar región"
            }
        }
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let action: Action
    }

    static let shared = HotKeyManager()

    /// Se invoca cuando se pulsa un atajo registrado.
    var handler: ((Action) -> Void)?

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    /// Atajos que no pudieron registrarse (normalmente porque otra aplicación los ocupa).
    private(set) var failedActions: Set<Action> = []

    private init() {}

    // MARK: - Registro

    /// Registra los atajos configurados, reemplazando los anteriores.
    /// Se llama al arrancar y cada vez que el usuario cambia un atajo en los ajustes.
    @discardableResult
    func reload(with preferences: Preferences) -> Set<Action> {
        unregisterAll()
        register(preferences.fullScreenShortcut, for: .captureFullScreen)
        register(preferences.regionShortcut, for: .captureRegion)
        return failedActions
    }

    @discardableResult
    func register(_ shortcut: GlobalShortcut, for action: Action) -> Bool {
        guard shortcut.isValid else {
            failedActions.insert(action)
            return false
        }
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            NSLog("[Tempo] No se pudo registrar el atajo \(shortcut.display) (OSStatus \(status)); probablemente ya está en uso por otra aplicación.")
            failedActions.insert(action)
            return false
        }

        registrations[id] = Registration(ref: reference, action: action)
        failedActions.remove(action)
        return true
    }

    func unregisterAll() {
        for (_, registration) in registrations {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        failedActions.removeAll()
    }

    // MARK: - Interno

    private static let signature: OSType = {
        // 'TMPO'
        Array("TMPO".utf8).reduce(OSType(0)) { ($0 << 8) | OSType($1) }
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
        DispatchQueue.main.async { [weak self] in
            self?.handler?(registration.action)
        }
    }
}
