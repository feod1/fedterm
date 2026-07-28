import SwiftUI

/// Шестерёнка (правый верхний угол) → поповер с настройками темы и шрифта.
struct SettingsButton: View {
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L.settings)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            SettingsView(dismiss: { showPopover = false })
        }
    }
}

struct SettingsView: View {
    var dismiss: () -> Void = {}
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var automations = AutomationsStore.shared
    @ObservedObject private var customThemes = CustomThemesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(L.settings).font(.system(size: 12, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.colorTheme)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Picker("", selection: $settings.themeID) {
                    ForEach(TerminalTheme.presets) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                    if !customThemes.themes.isEmpty {
                        Divider()
                        ForEach(customThemes.themes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                // мини-превью палитры
                HStack(spacing: 3) {
                    ForEach(Array(settings.theme.ansi.prefix(8).enumerated()), id: \.offset) { _, rgb in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(nsColor: NSColor(hex: rgb)))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: settings.theme.background))
                )

                // кастомные темы: создать из текущей / редактировать / удалить
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                        var draft = settings.theme
                        draft.id = "custom-\(UUID().uuidString.lowercased())"
                        draft.name = "\(draft.name) \(L.copySuffix)"
                        customThemes.editing = draft
                    } label: {
                        Label(L.themeNewFromCurrent, systemImage: "plus.circle")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    if customThemes.theme(id: settings.themeID) != nil {
                        Button {
                            dismiss()
                            customThemes.editing = settings.theme
                        } label: {
                            Label(L.themeEdit, systemImage: "pencil")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button {
                            customThemes.delete(id: settings.themeID)
                            settings.themeID = "darkgray"
                        } label: {
                            Label(L.themeDelete, systemImage: "trash")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.font)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Picker("", selection: $settings.fontName) {
                    ForEach(settings.availableFonts, id: \.id) { font in
                        Text(font.title).tag(font.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                HStack(spacing: 8) {
                    Text(L.fontWeightLabel)
                        .font(.system(size: 11))
                    Picker("", selection: $settings.fontWeight) {
                        Text(L.weightRegular).tag("regular")
                        Text(L.weightMedium).tag("medium")
                        Text(L.weightSemibold).tag("semibold")
                        Text(L.weightBold).tag("bold")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                HStack {
                    Text(L.fontSize(Int(settings.fontSize)))
                        .font(.system(size: 11))
                    Spacer()
                    Button { settings.decreaseFont() } label: {
                        Image(systemName: "minus.circle").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    Button { settings.increaseFont() } label: {
                        Image(systemName: "plus.circle").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    Button(L.reset) { settings.resetFont() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(L.fontHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Toggle(isOn: $settings.thinStrokes) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L.thinStrokes).font(.system(size: 11))
                        Text(L.needsRestart).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }

            HotkeyRecorderView()

            VStack(alignment: .leading, spacing: 6) {
                Text(L.windowOpacity)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    Text(L.glassy)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Slider(value: $settings.windowDim, in: 0...0.95)
                        .controlSize(.small)
                    Text(L.solid)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.automations)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                ForEach(automations.automations) { auto in
                    HStack(spacing: 10) {
                        Text("⌃\(auto.key)")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(auto.command)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let cwd = auto.cwd {
                                Text(cwd)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        Spacer()
                        Button {
                            automations.remove(auto.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                }

                if automations.freeKeys.isEmpty {
                    Text(L.noFreeKeys)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    // конструктор — отдельным оверлеем поверх окна:
                    // он переживает системные диалоги (выбор папки/файла)
                    Button {
                        dismiss()
                        automations.editorVisible = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 12))
                            Text(L.addAutomation).font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9).fill(
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
                Text(L.automationHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
