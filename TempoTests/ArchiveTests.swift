import AppKit
import XCTest
@testable import Tempo

/// Historial local de capturas: se guarda en este Mac y caduca solo.
final class ArchiveTests: XCTestCase {

    private var archive: CaptureArchive { CaptureArchive.shared }

    override func setUp() {
        super.setUp()
        archive.removeAll()
    }

    override func tearDown() {
        archive.removeAll()
        super.tearDown()
    }

    private func store(id: UUID = UUID(), daysAgo: Int = 0) throws -> UUID {
        let capture = TestSupport.makeCapture(logicalWidth: 60, logicalHeight: 40, scale: 1)
        let image = try ImageExporter.compose(capture: capture, annotations: [])
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        archive.store(image: image, id: id, date: date)
        // La escritura es asíncrona; se espera a que el archivo aparezca.
        let deadline = Date().addingTimeInterval(3)
        while archive.entries().first(where: { $0.id == id }) == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return id
    }

    // MARK: - Guardar y recuperar

    func testStoredCaptureCanBeListedAndReopened() throws {
        let id = try store()
        let entries = archive.entries()

        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, id)
        XCTAssertNotNil(archive.image(at: entry.url), "La imagen guardada se puede volver a abrir")
        XCTAssertFalse(entry.displayName.isEmpty)
    }

    func testEntriesComeNewestFirst() throws {
        _ = try store(daysAgo: 2)
        _ = try store(daysAgo: 0)
        let entries = archive.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertGreaterThan(entries[0].date, entries[1].date)
    }

    func testStoringTheSameCaptureReplacesIt() throws {
        let id = UUID()
        _ = try store(id: id)
        _ = try store(id: id)
        XCTAssertEqual(archive.entries().filter { $0.id == id }.count, 1,
                       "Al cerrar una captura anotada se reemplaza su versión anterior")
    }

    // MARK: - Caducidad

    func testOldCapturesAreRemoved() throws {
        Preferences.shared.historyDays = 7
        _ = try store(daysAgo: 30)
        _ = try store(daysAgo: 1)

        archive.pruneOldEntries()

        let entries = archive.entries()
        XCTAssertEqual(entries.count, 1, "Lo que pasa del plazo se borra solo")
        XCTAssertLessThan(Date().timeIntervalSince(entries[0].date), 60 * 60 * 24 * 2)
    }

    func testHistoryCanBeEmptied() throws {
        _ = try store()
        _ = try store()
        XCTAssertEqual(archive.entries().count, 2)

        archive.removeAll()
        XCTAssertTrue(archive.entries().isEmpty)
        XCTAssertEqual(archive.totalSize(), 0)
    }

    func testSizeIsReported() throws {
        _ = try store()
        XCTAssertGreaterThan(archive.totalSize(), 0)
    }

    // MARK: - Se puede desactivar

    func testNothingIsStoredWhenHistoryIsOff() throws {
        Preferences.shared.keepsHistory = false
        defer { Preferences.shared.keepsHistory = true }

        let capture = TestSupport.makeCapture(logicalWidth: 40, logicalHeight: 30, scale: 1)
        let image = try ImageExporter.compose(capture: capture, annotations: [])
        archive.store(image: image, id: UUID(), date: Date())

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertTrue(archive.entries().isEmpty,
                      "Con el historial desactivado no se escribe nada en disco")
    }

    // MARK: - Dónde vive

    func testArchiveLivesInApplicationSupport() {
        let path = archive.folder.path
        XCTAssertTrue(path.contains("Application Support"), "Obtenido: \(path)")
        XCTAssertTrue(path.contains("Tempo"))
    }

    func testPreferenceDefaults() {
        XCTAssertTrue(Preferences.historyDayOptions.contains(7))
        XCTAssertEqual(Preferences.historyDayOptions.min(), 1)
    }
}
