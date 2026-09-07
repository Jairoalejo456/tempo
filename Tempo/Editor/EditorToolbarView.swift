import SwiftUI

/// Barra de herramientas del editor: compacta, discreta y con los atajos siempre a la vista.
struct EditorToolbarView: View {

    @ObservedObject var document: EditorDocument

    var onUndo: () -> Void
    var onRedo: () -> Void
    var onCopy: () -> Void
    var onSave: () -> Void
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onZoomToFit: () -> Void

    @State private var showsShortcuts = false

    var body: some View {
        HStack(spacing: 10) {
            toolGroup
            divider
            colorGroup
            divider
            widthGroup
            divider
            historyGroup
            divider
            zoomGroup

            Spacer(minLength: 12)

            actionGroup
            helpButton
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Grupos

    private var toolGroup: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                ToolButton(
                    symbol: tool.symbolName,
                    shortcut: tool.shortcutKey.uppercased(),
                    isSelected: document.tool == tool,
                    help: helpText(for: tool)
                ) {
                    document.tool = tool
                }
                // El puntero se separa del resto: no dibuja, navega.
                if tool == .navigate {
                    divider.padding(.horizontal, 3)
                }
            }
        }
    }

    private func helpText(for tool: EditorTool) -> String {
        let key = tool.shortcutKey.uppercased()
        switch tool {
        case .navigate:
            return "Puntero · \(key) — arrastra para mover, rueda para acercar o alejar"
        case .annotate:
            return "\(tool.title) · \(key)"
        }
    }

    /// Control de zoom: porcentaje actual y botones para acercar, alejar y ajustar.
    private var zoomGroup: some View {
        HStack(spacing: 2) {
            ToolButton(symbol: "minus.magnifyingglass", shortcut: nil, isSelected: false,
                       help: "Alejar · ⌘−", action: onZoomOut)

            Button(action: onZoomToFit) {
                Text(zoomLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 42, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ajustar a la ventana · ⌘0")

            ToolButton(symbol: "plus.magnifyingglass", shortcut: nil, isSelected: false,
                       help: "Acercar · ⌘+", action: onZoomIn)
        }
    }

    private var zoomLabel: String {
        let percentage = Int((document.effectiveZoom * 100).rounded())
        return "\(max(percentage, 1)) %"
    }

    private var colorGroup: some View {
        HStack(spacing: 5) {
            ForEach(Array(AnnotationColor.palette.enumerated()), id: \.offset) { index, color in
                Button {
                    document.color = color
                } label: {
                    Circle()
                        .fill(Color(color))
                        .frame(width: 15, height: 15)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .padding(-3)
                                .opacity(document.color == color ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .help("Color \(index + 1)")
            }
        }
        .opacity(document.tool.usesColor ? 1 : 0.35)
        .disabled(!document.tool.usesColor)
    }

    private var widthGroup: some View {
        HStack(spacing: 2) {
            ForEach(LineWeight.allCases) { weight in
                Button {
                    document.lineWidth = weight.lineWidth
                    document.fontSize = weight.fontSize
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: weight.dotSize, height: weight.dotSize)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected(weight) ? Color.primary.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Grosor \(weight.title)")
            }
        }
    }

    private var historyGroup: some View {
        HStack(spacing: 2) {
            ToolButton(symbol: "arrow.uturn.backward", shortcut: nil, isSelected: false, help: "Deshacer · ⌘Z", action: onUndo)
                .disabled(!document.canUndo)
                .opacity(document.canUndo ? 1 : 0.35)
            ToolButton(symbol: "arrow.uturn.forward", shortcut: nil, isSelected: false, help: "Rehacer · ⇧⌘Z", action: onRedo)
                .disabled(!document.canRedo)
                .opacity(document.canRedo ? 1 : 0.35)
        }
    }

    private var actionGroup: some View {
        HStack(spacing: 8) {
            ActionButton(symbol: "doc.on.doc", title: "Copiar", shortcut: "⌘C",
                         help: "Copiar la imagen con anotaciones · ⌘C", action: onCopy)
            ActionButton(symbol: "square.and.arrow.down", title: "Guardar", shortcut: "⌘S",
                         help: "Guardar como PNG · ⌘S", action: onSave)
        }
    }

    private var helpButton: some View {
        Button {
            showsShortcuts.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .help("Atajos de teclado")
        .popover(isPresented: $showsShortcuts, arrowEdge: .bottom) {
            ShortcutsCheatSheet()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
    }

    private func isSelected(_ weight: LineWeight) -> Bool {
        abs(document.lineWidth - weight.lineWidth) < 0.01
    }
}

// MARK: - Piezas

private struct ToolButton: View {
    let symbol: String
    let shortcut: String?
    let isSelected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                    .frame(width: 30, height: 30)

                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.8))
                    .frame(width: 30, height: 30)

                // La tecla del atajo se muestra siempre, en pequeño, para poder aprenderla.
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.75))
                        .padding(.trailing, 1)
                        .padding(.bottom, 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Botón de salida: icono, texto y atajo siempre visibles, para que se aprenda sin buscarlo.
private struct ActionButton: View {
    let symbol: String
    let title: String
    let shortcut: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12))
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .fixedSize()
    }
}

enum LineWeight: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "fino"
        case .medium: return "medio"
        case .large: return "grueso"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .small: return 2.5
        case .medium: return 4
        case .large: return 7
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: return 20
        case .medium: return 28
        case .large: return 40
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .small: return 5
        case .medium: return 8
        case .large: return 12
        }
    }
}

/// Lista completa de atajos, accesible desde el botón "?" de la barra.
struct ShortcutsCheatSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Herramientas", rows: EditorTool.allCases.map { ($0.title, $0.shortcutKey.uppercased()) })
            section("Edición", rows: [
                ("Deshacer", "⌘Z"),
                ("Rehacer", "⇧⌘Z"),
                ("Borrar la última anotación", "⌫"),
                ("Colores", "1 – 8"),
                ("Grosor", "[  /  ]")
            ])
            section("Vista", rows: [
                ("Acercar / Alejar", "⌘+  /  ⌘−"),
                ("Ajustar a la ventana", "⌘0"),
                ("Tamaño real", "⌘1"),
                ("Con el puntero: mover", "arrastrar"),
                ("Con el puntero: zoom", "rueda")
            ])
            section("Salida", rows: [
                ("Copiar con anotaciones", "⌘C"),
                ("Guardar como PNG", "⌘S"),
                ("Volver a la miniatura", "⌘W  /  Esc"),
                ("Descartar la captura", "⇧⌘⌫")
            ])
            section("Captura global", rows: [
                ("Pantalla completa", Preferences.shared.fullScreenShortcut.display),
                ("Región", Preferences.shared.regionShortcut.display)
            ])
        }
        .padding(16)
        .frame(width: 300)
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .font(.system(size: 12))
                    Spacer(minLength: 16)
                    Text(row.1)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.07))
                        )
                }
            }
        }
    }
}

extension Color {
    init(_ annotationColor: AnnotationColor) {
        self.init(.sRGB,
                  red: annotationColor.red,
                  green: annotationColor.green,
                  blue: annotationColor.blue,
                  opacity: annotationColor.alpha)
    }
}
