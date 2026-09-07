import AppKit
import Carbon.HIToolbox

/// Un atajo de teclado configurable por el usuario.
///
/// Guarda el código físico de la tecla, no el carácter, de modo que el atajo sigue funcionando
/// aunque se cambie la distribución del teclado. Para mostrarlo se traduce el código con la
/// distribución activa, así un teclado español enseña «Ñ» donde corresponde.
struct GlobalShortcut: Equatable, Codable {

    /// Código físico de la tecla (`kVK_*`).
    var keyCode: UInt16
    /// Modificadores en el formato de `NSEvent.ModifierFlags`.
    var modifierFlags: UInt

    init(keyCode: UInt16, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = UInt16(keyCode)
        self.modifierFlags = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
    }

    /// Un atajo global debe llevar al menos ⌘, ⌥ o ⌃; si no, secuestraría teclas normales.
    var isValid: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    // MARK: - Conversión a Carbon

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    // MARK: - Presentación

    /// Representación legible, en el orden que usa macOS: ⌃ ⌥ ⇧ ⌘.
    var display: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += GlobalShortcut.keyName(for: keyCode)
        return result
    }

    /// Nombre visible de la tecla, traducido con la distribución de teclado activa.
    static func keyName(for keyCode: UInt16) -> String {
        if let special = specialKeyNames[Int(keyCode)] {
            return special
        }
        if let character = character(for: keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "?"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Espacio",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// Traduce un código de tecla al carácter que produce con la distribución actual.
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let base = buffer.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)

            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)

            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0, // sin modificadores: interesa la tecla base
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )

            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}

extension GlobalShortcut {
    /// ⌥⇧⌘F — captura de pantalla completa.
    static let defaultFullScreen = GlobalShortcut(keyCode: kVK_ANSI_F, modifiers: [.command, .shift, .option])
    /// ⌥⇧⌘S — captura de una región.
    static let defaultRegion = GlobalShortcut(keyCode: kVK_ANSI_S, modifiers: [.command, .shift, .option])
}
