import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// Корневая вью панели: тонкий таб-бар (появляется, когда нужен) + активная вкладка.
struct ContentView: View {
    @EnvironmentObject var tabs: TabsModel
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var pins: PinsStore
    @EnvironmentObject var claude: ClaudeSessionsStore
    @ObservedObject var panelState: PanelBridge = .shared
    @ObservedObject var automationsStore: AutomationsStore = .shared
    @ObservedObject var customThemes: CustomThemesStore = .shared
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if showTabBar {
                    TabBarView()
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                }
                content
            }
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(claudeOrange, lineWidth: 2)
                    .background(claudeOrange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        Label(L.dropHint, systemImage: "sparkle")
                            .font(.system(size: 13, weight: .medium))
                            .padding(10)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    )
                    .allowsHitTesting(false)
            }
            if let folder = claude.pendingFolder {
                ClaudeNameOverlay(folder: folder)
            }
            if automationsStore.editorVisible {
                AutomationEditorOverlay()
            }
            if customThemes.editing != nil {
                ThemeEditorOverlay()
            }
        }
        .frame(minWidth: 680, minHeight: 420)
        .ignoresSafeArea(.container, edges: .top) // контент с самого верха, без зоны невидимого тайтлбара
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .onChange(of: tabs.selectedID) { _ in
            focusSelected()
        }
    }

    /// Drop папки (например, из обозревателя WebStorm) → оверлей имени → вкладка с Claude.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            }
            guard var folder = url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) else { return }
            if !isDir.boolValue { folder = folder.deletingLastPathComponent() } // кинули файл — берём его папку
            DispatchQueue.main.async { claude.pendingFolder = folder }
        }
        return true
    }

    // шапка всегда видна — в ней кнопки клода и настроек
    private var showTabBar: Bool { true }

    @ViewBuilder
    private var content: some View {
        if let tab = tabs.selectedTab {
            switch tab.kind {
            case .home:
                HomeView(tab: tab)
                    .id(tab.id) // свой стейт для каждой домашней вкладки
            case .terminal(let controller):
                TerminalHostView(controller: controller)
                    .id(tab.id) // иначе SwiftUI не подменяет NSView при переключении терминал → терминал
                    .padding(.horizontal, 3)
                    .padding(.bottom, 3)
            }
        }
    }

    private func focusSelected() {
        guard let tab = tabs.selectedTab else { return }
        if let terminal = tab.terminal {
            DispatchQueue.main.async { terminal.focus() }
        } else {
            // новая/домашняя вкладка: забрать фокус у терминала и отдать полю ввода,
            // иначе стрелки продолжают листать историю шелла
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
                PanelBridge.shared.panelShown.send()
            }
        }
    }
}

/// Тонкая полоска вкладок в стиле «стекло».
struct TabBarView: View {
    @EnvironmentObject var tabs: TabsModel
    @ObservedObject var panelState: PanelBridge = .shared
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var draggingID: UUID?
    @State private var tabsContentWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(tabs.tabs) { tab in
                        TabChip(tab: tab, isSelected: tab.id == tabs.selectedID)
                            .opacity(draggingID == tab.id ? 0.55 : 1)
                            .background(GeometryReader { geo in
                                Color.clear.preference(
                                    key: TabFramesKey.self,
                                    value: [tab.id: geo.frame(in: .named("tabbar"))]
                                )
                            })
                            .highPriorityGesture(reorderGesture(for: tab))
                    }
                }
                .coordinateSpace(name: "tabbar")
                .onPreferenceChange(TabFramesKey.self) { frames in
                    tabFrames = frames
                    tabsContentWidth = (frames.values.map(\.maxX).max() ?? 0) + 8
                }
                .animation(.easeInOut(duration: 0.15), value: tabs.tabs.map(\.id))
                .padding(.horizontal, 2)
            }
            // полоса вкладок — по ширине контента (не больше доступного);
            // когда вкладок много — внутри включается скролл.
            // layoutPriority — иначе HStack делит ширину пополам с drag-зоной
            .frame(maxWidth: max(tabsContentWidth, 60), alignment: .leading)
            .layoutPriority(1)
            Button { tabs.newTab() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L.newTabHelp)

            // пустая середина таб-бара — ручка для перетаскивания окна
            WindowDragArea()
                .frame(minWidth: 24, maxWidth: .infinity)
                .frame(height: 20)

            ClaudeMenuButton()

            Button { panelState.pinned.toggle() } label: {
                Image(systemName: panelState.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(panelState.pinned ? Color.accentColor : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(panelState.pinned ? L.pinWindowOn : L.pinWindowOff)

            SettingsButton()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

/// Зона, за которую таскается окно (пустое место таб-бара).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct TabFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension TabBarView {
    /// Ручная перестановка вкладок: без системного drag&drop — мгновенно,
    /// без «призрака» на курсоре. Своп при пересечении середины соседа.
    fileprivate func reorderGesture(for tab: Tab) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("tabbar"))
            .onChanged { value in
                draggingID = tab.id
                let x = value.location.x
                guard let myFrame = tabFrames[tab.id] else { return }
                for (otherID, frame) in tabFrames where otherID != tab.id {
                    let movingRight = frame.minX > myFrame.minX
                    // меняем местами, только когда курсор перевалил середину соседа
                    if movingRight ? (x > frame.midX && x < frame.maxX + 20)
                                   : (x < frame.midX && x > frame.minX - 20) {
                        tabs.move(id: tab.id, to: otherID)
                        break
                    }
                }
            }
            .onEnded { _ in draggingID = nil }
    }
}

private struct TabChip: View {
    @ObservedObject var tab: Tab
    let isSelected: Bool
    @EnvironmentObject var tabs: TabsModel
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .primary : .tertiary)
            if editing {
                TextField(L.tabName, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(width: 140)
                    .focused($editFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Button { tabs.close(tab) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering && !editing ? 1 : 0)
            .frame(width: 13)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.14) : (hovering ? Color.white.opacity(0.06) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startRename() }
        .simultaneousGesture(TapGesture().onEnded {
            // не трогаем выделение, если вкладку только что закрыли крестиком
            guard tabs.tabs.contains(where: { $0.id == tab.id }) else { return }
            tabs.selectedID = tab.id
        })
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L.rename) { startRename() }
            if tab.customTitle != nil {
                Button(L.resetName) {
                    tab.customTitle = nil
                    tabs.persist()
                }
            }
            Divider()
            Button(L.closeTab) { tabs.close(tab) }
        }
    }

    private func startRename() {
        draft = tab.customTitle ?? tab.title
        editing = true
        PanelBridge.shared.editingText = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitRename() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        tab.customTitle = name.isEmpty ? nil : name
        editing = false
        PanelBridge.shared.editingText = false
        tabs.persist()
    }

    private func cancelRename() {
        editing = false
        PanelBridge.shared.editingText = false
    }
}

/// Мост между SwiftUI и панелью (скрыть/закрепить) — чтобы вью не знали про AppKit-окно.
final class PanelBridge: ObservableObject {
    static let shared = PanelBridge()
    @Published var pinned = false
    /// Срабатывает при каждом показе панели — домашняя вкладка ставит фокус в поле ввода.
    let panelShown = PassthroughSubject<Void, Never>()
    /// true, пока где-то идёт инлайн-переименование — спотлайт-навигация не трогает клавиши.
    var editingText = false
    /// true, пока открыт системный диалог (выбор папки) — панель не должна прятаться.
    var suppressHide = false
    var hideAction: (() -> Void)?
    var showAction: (() -> Void)?

    func hide() { hideAction?() }
    func show() { showAction?() }
}
