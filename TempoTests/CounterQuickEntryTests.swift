import XCTest
@testable import Tempo

/// Renumerar un contador tecleando: sin cuadro de texto y sin confirmar.
final class CounterQuickEntryTests: XCTestCase {

    private var document: EditorDocument!
    private var stack: EditorStack!
    private var entry: CounterQuickEntry!

    override func setUp() {
        super.setUp()
        document = EditorDocument(capture: TestSupport.makeCapture())
        // El tecleo actúa sobre la captura activa de la pila, aunque aquí sólo haya una.
        stack = EditorStack(documents: [document])
        entry = CounterQuickEntry(stack: stack)
    }

    override func tearDown() {
        entry = nil
        stack = nil
        document = nil
        super.tearDown()
    }

    @discardableResult
    private func addCounter(number: Int = 1) -> Annotation {
        let counter = Annotation(shape: .counter(center: CGPoint(x: 50, y: 50), number: number),
                                 style: .default)
        document.add(counter)
        return counter
    }

    private var currentNumber: Int? {
        document.annotations.last?.counterNumber
    }

    // MARK: - Cambio inmediato

    func testTypingADigitChangesTheNumberAtOnce() {
        addCounter(number: 3)
        XCTAssertTrue(entry.type("8"))
        XCTAssertEqual(currentNumber, 8, "El número cambia al teclearlo, sin confirmar nada")
    }

    func testConsecutiveDigitsComposeTheNumber() {
        addCounter(number: 1)
        entry.type("2")
        XCTAssertEqual(currentNumber, 2)
        entry.type("5")
        XCTAssertEqual(currentNumber, 25, "Dos dígitos seguidos forman el número 25")
    }

    func testAPauseStartsANewNumber() {
        addCounter(number: 1)
        entry.type("4")
        XCTAssertEqual(currentNumber, 4)

        // `finish` es lo que hace la pausa: cierra la secuencia.
        entry.finish()

        entry.type("7")
        XCTAssertEqual(currentNumber, 7, "Tras la pausa, el dígito empieza un número nuevo")
    }

    func testNumberIsCappedToFourDigits() {
        addCounter()
        for digit in "123456" {
            entry.type(digit)
        }
        XCTAssertEqual(currentNumber, 1234, "No se admiten números absurdamente largos")
    }

    func testZeroIsAllowed() {
        addCounter(number: 5)
        entry.type("0")
        XCTAssertEqual(currentNumber, 0)
    }

    // MARK: - Corregir

    func testBackspaceRemovesTheLastDigit() {
        addCounter(number: 1)
        entry.type("4")
        entry.type("2")
        XCTAssertEqual(currentNumber, 42)

        XCTAssertTrue(entry.deleteLastDigit())
        XCTAssertEqual(currentNumber, 4)
    }

    func testBackspaceIsIgnoredWhenNotTyping() {
        addCounter(number: 1)
        XCTAssertFalse(entry.deleteLastDigit(),
                       "Sin nada tecleado, ⌫ debe seguir su camino y borrar la anotación")
    }

    // MARK: - Historial

    func testWholeSequenceIsOneUndoStep() {
        let counter = addCounter(number: 1)
        _ = counter

        entry.type("2")
        entry.type("5")
        entry.finish()

        document.undo()
        XCTAssertEqual(currentNumber, 1, "Escribir 25 deja una sola entrada en el historial")
    }

    func testTypingOnAnotherCounterClosesThePreviousSequence() {
        let first = addCounter(number: 1)
        let second = Annotation(shape: .counter(center: CGPoint(x: 120, y: 50), number: 2), style: .default)
        document.add(second)

        // El segundo está seleccionado por ser el último añadido.
        entry.type("9")
        XCTAssertEqual(document.annotations.last?.counterNumber, 9)

        document.select(first.id)
        entry.type("7")
        XCTAssertEqual(document.annotations.first?.counterNumber, 7)
        XCTAssertEqual(document.annotations.last?.counterNumber, 9, "El primero no se toca")

        entry.finish()
        document.undo()
        XCTAssertEqual(document.annotations.first?.counterNumber, 1)
        XCTAssertEqual(document.annotations.last?.counterNumber, 9,
                       "Cada contador tiene su propia entrada en el historial")
    }

    // MARK: - Cuándo no aplica

    func testDoesNothingWithoutASelectedCounter() {
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)),
                                style: .default))
        XCTAssertFalse(entry.type("5"), "Sobre un rectángulo, el dígito sigue siendo el atajo de color")
    }

    func testDoesNothingWithoutSelection() {
        addCounter()
        document.select(nil)
        XCTAssertFalse(entry.type("5"))
    }

    func testIgnoresNonDigits() {
        addCounter()
        XCTAssertFalse(entry.type("a"))
    }

    func testIsTypingReflectsState() {
        addCounter()
        XCTAssertFalse(entry.isTyping)
        entry.type("3")
        XCTAssertTrue(entry.isTyping)
        entry.finish()
        XCTAssertFalse(entry.isTyping)
    }

    // MARK: - Numeración automática después

    func testAutomaticNumberingContinuesFromTheHighest() {
        addCounter(number: 1)
        addCounter(number: 2)
        entry.type("8")
        entry.finish()

        XCTAssertEqual(currentNumber, 8)
        XCTAssertEqual(document.nextCounterNumber, 9,
                       "El siguiente contador continúa desde el mayor que exista")
    }
}
