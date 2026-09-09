import Foundation

/// Renumeración de un contador tecleando directamente, sin cuadro de texto ni confirmación.
///
/// Con un contador seleccionado, cada dígito cambia su número al momento. Los dígitos escritos
/// seguidos se van componiendo —`2` y luego `5` dan 25— y, tras una breve pausa, el siguiente
/// dígito empieza un número nuevo.
///
/// Toda la secuencia cuenta como **una sola** operación de deshacer, igual que un arrastre: no
/// tendría sentido que escribir "25" dejara dos entradas en el historial.
final class CounterQuickEntry {

    /// Tiempo que se siguen encadenando dígitos antes de empezar un número nuevo.
    private let groupingInterval: TimeInterval = 1.2
    private let maximumDigits = 4

    /// La pila, para que el tecleo se aplique siempre a la captura activa aunque el usuario
    /// cambie de una a otra mientras escribe.
    private weak var stack: EditorStack?
    private var buffer: String = ""
    private var targetID: UUID?
    private var timer: Timer?

    init(stack: EditorStack) {
        self.stack = stack
    }

    private var document: EditorDocument? { stack?.active }

    deinit {
        timer?.invalidate()
    }

    /// Aplica un dígito al contador seleccionado.
    /// - Returns: `true` si se ha consumido la tecla.
    @discardableResult
    func type(_ digit: Character) -> Bool {
        guard digit.isNumber,
              let document,
              let annotation = document.selectedAnnotation,
              annotation.counterNumber != nil else {
            return false
        }

        // Un contador distinto —o una pausa— empiezan un número desde cero.
        if targetID != annotation.id {
            finish()
            document.beginInteractiveChange()
            targetID = annotation.id
            buffer = ""
        }

        guard buffer.count < maximumDigits else { return true }
        buffer.append(digit)

        if let value = Int(buffer) {
            document.updateLive(annotation.withCounterNumber(value))
        }

        restartTimer()
        return true
    }

    /// Borra el último dígito escrito. Devuelve `false` si no había nada que borrar, para que
    /// la tecla siga su camino y elimine la anotación.
    @discardableResult
    func deleteLastDigit() -> Bool {
        guard !buffer.isEmpty, let document, let annotation = document.selectedAnnotation else {
            return false
        }
        buffer.removeLast()
        document.updateLive(annotation.withCounterNumber(Int(buffer) ?? 0))
        restartTimer()
        return true
    }

    /// Cierra la secuencia en curso y la registra en el historial como un solo cambio.
    func finish() {
        timer?.invalidate()
        timer = nil
        guard targetID != nil else { return }
        targetID = nil
        buffer = ""
        document?.endInteractiveChange()
    }

    /// `true` mientras se está escribiendo un número.
    var isTyping: Bool { targetID != nil }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: groupingInterval, repeats: false) { [weak self] _ in
            self?.finish()
        }
    }
}
