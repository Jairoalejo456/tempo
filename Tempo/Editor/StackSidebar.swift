import AppKit
import SwiftUI

/// Tira lateral con una miniatura por captura, para elegir sobre cuál se trabaja.
///
/// Sólo se edita una captura a la vez —la que ocupa el lienzo—; esta tira dice cuáles hay y
/// permite saltar entre ellas sin perder lo anotado en ninguna.
struct StackSidebar: View {

    @ObservedObject var stack: EditorStack
    let onSelect: (UUID) -> Void

    /// Miniaturas ya compuestas, para no rehacerlas en cada repintado.
    @State private var previews: [UUID: NSImage] = [:]

    static let width: CGFloat = 104

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(Array(stack.documents.enumerated()), id: \.element.id) { index, document in
                    thumbnail(for: document, position: index + 1)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .underPageBackgroundColor))
        // El separador va del lado del lienzo, que ahora queda a la izquierda.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)
        }
        .onAppear(perform: refreshPreviews)
        // Al cambiar de captura se rehacen las miniaturas: la que se deja puede haberse
        // anotado o recortado mientras estaba activa.
        .onChange(of: stack.activeID) { _, _ in refreshPreviews() }
        .onChange(of: stack.documents.count) { _, _ in refreshPreviews() }
    }

    private func thumbnail(for document: EditorDocument, position: Int) -> some View {
        let isActive = document.id == stack.activeID

        return Button {
            onSelect(document.id)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)

                    if let image = previews[document.id] {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(0.18),
                                      lineWidth: isActive ? 2.5 : 1)
                )

                Text("\(position)")
                    .font(.system(size: 10, weight: isActive ? .bold : .regular, design: .rounded))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Captura \(position) de \(stack.count)")
    }

    private func refreshPreviews() {
        for document in stack.documents {
            guard let composed = try? ImageExporter.compose(document: document) else { continue }
            previews[document.id] = NSImage(cgImage: composed, size: document.capture.logicalSize)
        }
        // Se descartan las de capturas que ya no están.
        let alive = Set(stack.documents.map(\.id))
        previews = previews.filter { alive.contains($0.key) }
    }
}
