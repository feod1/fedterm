import SwiftUI
import UniformTypeIdentifiers

/// Оверлей-конструктор автоматизации: текстарея под bash-скрипт, скрипт из файла,
/// папка запуска, хоткей. Живёт поверх главного окна — системные диалоги его не закрывают.
struct AutomationEditorOverlay: View {
    @ObservedObject private var automations = AutomationsStore.shared

    @State private var command = ""
    @State private var cwd = "~"
    @State private var key: Int = 1
    @State private var wasPinned = false
    @FocusState private var commandFocused: Bool

    private let accent = Color(red: 0.36, green: 0.66, blue: 0.95)

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").foregroundStyle(.orange)
                    Text(L.addAutomation)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { pickScriptFile() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 10))
                            Text(L.scriptFromFile).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }

                // текстарея скрипта
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $command)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 160)
                        .focused($commandFocused)
                    if command.isEmpty {
                        Text(L.automationPlaceholder)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )

                // папка запуска
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField(L.workingDir, text: $cwd)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                    Button { pickCwd() } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L.workingDir)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))

                HStack(spacing: 10) {
                    Text(L.hotkeyLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $key) {
                        ForEach(automations.freeKeys, id: \.self) { k in
                            Text("⌃\(k)").tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 70)
                    Spacer()
                    Button(L.cancel) { close() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    Button { add() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 12))
                            Text(L.add).font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: canAdd
                                        ? [accent, Color(red: 0.22, green: 0.47, blue: 0.87)]
                                        : [Color.white.opacity(0.12), Color.white.opacity(0.10)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        )
                        .foregroundStyle(canAdd ? Color.white : Color.white.opacity(0.4))
                        .shadow(color: canAdd ? accent.opacity(0.35) : .clear, radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                }

                Text(L.automationHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: NSColor(hex: 0x24282E)))
                    .shadow(radius: 30)
            )
        }
        .onAppear {
            key = automations.freeKeys.first ?? 1
            PanelBridge.shared.editingText = true
            // на время конструктора окно закреплено — не спрячется при потере фокуса
            wasPinned = PanelBridge.shared.pinned
            PanelBridge.shared.pinned = true
            DispatchQueue.main.async { commandFocused = true }
        }
        .onDisappear {
            PanelBridge.shared.editingText = false
            PanelBridge.shared.pinned = wasPinned
        }
    }

    private var canAdd: Bool {
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !automations.freeKeys.isEmpty
    }

    private func add() {
        automations.add(command: command, key: key, cwd: cwd)
        close()
    }

    private func close() {
        automations.editorVisible = false
    }

    /// Подгрузить скрипт из файла: текст — в редактор (можно править),
    /// бинарь/огромный файл — ссылкой bash '<путь>'.
    private func pickScriptFile() {
        PanelBridge.shared.suppressHide = true
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = L.choose
        NSApp.activate(ignoringOtherApps: true)
        let result = openPanel.runModal()
        PanelBridge.shared.suppressHide = false
        PanelBridge.shared.show()
        guard result == .OK, let url = openPanel.url else { return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int) ?? 0
        if size < 100_000, let text = try? String(contentsOf: url, encoding: .utf8) {
            command = text
        } else {
            command = "bash '\(url.path)'"
        }
        cwd = url.deletingLastPathComponent().path
    }

    private func pickCwd() {
        PanelBridge.shared.suppressHide = true
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = L.choose
        if !cwd.isEmpty {
            openPanel.directoryURL = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath)
        }
        NSApp.activate(ignoringOtherApps: true)
        let result = openPanel.runModal()
        PanelBridge.shared.suppressHide = false
        PanelBridge.shared.show()
        if result == .OK, let url = openPanel.url {
            cwd = url.path
        }
    }
}
