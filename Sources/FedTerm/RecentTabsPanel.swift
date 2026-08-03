import SwiftUI
import Combine

/// State of the "recent tabs" panel (⌘E): visibility and the selected row.
/// Keys are handled by the monitor in AppDelegate; the view only draws.
final class RecentTabsState: ObservableObject {
    static let shared = RecentTabsState()
    @Published var visible = false
    @Published var selection = 0

    /// On show: selection starts on the second row — Enter immediately returns to the
    /// previous tab (like ⌘E in WebStorm).
    func show(count: Int) {
        selection = count > 1 ? 1 : 0
        visible = true
    }

    func hide() {
        visible = false
    }

    func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }
}

/// Overlay listing tabs by recency — like Recent Files in WebStorm.
struct RecentTabsOverlay: View {
    @EnvironmentObject var tabs: TabsModel
    @ObservedObject var state: RecentTabsState = .shared

    var body: some View {
        let recent = tabs.recentTabs
        ZStack {
            Color.black.opacity(0.35)
                .onTapGesture { state.hide() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text(L.recentTabsTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("⌘E")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, tab in
                                RecentTabRow(tab: tab, isSelected: index == min(state.selection, recent.count - 1))
                                    .id(index)
                                    .onTapGesture {
                                        tabs.selectedID = tab.id
                                        state.hide()
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: state.selection) { sel in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(sel) }
                    }
                }
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                Text(L.recentTabsHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .frame(width: 440)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: NSColor(hex: 0x24282E)))
                    .shadow(radius: 30)
            )
        }
    }
}

private struct RecentTabRow: View {
    @ObservedObject var tab: Tab
    let isSelected: Bool
    // The mouse doesn't move the selection (Enter always goes to what the keyboard picked),
    // hovering only highlights the row as clickable.
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.12)
                      : hovering ? Color.white.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var iconColor: Color {
        if case .terminal(let controller) = tab.kind,
           controller.claudeRecordID != nil || controller.claudeSessionID != nil {
            return claudeOrange
        }
        return isSelected ? .primary : .secondary
    }

    private var subtitle: String {
        guard let terminal = tab.terminal else { return L.recentTabHome }
        if let target = terminal.sshTarget { return target.displayTarget }
        let path = terminal.currentDirectory ?? terminal.startDirectory
        return path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"
        )
    }
}
