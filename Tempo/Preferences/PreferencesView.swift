import AppKit
import SwiftUI

/// Pestañas de la ventana de ajustes.
enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Atajos"
        case .about: return "Acerca de"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesView: View {

    @ObservedObject var preferences: Preferences
    @Binding var selection: PreferencesTab

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(preferences: preferences)
                .tabItem { Label(PreferencesTab.general.title, systemImage: PreferencesTab.general.symbolName) }
                .tag(PreferencesTab.general)

            ShortcutSettingsView(preferences: preferences)
                .tabItem { Label(PreferencesTab.shortcuts.title, systemImage: PreferencesTab.shortcuts.symbolName) }
                .tag(PreferencesTab.shortcuts)

            AboutView()
                .tabItem { Label(PreferencesTab.about.title, systemImage: PreferencesTab.about.symbolName) }
                .tag(PreferencesTab.about)
        }
        .frame(width: 460)
        .padding(20)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {

    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Al pulsar Guardar")
                    .font(.system(size: 12, weight: .semibold))

                Picker("", selection: $preferences.saveMode) {
                    ForEach(Preferences.SaveMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(preferences.saveMode.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Carpeta de las capturas")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(displayPath)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(preferences.saveFolder.path)
                    Spacer()
                    Button("Elegir…", action: chooseFolder)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.05))
                )

                if !preferences.saveFolderExists {
                    Label("La carpeta ya no existe. Elige otra o se usará el escritorio.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                Text(preferences.saveMode == .direct
                     ? "Las capturas se guardarán aquí sin preguntar."
                     : "Se usará como carpeta inicial del panel de guardar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 240, alignment: .top)
    }

    private var displayPath: String {
        let path = preferences.saveFolder.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.saveFolderExists ? preferences.saveFolder : Preferences.defaultSaveFolder
        panel.prompt = "Elegir"
        panel.message = "Elige dónde se guardarán las capturas"

        if panel.runModal() == .OK, let url = panel.url {
            preferences.saveFolder = url
        }
    }
}

// MARK: - Atajos

private struct ShortcutSettingsView: View {

    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Atajos globales")
                    .font(.system(size: 12, weight: .semibold))

                row(title: HotKeyManager.Action.captureFullScreen.title,
                    shortcut: $preferences.fullScreenShortcut,
                    fallback: .defaultFullScreen,
                    other: preferences.regionShortcut)

                row(title: HotKeyManager.Action.captureRegion.title,
                    shortcut: $preferences.regionShortcut,
                    fallback: .defaultRegion,
                    other: preferences.fullScreenShortcut)

                Text("Haz clic en un atajo y pulsa la combinación que quieras. Esc cancela y ⌫ restablece el original. Los atajos funcionan con cualquier aplicación en primer plano.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Restablecer atajos") { preferences.resetShortcuts() }
                        .controlSize(.small)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Atajos del editor")
                    .font(.system(size: 12, weight: .semibold))
                Text("Son fijos y se muestran en la propia barra de herramientas, junto al botón «?».")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                EditorShortcutsGrid()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 240, alignment: .top)
    }

    private func row(title: String,
                     shortcut: Binding<GlobalShortcut>,
                     fallback: GlobalShortcut,
                     other: GlobalShortcut) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            ShortcutRecorder(shortcut: shortcut, fallback: fallback) { candidate in
                // Los dos atajos globales no pueden coincidir.
                candidate != other
            }
            .frame(width: 160, height: 26)
        }
    }
}

private struct EditorShortcutsGrid: View {
    private let columns = [GridItem(.flexible(), alignment: .leading),
                           GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(EditorTool.allCases) { tool in
                HStack(spacing: 6) {
                    Text(tool.shortcutKey.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .frame(minWidth: 16)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                    Text(tool.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Acerca de

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 3) {
                Text(Preferences.appName)
                    .font(.system(size: 20, weight: .semibold))
                Text("Versión \(Preferences.appVersion) (\(Preferences.buildNumber))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("Captura, anota y arrastra a donde quieras.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 6) {
                Label("Todo ocurre en local: sin cuentas, sin nube y sin telemetría.",
                      systemImage: "lock.fill")
                Label("Necesita el permiso de Grabación de pantalla de macOS.",
                      systemImage: "checkmark.shield")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Button("Abrir ajustes de privacidad de macOS") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 240, alignment: .top)
        .padding(.top, 8)
    }
}
