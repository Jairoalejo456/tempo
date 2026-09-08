import SwiftUI

/// Medidas compartidas entre la barra de herramientas (SwiftUI) y la ventana (AppKit), para que
/// no puedan desincronizarse: si la altura declarada aquí fuese menor que la que el contenido
/// necesita, los controles se recortarían.
enum EditorMetrics {
    /// Alto de la barra de herramientas.
    static let toolbarHeight: CGFloat = 54
    /// Alto de un botón de herramienta, incluida la letra de su atajo.
    static let toolButtonHeight: CGFloat = 38
    static let toolButtonWidth: CGFloat = 32
}

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

    /// Cuánto espacio se permite ocupar a la barra. Cuando la ventana es estrecha —o cuando
    /// aparecen los controles de la selección— se va recortando lo accesorio antes que
    /// esconder ningún control.
    private enum Density {
        /// Todo con su etiqueta y los botones de zoom.
        case comfortable
        /// Sin los botones de zoom: quedan sus atajos y el porcentaje, que también ajusta.
        case compact
        /// Copiar y Guardar sólo con su icono.
        case minimal
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(density: .comfortable)
            content(density: .compact)
            content(density: .minimal)
        }
        .frame(height: EditorMetrics.toolbarHeight)
        // Fondo sólido en lugar de un material translúcido: la vibrancia desaturaba los
        // círculos de color y hacía difícil distinguir cuál estaba elegido.
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func content(density: Density) -> some View {
        HStack(spacing: density == .comfortable ? 9 : 6) {
            toolGroup
            divider
            colorGroup
            divider
            // El blur y el lápiz tienen su propio ajuste continuo; el resto usa los tres
            // tamaños fijos, que van más rápido.
            settingGroup
            divider
            historyGroup

            if document.selectedAnnotation != nil {
                divider
                selectionGroup
            }

            divider
            zoomGroup(showsButtons: density == .comfortable)

            Spacer(minLength: 10)

            actionGroup(showsLabels: density != .minimal)
            helpButton
        }
        .padding(.horizontal, 12)
        .frame(height: EditorMetrics.toolbarHeight)
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
                // El puntero y el recorte se separan del resto: no dibujan nada.
                if tool == .navigate || tool == .crop {
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
        case .crop:
            return "Recortar · \(key) — ajusta el encuadre y confirma con ↩"
        case .annotate:
            return "\(tool.title) · \(key)"
        }
    }

    /// Control de zoom: porcentaje actual y, si hay sitio, botones para acercar y alejar.
    private func zoomGroup(showsButtons: Bool) -> some View {
        HStack(spacing: 2) {
            if showsButtons {
                ToolButton(symbol: "minus.magnifyingglass", shortcut: nil, isSelected: false,
                           help: "Alejar · ⌘−", action: onZoomOut)
            }

            Button(action: onZoomToFit) {
                Text(zoomLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 46, height: EditorMetrics.toolButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ajustar a la ventana · ⌘0. Acercar y alejar: ⌘+ / ⌘− o la rueda del ratón.")

            if showsButtons {
                ToolButton(symbol: "plus.magnifyingglass", shortcut: nil, isSelected: false,
                           help: "Acercar · ⌘+", action: onZoomIn)
            }
        }
    }

    private var zoomLabel: String {
        let percentage = Int((document.effectiveZoom * 100).rounded())
        return "\(max(percentage, 1)) %"
    }

    private var colorGroup: some View {
        HStack(spacing: 1) {
            ForEach(Array(AnnotationColor.palette.enumerated()), id: \.offset) { index, color in
                Button {
                    document.color = color
                    // Si hay algo seleccionado, el color se aplica también a ello.
                    document.applyColorToSelection()
                } label: {
                    Circle()
                        .fill(Color(color))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .padding(-3)
                                .opacity(document.color == color ? 1 : 0)
                        )
                        // Aísla los círculos de cualquier efecto de vibrancia del fondo, para
                        // que el color que se ve sea exactamente el que se va a dibujar.
                        .compositingGroup()
                        .frame(width: 20, height: EditorMetrics.toolButtonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Color \(index + 1) · tecla \(index + 1)")
            }
        }
        .opacity(document.tool.usesColor ? 1 : 0.35)
        .disabled(!document.tool.usesColor)
    }

    /// Ajuste que corresponde a la herramienta activa.
    @ViewBuilder
    private var settingGroup: some View {
        switch activeSetting {
        case .blurIntensity:
            SliderSetting(
                title: "Intensidad",
                systemImage: "drop.halffull",
                value: Binding(
                    get: { document.blurIntensity },
                    set: {
                        document.blurIntensity = $0
                        document.applyBlurIntensityToSelection()
                    }
                ),
                range: 0...1,
                help: "Fuerza del difuminado"
            )
        case .pencilWidth:
            SliderSetting(
                title: "Grosor",
                systemImage: "pencil.tip",
                value: Binding(
                    get: { document.lineWidth },
                    set: {
                        document.lineWidth = $0
                        document.applyLineWidthToSelection()
                    }
                ),
                range: EditorDocument.pencilWidthRange,
                help: "Grosor del trazo"
            )
        case .fixedWeights:
            widthGroup
        }
    }

    private enum ActiveSetting {
        case blurIntensity, pencilWidth, fixedWeights
    }

    /// La barra sigue a lo que estés tocando: primero lo seleccionado, y si no, la herramienta.
    private var activeSetting: ActiveSetting {
        let tool = document.selectedAnnotation.map { EditorTool.annotate($0.tool) } ?? document.tool
        switch tool {
        case .annotate(.blur): return .blurIntensity
        case .annotate(.pencil): return .pencilWidth
        default: return .fixedWeights
        }
    }

    private var widthGroup: some View {
        HStack(spacing: 2) {
            ForEach(LineWeight.allCases) { weight in
                Button {
                    document.lineWidth = weight.lineWidth
                    document.fontSize = weight.fontSize
                    document.applyWeightToSelection()
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: weight.dotSize, height: weight.dotSize)
                        .frame(width: 24, height: 24)
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

    /// Controles que sólo tienen sentido con una anotación seleccionada.
    @ViewBuilder
    private var selectionGroup: some View {
        HStack(spacing: 6) {
            if let selected = document.selectedAnnotation, let number = selected.counterNumber {
                // Un contador se puede renumerar a mano: no está atado al orden en que se puso.
                HStack(spacing: 3) {
                    Text("N.º")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Stepper(
                        value: Binding(
                            get: { number },
                            set: { document.setCounterNumber($0, for: selected.id) }
                        ),
                        in: 0...9999
                    ) {
                        Text("\(number)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 22)
                    }
                    .controlSize(.small)
                }
                .help("Número del contador. También puedes hacer doble clic sobre él.")
            }

            ToolButton(symbol: "trash", shortcut: nil, isSelected: false,
                       help: "Eliminar lo seleccionado · ⌫") {
                document.deleteSelected()
            }
        }
        .fixedSize()
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

    private func actionGroup(showsLabels: Bool) -> some View {
        HStack(spacing: 6) {
            ActionButton(symbol: "doc.on.doc", title: "Copiar", shortcut: "⌘C",
                         showsLabel: showsLabels,
                         help: "Copiar la imagen con anotaciones · ⌘C", action: onCopy)
            ActionButton(symbol: "square.and.arrow.down", title: "Guardar", shortcut: "⌘S",
                         showsLabel: showsLabels,
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
            .frame(width: 1, height: 26)
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
            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.85))
                    .frame(height: 18)

                // La tecla del atajo se muestra siempre, para poder aprenderla. Ocupa su propio
                // espacio en lugar de superponerse al icono.
                Text(shortcut ?? " ")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.8))
                    .frame(height: 11)
            }
            .frame(width: EditorMetrics.toolButtonWidth, height: EditorMetrics.toolButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Deslizador compacto para un ajuste continuo (intensidad del blur, grosor del lápiz).
private struct SliderSetting: View {
    let title: String
    let systemImage: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let help: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: $value, in: range)
                .controlSize(.mini)
                .frame(width: 88)
            Text(readout)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
        }
        .frame(height: EditorMetrics.toolButtonHeight)
        .help("\(help) · \(title)")
    }

    private var readout: String {
        // La intensidad se lee en porcentaje; el grosor, en puntos.
        range.upperBound <= 1
            ? "\(Int((value * 100).rounded())) %"
            : "\(Int(value.rounded())) pt"
    }
}

/// Botón de salida: icono, texto y atajo siempre visibles, para que se aprenda sin buscarlo.
private struct ActionButton: View {
    let symbol: String
    let title: String
    let shortcut: String
    var showsLabel: Bool = true
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                if showsLabel {
                    Text(title)
                        .font(.system(size: 12))
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, showsLabel ? 9 : 7)
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
