import SwiftUI
import AppKit

/// Custom theme editor overlay: name, base colors, 16 ANSI, opacity.
/// Lives on top of the window; the window is pinned while editing.
struct ThemeEditorOverlay: View {
    @ObservedObject private var store = CustomThemesStore.shared

    @State private var themeID = ""
    @State private var name = ""
    @State private var bg: UInt32 = 0
    @State private var fg: UInt32 = 0
    @State private var caret: UInt32 = 0
    @State private var selection: UInt32 = 0
    @State private var alpha: Double = 0.88
    @State private var ansi: [UInt32] = Array(repeating: 0, count: 16)
    @State private var wasPinned = false
    @State private var loaded = false

    private let ansiNames = ["blk", "red", "grn", "yel", "blu", "mag", "cyn", "wht"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette.fill").foregroundStyle(.orange)
                    Text(L.themeEditorTitle).font(.system(size: 14, weight: .semibold))
                    Spacer()
                }

                TextField(L.themeName, text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))

                Text(L.baseColors)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 14) {
                    colorCell(L.colorBg, $bg)
                    colorCell(L.colorFg, $fg)
                    colorCell(L.colorCaret, $caret)
                    colorCell(L.colorSelection, $selection)
                    Spacer()
                }

                Text(L.ansiColorsLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        ForEach(0..<8, id: \.self) { i in
                            colorCell(ansiNames[i], ansiBinding(i))
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(8..<16, id: \.self) { i in
                            colorCell(ansiNames[i - 8], ansiBinding(i))
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(L.terminalAlpha)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $alpha, in: 0.3...1.0)
                        .controlSize(.small)
                    Text("\(Int(alpha * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 34)
                }

                // live preview
                HStack(spacing: 2) {
                    ForEach(0..<16, id: \.self) { i in
                        Text("A")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(nsColor: NSColor(hex: ansi[i])))
                    }
                    Text("  ls -la ▍")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: NSColor(hex: fg)))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: NSColor(hex: bg))))

                HStack(spacing: 10) {
                    Spacer()
                    Button(L.cancel) { close() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    Button { saveTheme() } label: {
                        Text(L.save)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.36, green: 0.66, blue: 0.95), Color(red: 0.22, green: 0.47, blue: 0.87)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: NSColor(hex: 0x24282E)))
                    .shadow(radius: 30)
            )
        }
        .onAppear {
            loadDraft()
            PanelBridge.shared.editingText = true
            wasPinned = PanelBridge.shared.pinned
            PanelBridge.shared.pinned = true
        }
        .onDisappear {
            PanelBridge.shared.editingText = false
            PanelBridge.shared.pinned = wasPinned
        }
    }

    private func colorCell(_ title: String, _ value: Binding<UInt32>) -> some View {
        VStack(spacing: 3) {
            ColorPicker("", selection: colorBinding(value), supportsOpacity: false)
                .labelsHidden()
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }

    private func ansiBinding(_ index: Int) -> Binding<UInt32> {
        Binding(get: { ansi[index] }, set: { ansi[index] = $0 })
    }

    private func colorBinding(_ value: Binding<UInt32>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: value.wrappedValue)) },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
                let r = UInt32((ns.redComponent * 255).rounded())
                let g = UInt32((ns.greenComponent * 255).rounded())
                let b = UInt32((ns.blueComponent * 255).rounded())
                value.wrappedValue = (r << 16) | (g << 8) | b
            }
        )
    }

    private func loadDraft() {
        guard !loaded, let draft = store.editing else { return }
        loaded = true
        themeID = draft.id
        name = draft.name
        bg = draft.bg
        fg = draft.fg
        caret = draft.caret
        selection = draft.selection
        alpha = Double(draft.bgAlpha)
        ansi = draft.ansi.count == 16 ? draft.ansi : Array(repeating: 0, count: 16)
    }

    private func saveTheme() {
        let theme = TerminalTheme(
            id: themeID, name: name.isEmpty ? "Custom" : name,
            bg: bg, fg: fg, caret: caret, selection: selection,
            bgAlpha: CGFloat(alpha), ansi: ansi
        )
        store.upsert(theme)
        SettingsStore.shared.themeID = theme.id
        close()
    }

    private func close() {
        store.editing = nil
    }
}
