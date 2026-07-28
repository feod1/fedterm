import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Поле записи глобального хоткея: клик — и следующее нажатое сочетание становится хоткеем.
/// Пока идёт запись, системная регистрация снята, иначе Carbon перехватил бы нажатие
/// раньше, чем его увидит монитор событий.
struct HotkeyRecorderView: View {
    @ObservedObject private var settings = SettingsStore.shared

    @State private var recording = false
    @State private var liveModifiers: UInt32 = 0
    @State private var message: String?
    @State private var messageIsError = false
    @State private var monitor: Any?
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.globalHotkey)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                capsule
                if !settings.hotKeyIsDefault && !recording {
                    Button {
                        settings.resetHotKey()
                        show(L.hotkeyReset, isError: false)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L.hotkeyResetHelp)
                }
            }

            Text(message ?? (recording ? L.hotkeyEscHint : L.hotkeyHint))
                .font(.system(size: 9))
                .foregroundStyle(messageIsError && message != nil ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(.tertiary))
                .animation(.easeOut(duration: 0.15), value: message)
        }
        .onDisappear { stopRecording(restore: true) }
    }

    // MARK: - Капсула с сочетанием

    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: recording ? "record.circle" : "command")
                .font(.system(size: 11))
                .foregroundStyle(recording ? Color.red.opacity(0.9) : .secondary)
            Text(capsuleTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(recording ? .secondary : .primary)
                .animation(nil, value: capsuleTitle)
        }
        .frame(minWidth: 128)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(recording ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    recording ? Color.accentColor.opacity(pulse ? 0.9 : 0.35) : Color.white.opacity(0.12),
                    lineWidth: recording ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { recording ? stopRecording(restore: true) : startRecording() }
        .help(L.hotkeyRecordHelp)
    }

    private var capsuleTitle: String {
        guard recording else { return settings.hotKeyDisplay }
        let held = HotkeyFormatter.modifierSymbols(liveModifiers)
        return held.isEmpty ? L.hotkeyPressPrompt : held + "…"
    }

    // MARK: - Запись

    private func startRecording() {
        guard !recording else { return }
        recording = true
        message = nil
        liveModifiers = 0
        // навигация спотлайта и вкладочные шорткаты не должны перехватывать клавиши
        PanelBridge.shared.editingText = true
        HotkeyManager.shared.suspend()
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil // ни одно нажатие не уходит дальше, пока идёт запись
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            liveModifiers = HotkeyFormatter.carbonFlags(from: event.modifierFlags)
            return
        }
        let modifiers = HotkeyFormatter.carbonFlags(from: event.modifierFlags)
        let code = UInt32(event.keyCode)

        // Esc — отмена, ⌫ — вернуть значение по умолчанию
        if modifiers == 0, code == UInt32(kVK_Escape) {
            stopRecording(restore: true)
            return
        }
        if modifiers == 0, code == UInt32(kVK_Delete) {
            stopRecording(restore: true)
            settings.resetHotKey()
            show(L.hotkeyReset, isError: false)
            return
        }
        // одиночная клавиша отобрала бы ввод у всех приложений — просим модификатор
        // (кроме F-клавиш, их не жалко)
        guard modifiers != 0 || HotkeyFormatter.isStandaloneSafe(keyCode: code) else {
            show(L.hotkeyNeedsModifier, isError: true)
            return
        }
        guard settings.setHotKey(keyCode: code, modifiers: modifiers) else {
            show(L.hotkeyTaken, isError: true)
            return
        }
        stopRecording(restore: false)
        show(L.hotkeySaved(settings.hotKeyDisplay), isError: false)
    }

    private func stopRecording(restore: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        pulse = false
        liveModifiers = 0
        PanelBridge.shared.editingText = false
        if restore { HotkeyManager.shared.registerFromSettings() }
    }

    private func show(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
        guard !isError else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if message == text { message = nil }
        }
    }
}
