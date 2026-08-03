import Foundation

/// A single executed command recorded by the zsh preexec hook (or a start/end event from the app).
struct CommandRecord: Codable, Identifiable, Hashable {
    var ts: Double
    var sid: String
    var cwd: String?
    var cmd: String?
    var event: String?   // "start" | "end" | nil (regular command)

    var id: String { "\(sid)-\(ts)-\(cmd ?? event ?? "")" }
    var date: Date { Date(timeIntervalSince1970: ts) }
}

/// SSH target: user@host[:port], extracted from a command.
struct SSHTarget: Codable, Hashable, Identifiable {
    var user: String?
    var host: String
    var port: Int?
    var label: String?

    var id: String { displayTarget }

    /// user@host — what gets substituted into the ssh command.
    var connectString: String {
        (user.map { "\($0)@" } ?? "") + host
    }

    var displayTarget: String {
        connectString + (port.map { ":\($0)" } ?? "")
    }

    /// Full command to run.
    var sshCommand: String {
        var parts = ["ssh"]
        if let port { parts.append("-p \(port)") }
        parts.append(connectString)
        return parts.joined(separator: " ")
    }

    /// Tries to parse an ssh command and extract the target.
    /// Understands flags with arguments (-p, -i, -o, ...) and the forms `ssh user@host`, `ssh host`.
    static func parse(from command: String) -> SSHTarget? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        var tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = tokens.first else { return nil }
        // also support `autossh` and command chains like `ssh host` at the start of the line
        guard first == "ssh" || first.hasSuffix("/ssh") else { return nil }
        tokens.removeFirst()

        let flagsWithValue: Set<String> = [
            "-p", "-i", "-L", "-R", "-D", "-o", "-F", "-J", "-l",
            "-W", "-b", "-c", "-e", "-m", "-O", "-Q", "-S", "-w", "-E", "-B", "-I",
        ]

        var port: Int? = nil
        var login: String? = nil
        var target: String? = nil

        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            if tok.hasPrefix("-") {
                if flagsWithValue.contains(tok), i + 1 < tokens.count {
                    let value = tokens[i + 1]
                    if tok == "-p" { port = Int(value) }
                    if tok == "-l" { login = value }
                    i += 2
                } else {
                    i += 1 // standalone flag (-A, -v, -T, …)
                }
                continue
            }
            target = tok
            break // everything after the target is the remote command, leave it alone
        }

        guard var host = target, !host.isEmpty else { return nil }
        var user: String? = login
        if let at = host.firstIndex(of: "@") {
            user = String(host[..<at])
            host = String(host[host.index(after: at)...])
        }
        // ssh://user@host:port
        if host.hasPrefix("ssh://") {
            host = String(host.dropFirst(6))
            if let at = host.firstIndex(of: "@") {
                user = String(host[..<at])
                host = String(host[host.index(after: at)...])
            }
            if let colon = host.lastIndex(of: ":"), let p = Int(host[host.index(after: colon)...]) {
                port = p
                host = String(host[..<colon])
            }
        }
        guard !host.isEmpty, host != "ssh" else { return nil }
        return SSHTarget(user: user, host: host, port: port, label: nil)
    }
}

/// Terminal session: all commands sharing one sid.
struct SessionSummary: Identifiable {
    var sid: String
    var records: [CommandRecord]

    var id: String { sid }
    var startDate: Date? { records.first?.date }
    var lastDate: Date? { records.last?.date }
    var commands: [CommandRecord] { records.filter { $0.event == nil && $0.cmd != nil } }
    var sshTargets: [SSHTarget] {
        commands.compactMap { $0.cmd.flatMap(SSHTarget.parse(from:)) }
    }
}

/// Keyword-based command classification — for the brief "what happened this hour" summary.
enum CommandKind: String, CaseIterable {
    case ssh, git, docker, kubernetes, node, brew, files, editor, network, other

    var icon: String {
        switch self {
        case .ssh: return "network"
        case .git: return "arrow.triangle.branch"
        case .docker: return "shippingbox"
        case .kubernetes: return "helm"
        case .node: return "cube.box"
        case .brew: return "mug"
        case .files: return "folder"
        case .editor: return "pencil"
        case .network: return "globe"
        case .other: return "terminal"
        }
    }

    var title: String {
        switch self {
        case .ssh: return "ssh"
        case .git: return "git"
        case .docker: return "docker"
        case .kubernetes: return "k8s"
        case .node: return "node/npm"
        case .brew: return "brew"
        case .files: return "файлы"
        case .editor: return "редактор"
        case .network: return "сеть"
        case .other: return "прочее"
        }
    }

    static func classify(_ command: String) -> CommandKind {
        let first = command.trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init) ?? ""
        let name = first.split(separator: "/").last.map(String.init) ?? first
        switch name {
        case "ssh", "scp", "sftp", "autossh", "ssh-copy-id", "mosh": return .ssh
        case "git", "gh", "tig", "lazygit": return .git
        case "docker", "docker-compose", "podman", "colima": return .docker
        case "kubectl", "helm", "k9s", "minikube": return .kubernetes
        case "node", "npm", "npx", "yarn", "pnpm", "bun", "deno": return .node
        case "brew", "port": return .brew
        case "ls", "cd", "cp", "mv", "rm", "mkdir", "cat", "find", "grep", "rg", "fd", "tar", "unzip", "touch", "chmod", "chown", "ln": return .files
        case "vim", "nvim", "nano", "emacs", "code", "subl": return .editor
        case "curl", "wget", "ping", "dig", "nslookup", "traceroute", "nc", "telnet", "http": return .network
        default: return .other
        }
    }
}

/// Activity summary for an interval (e.g. the last hour).
struct ActivitySummary {
    var interval: TimeInterval
    var totalCommands: Int
    var sshTargets: [SSHTarget]           // unique, ordered by most recent use
    var kindCounts: [(kind: CommandKind, count: Int)]
    var recent: [CommandRecord]           // latest commands, newest first

    var isEmpty: Bool { totalCommands == 0 }
}
