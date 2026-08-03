import AppKit
import SwiftUI

/// NSHostingView that can't be used to drag the window — the window moves only
/// via the explicit drag zone in the tab bar (WindowDragArea).
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
        // custom hosting view: keeps the window from hijacking drags on content,
        // otherwise dragging tabs would move the whole window
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
            // the saved shortcut was taken by another app — fall back to ⌥Space
            SettingsStore.shared.resetHotKey()
        }

        // warm up the Claude history index in the background — the popover opens instantly
        claude.refreshDiscovered()

        // favorites marked with the "pin rivet" — open them on launch
        tabs.launchAutoruns(favorites: favorites.favorites)

        // show right away on first launch
        panel.present()
    }

    /// Quit confirmation when tabs with running processes are open.
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

    // MARK: - Showing/hiding the panel

    func togglePanel() {
        if panel.isVisible && NSApp.isActive {
            hidePanel()
        } else {
            panel.present()
            // focus goes straight where it belongs: terminal tab — the terminal, home tab — the input field
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
        RecentTabsState.shared.hide()
        panel.saveFrame()
        panel.orderOut(nil)
        NSApp.hide(nil) // give focus back to the previous app
    }

    func windowDidResignKey(_ notification: Notification) {
        // like Spotlight: click outside — the window hides (unless it's pinned
        // or a system folder-picker dialog is open)
        guard !PanelBridge.shared.pinned, !PanelBridge.shared.suppressHide else { return }
        panel.orderOut(nil)
    }

    // the user moved or resized the window — remember the exact frame
    func windowDidMove(_ notification: Notification) {
        panel.saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        panel.saveFrame()
    }

    // MARK: - Menu (needed for ⌘C/⌘V/⌘Q etc.)

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

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "apple.terminal", accessibilityDescription: "FedTerm")
        }
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: toggleItemTitle, action: #selector(toggleAction), keyEquivalent: "")
        toggleMenuItem = toggleItem
        // the shortcut goes right in the title: Carbon catches the actual hotkey, and a keyEquivalent
        // in the status menu would be mere decoration we'd have to assemble from key codes
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

    // MARK: - Tab shortcuts (⌘T/⌘W/⌘1-9/⌘[/⌘])

    private func setupShortcuts() {
        // Match by physical keyCode, not by characters — otherwise on the Russian
        // layout Cmd+T becomes "Cmd+е" and the hotkeys stop being caught.
        let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, NSApp.isActive else { return event }
            // the "recent tabs" panel is open — keys go to it first
            if RecentTabsState.shared.visible, self.handleRecentTabsKey(event) {
                return nil
            }
            // Guaranteed Ctrl+C in the terminal: send ETX (0x03) straight to the pty,
            // bypassing the kitty protocol — canceling actions in Claude Code always works.
            if event.modifierFlags.contains(.control),
               !event.modifierFlags.contains(.command),
               event.keyCode == 8, // physical C key
               let termView = self.panel.firstResponder as? FedTermView {
                termView.send([0x03])
                return nil
            }
            // Ctrl+1…9 — automations (⌘-digits are taken by tab switching)
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
            case 14: // E — recent tabs panel (like Recent Files in WebStorm)
                RecentTabsState.shared.show(count: self.tabs.recentTabs.count)
                return nil
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

    /// Keys for the "recent tabs" panel: arrows/⌘E — move through the list,
    /// Enter — switch, Esc — close, anything else closes the panel.
    private func handleRecentTabsKey(_ event: NSEvent) -> Bool {
        let state = RecentTabsState.shared
        let recent = tabs.recentTabs
        guard !recent.isEmpty else {
            state.hide()
            return false
        }
        switch event.keyCode {
        case 53: // Esc
            state.hide()
            return true
        case 36, 76: // Enter
            let idx = min(state.selection, recent.count - 1)
            tabs.selectedID = recent[idx].id
            state.hide()
            return true
        case 125: // ↓
            state.moveSelection(by: 1, count: recent.count)
            return true
        case 126: // ↑
            state.moveSelection(by: -1, count: recent.count)
            return true
        case 14 where event.modifierFlags.contains(.command): // ⌘E moves further down the list
            state.moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1, count: recent.count)
            return true
        default:
            // any other key — the panel isn't modal, just hide it
            state.hide()
            return false
        }
    }
}
