import AppKit
import SwiftUI

/// Плавающая панель в стиле Spotlight: блюр, скругления, без тайтлбара,
/// всплывает на любом рабочем столе, прячется при потере фокуса (если не закреплена).
final class SpotlightPanel: NSPanel {
    init(contentView: NSView) {
        // borderless: у titled-окна невидимый тайтлбар перехватывал drag
        // в зоне таб-бара (перетаскивание вкладок таскало окно целиком)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false // окно таскается только за drag-зону таб-бара
        isOpaque = false
        backgroundColor = .clear
        // системная тень borderless-окна рисует светлый 1px-ободок по контуру — отключаем
        hasShadow = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 680, height: 420)
        animationBehavior = .utilityWindow
        setFrameAutosaveName("FedTermPanel")

        // блюр-подложка как у спотлайта
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        // регулируемое затемнение поверх блюра — на светлых обоях стекло не белёсое
        let dim = NSView()
        dim.wantsLayer = true
        dim.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(dim)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(contentView)
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: effect.topAnchor),
            dim.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: effect.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])
        self.contentView = effect
        self.dimView = dim
        appearance = NSAppearance(named: .darkAqua)

        applyDim()
        dimObserver = NotificationCenter.default.addObserver(
            forName: SettingsStore.appearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyDim()
        }
    }

    private var dimView: NSView?
    private var dimObserver: NSObjectProtocol?

    private func applyDim() {
        let dim = CGFloat(SettingsStore.shared.windowDim)
        dimView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Запоминание позиции и размера

    private static let frameKey = "FedTermSavedFrame"

    func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    private var savedFrame: NSRect? {
        guard let str = UserDefaults.standard.string(forKey: Self.frameKey) else { return nil }
        let rect = NSRectFromString(str)
        guard rect.width >= minSize.width, rect.height >= minSize.height else { return nil }
        return rect
    }

    /// Показ: там, где пользователь оставил окно; если сохранённого фрейма нет
    /// или он вне видимых экранов — по центру активного экрана (чуть выше середины, как Spotlight).
    func present() {
        if let saved = savedFrame,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            setFrame(saved, display: true)
        } else {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main
            if let screen {
                var frame = self.frame
                if frame.width < minSize.width { frame.size = NSSize(width: 780, height: 500) }
                frame.origin.x = screen.visibleFrame.midX - frame.width / 2
                frame.origin.y = screen.visibleFrame.midY - frame.height / 2 + screen.visibleFrame.height * 0.08
                setFrame(frame, display: true)
                saveFrame()
            }
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
