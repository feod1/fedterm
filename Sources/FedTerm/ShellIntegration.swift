import Foundation

/// Generates ZDOTDIR shims: zsh starts with our config, which sources the user's
/// ~/.zshenv/.zprofile/.zshrc/.zlogin and installs a preexec hook that writes
/// every executed command to history.jsonl (per session, with cwd and timestamp).
enum ShellIntegration {
    static func ensureInstalled() {
        let dir = AppPaths.zdotdir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        write("zshenv", """
        # FedTerm shim — source the user's own config
        [[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
        """)

        write("zprofile", """
        [[ -f "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
        """)

        write("zlogin", """
        [[ -f "$HOME/.zlogin" ]] && source "$HOME/.zlogin"
        """)

        write("zshrc", """
        # FedTerm shim — user config + history capture hook
        [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

        if [[ -n "$FEDTERM_HIST" && -n "$FEDTERM_SESSION_ID" ]]; then
            zmodload zsh/datetime 2>/dev/null

            __fedterm_escape() {
                local s="$1"
                s=${s//\\\\/\\\\\\\\}
                s=${s//\\"/\\\\\\"}
                s=${s//$'\\n'/\\\\n}
                s=${s//$'\\t'/\\\\t}
                s=${s//$'\\r'/}
                print -r -- "$s"
            }

            __fedterm_preexec() {
                local cmd cwd
                cmd=$(__fedterm_escape "$1")
                cwd=$(__fedterm_escape "$PWD")
                print -r -- "{\\"ts\\":${EPOCHSECONDS},\\"sid\\":\\"${FEDTERM_SESSION_ID}\\",\\"cwd\\":\\"${cwd}\\",\\"cmd\\":\\"${cmd}\\"}" >> "$FEDTERM_HIST" 2>/dev/null
            }

            autoload -Uz add-zsh-hook
            add-zsh-hook preexec __fedterm_preexec
        fi

        # so that nested zsh behaves as usual
        unset ZDOTDIR
        """)
    }

    private static func write(_ name: String, _ content: String) {
        let url = AppPaths.zdotdir.appendingPathComponent(".\(name)")
        try? (content + "\n").data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Environment for launching zsh inside the terminal.
    static func environment(sessionID: String) -> [String] {
        var env: [String: String] = ProcessInfo.processInfo.environment
        // If FedTerm was launched from inside a Claude Code session (open inherits env),
        // the CLAUDE_CODE_CHILD_SESSION marker makes Claude in the tabs DISABLE
        // transcript saving. Strip everything Claude-related — tabs must be
        // fully independent sessions.
        for key in env.keys where key.hasPrefix("CLAUDE") || key.hasPrefix("ANTHROPIC") {
            env.removeValue(forKey: key)
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["ZDOTDIR"] = AppPaths.zdotdir.path
        env["FEDTERM_SESSION_ID"] = sessionID
        env["FEDTERM_HIST"] = AppPaths.historyFile.path
        env["TERM_PROGRAM"] = "FedTerm"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }
}
