import AppKit
import Foundation

/// Guarda las últimas capturas en el disco de este Mac, para poder recuperarlas si se descartan
/// por error.
///
/// Todo queda dentro de la carpeta de soporte de la aplicación: no hay nube, ni sincronización,
/// ni nada que salga del equipo. Los archivos se borran solos pasados los días configurados.
final class CaptureArchive {

    static let shared = CaptureArchive()

    /// Una captura guardada.
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let url: URL
        let date: Date

        var displayName: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_ES")
            formatter.dateFormat = "d MMM · HH:mm:ss"
            return formatter.string(from: date)
        }
    }

    /// Cuántas capturas se conservan como mucho, además del límite por días.
    static let maximumEntries = 30

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.jairo.tempo.archive", qos: .utility)

    private init() {}

    /// Carpeta del historial, dentro del soporte de la aplicación.
    var folder: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let url = base.appendingPathComponent("Tempo/Historial", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Guardar

    /// Archiva una captura. Si ya había una guardada con ese identificador, la reemplaza, de
    /// modo que al cerrar una sesión anotada se conserva la versión con sus anotaciones.
    func store(image: CGImage, id: UUID, date: Date) {
        guard Preferences.shared.keepsHistory else { return }
        let folder = self.folder
        queue.async { [weak self] in
            guard let self else { return }
            let url = folder.appendingPathComponent("\(Self.fileNameFormatter.string(from: date))_\(id.uuidString).png")
            // Se retira cualquier versión anterior de la misma captura.
            for existing in self.rawEntries() where existing.id == id && existing.url != url {
                try? self.fileManager.removeItem(at: existing.url)
            }
            if let data = try? ImageExporter.pngData(from: image) {
                try? data.write(to: url, options: .atomic)
            }
            self.pruneOldEntries()
        }
    }

    // MARK: - Leer

    /// Capturas guardadas, de la más reciente a la más antigua.
    func entries() -> [Entry] {
        rawEntries().sorted { $0.date > $1.date }
    }

    private func rawEntries() -> [Entry] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }

        return contents.compactMap { url -> Entry? in
            guard url.pathExtension.lowercased() == "png" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "_", maxSplits: 1)
            guard parts.count == 2,
                  let date = Self.fileNameFormatter.date(from: String(parts[0])),
                  let id = UUID(uuidString: String(parts[1])) else { return nil }
            return Entry(id: id, url: url, date: date)
        }
    }

    func image(at url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }

    // MARK: - Limpiar

    /// Borra lo que haya caducado y lo que sobre del límite de entradas.
    func pruneOldEntries() {
        let days = Preferences.shared.historyDays
        let deadline = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        var kept: [Entry] = []

        for entry in entries() {
            if entry.date < deadline || kept.count >= Self.maximumEntries {
                try? fileManager.removeItem(at: entry.url)
            } else {
                kept.append(entry)
            }
        }
    }

    /// Vacía el historial por completo.
    func removeAll() {
        for entry in entries() {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    /// Espacio que ocupa el historial, en bytes.
    func totalSize() -> Int {
        entries().reduce(0) { total, entry in
            let size = (try? fileManager.attributesOfItem(atPath: entry.url.path)[.size] as? Int) ?? 0
            return total + (size ?? 0)
        }
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter
    }()
}
