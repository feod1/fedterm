# Changelog

Notable changes to FedTerm.

## 1.1 — 2026-08-03

### Added
- Recent tabs panel on <kbd>⌘E</kbd>, in the spirit of Recent Files in WebStorm: tabs ordered by last use, <kbd>↑</kbd><kbd>↓</kbd>/<kbd>⌘E</kbd> to navigate, <kbd>Enter</kbd> to switch. Opens with the previous tab preselected, so <kbd>⌘E</kbd><kbd>Enter</kbd> jumps back. The order survives restarts.
- Interface language picker in settings: system default, Russian or English. Applies after a restart; the default keeps the old behaviour (Russian system → Russian UI, anything else → English).
- A short hotkey reference at the bottom of settings.
- Everything on the home screen can be deleted now: commands in history and in search results, and recent connections are erased from history forever (all their records, so they don't resurface); favourites and pins are removed from their lists. Trash button on the selected row, plus a context menu entry.

### Changed
- Code comments are written in English now.
- README: building requires full Xcode, not just Command Line Tools — SwiftTerm compiles a Metal shader and the `metal` compiler ships only with Xcode (#1).

## 1.0 — 2026-07-28

Initial release.

- Terminal in a floating window on a global shortcut (<kbd>⌥</kbd><kbd>Space</kbd>, rebindable), on top of any app including fullscreen ones. Lives in the menu bar, no Dock icon.
- One input field for everything: a command runs in a new tab, an SSH target opens a connection, a folder path starts a Claude Code session, plain text searches command history.
- Command history captured through a zsh preexec hook, grouped by age, with fuzzy search.
- Favourite commands, pinned SSH connections, autostart tabs.
- Claude Code: named sessions that resume exactly, a browser of all past sessions from `~/.claude/projects`.
- Custom commands on <kbd>⌃1</kbd>–<kbd>⌃9</kbd> with working directories.
- Tabs with drag reorder, rename, and restore on launch; SSH tabs reconnect.
- 13 built-in themes, a theme editor, font family/size/weight, thin strokes, background transparency.
- Russian and English interface.
