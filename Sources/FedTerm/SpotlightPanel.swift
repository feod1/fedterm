import AppKit
import SwiftUI

/// Spotlight-style floating panel: blur, rounded corners, no title bar,
/// pops up on any desktop, hides on focus loss (unless pinned).
final class SpotlightPanel: NSPanel {
    init(contentView: NSView) {
        // borderless: a titled window's invisible title bar intercepted drags
        // in the tab bar area (dragging tabs moved the whole window)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false // the window is dragged only by the tab bar's drag zone
        isOpaque = false
        backgroundColor = .clear
        // the system shadow of a borderless window draws a light 1px rim along the edge — disable it
        hasShadow = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 680, height: 420)
        animationBehavior = .utilityWindow
        setFrameAutosaveName("FedTermPanel")

        // blur backdrop like Spotlight's
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        // adjustable dimming over the blur — the glass doesn't wash out on light wallpapers
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

    // MARK: - Remembering position and size

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

    /// Show: where the user left the window; if there is no saved frame
    /// or it is off all visible screens — centered on the active screen (slightly above middle, like Spotlight).
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
