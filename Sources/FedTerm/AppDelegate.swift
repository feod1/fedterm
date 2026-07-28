import AppKit
import SwiftUI

/// NSHostingView, по которому нельзя таскать окно — окно двигается только
/// за явную drag-зону в таб-баре (WindowDragArea).
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: SpotlightPanel!
    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem?
    private let hotkey = HotkeyManager.shared
    private var keyMonitor: Any?

    private let history = HistoryStore()
    private let pins = PinsStore()
    private let claude = ClaudeSessionsStore()
    private let favorites = FavoritesStore()
    private var tabs: TabsModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ShellIntegration.ensureInstalled()

        tabs = TabsModel(history: history, claude: claude)

        let root = ContentView()
            .environmentObject(tabs)
            .environmentObject(history)
            .environmentObject(pins)
            .environmentObject(claude)
            .environmentObject(favorites)
        // свой hosting: запрещает окну перехватывать drag по контенту,
        // иначе перетаскивание вкладок таскало окно целиком
        let hosting = PanelHostingView(rootView: root)
        panel = SpotlightPanel(contentView: hosting)
        panel.delegate = self

        PanelBridge.shared.hideAction = { [weak self] in self?.hidePanel() }
        PanelBridge.shared.showAction = { [weak self] in self?.panel.present() }

        setupMenu()
        setupStatusItem()
        setupShortcuts()

        hotkey.handler = { [weak self] in self?.togglePanel() }
        if !hotkey.registerFromSettings() {
            // сохранённое сочетание отобрала другая программа — откатываемся к ⌥Space
            SettingsStore.shared.resetHotKey()
        }

        // прогреваем индекс истории клода в фоне — поповер откроется мгновенно
        claude.refreshDiscovered()

        // избранные с «заклёпкой» — открыть при запуске
        tabs.launchAutoruns(favorites: favorites.favorites)

        // сразу показываем при первом запуске
        panel.present()
    }

    /// Подтверждение выхода, если открыты вкладки с процессами.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = tabs.tabs.filter { $0.terminal != nil && $0.terminal?.terminated != true }.count
        guard running > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L.quitConfirmTitle
        alert.informativeText = L.quitConfirmText(running)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.quitButton)
        alert.addButton(withTitle: L.cancel)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        tabs.shutdown()
    }

    // MARK: - Показ/скрытие панели

    func togglePanel() {
        if panel.isVisible && NSApp.isActive {
            hidePanel()
        } else {
            panel.present()
            // фокус сразу в нужное место: терминал — в терминал, домашняя — в поле ввода
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let terminal = self.tabs.selectedTab?.terminal {
                    terminal.focus()
                } else {
                    PanelBridge.shared.panelShown.send()
                }
            }
        }
    }

    func hidePanel() {
        panel.saveFrame()
        panel.orderOut(nil)
        NSApp.hide(nil) // вернуть фокус предыдущему приложению
    }

    func windowDidResignKey(_ notification: Notification) {
        // как Spotlight: кликнул вовне — окно спряталось (если не закреплено пином
        // и не открыт системный диалог выбора папки)
        guard !PanelBridge.shared.pinned, !PanelBridge.shared.suppressHide else { return }
        panel.orderOut(nil)
    }

    // пользователь двинул или растянул окно — запоминаем точный фрейм
    func windowDidMove(_ notification: Notification) {
        panel.saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        panel.saveFrame()
    }

    // MARK: - Меню (нужно для ⌘C/⌘V/⌘Q и т.п.)

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L.hideApp, action: #selector(hidePanelAction), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L.edit)
        editMenu.addItem(withTitle: L.undo, action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func hidePanelAction() { hidePanel() }

    // MARK: - Статус-бар

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "apple.terminal", accessibilityDescription: "FedTerm")
        }
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: toggleItemTitle, action: #selector(toggleAction), keyEquivalent: "")
        toggleMenuItem = toggleItem
        // сочетание пишем прямо в заголовке: сам хоткей ловит Carbon, а keyEquivalent
        // в статус-меню был бы лишь декорацией, которую пришлось бы собирать по кодам клавиш
        NotificationCenter.default.addObserver(
            forName: SettingsStore.hotKeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.toggleMenuItem?.title = self.toggleItemTitle
        }
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleAction() { togglePanel() }

    private var toggleItemTitle: String {
        "\(L.toggleWindow)   \(SettingsStore.shared.hotKeyDisplay)"
    }

    // MARK: - Шорткаты вкладок (⌘T/⌘W/⌘1-9/⌘[/⌘])

    private func setupShortcuts() {
        // Матчим по физическим keyCode, а не по символам — иначе на русской
        // раскладке Cmd+T превращается в «Cmd+е» и хоткеи перестают ловиться.
        let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, NSApp.isActive else { return event }
            // Гарантированный Ctrl+C в терминале: шлём ETX (0x03) напрямую в pty,
            // минуя kitty-протокол — отмена действий в Claude Code работает всегда.
            if event.modifierFlags.contains(.control),
               !event.modifierFlags.contains(.command),
               event.keyCode == 8, // физическая клавиша C
               let termView = self.panel.firstResponder as? FedTermView {
                termView.send([0x03])
                return nil
            }
            // Ctrl+1…9 — автоматизации (⌘-цифры заняты переключением вкладок)
            if event.modifierFlags.contains(.control),
               !event.modifierFlags.contains(.command),
               let n = digitKeys[event.keyCode],
               let automation = AutomationsStore.shared.automation(forKey: n) {
                self.tabs.openTerminal(
                    command: AutomationsStore.shared.launchCommand(for: automation),
                    cwd: automation.expandedCwd
                )
                return nil
            }
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control) else { return event }
            switch event.keyCode {
            case 17: // T
                self.tabs.newTab()
                return nil
            case 13: // W
                self.tabs.closeSelected()
                return nil
            case let code where digitKeys[code] != nil:
                self.tabs.select(index: digitKeys[code]! - 1)
                return nil
            case 30: // ]
                self.tabs.selectNext(delta: 1)
                return nil
            case 33: // [
                self.tabs.selectNext(delta: -1)
                return nil
            case 24: // =
                SettingsStore.shared.increaseFont()
                return nil
            case 27: // -
                SettingsStore.shared.decreaseFont()
                return nil
            case 29: // 0
                SettingsStore.shared.resetFont()
                return nil
            default:
                return event
            }
        }
    }
}
