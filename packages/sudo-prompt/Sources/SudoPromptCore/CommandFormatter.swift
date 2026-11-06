import Foundation

/// One display line of a formatted command. `indent` is a nesting level, not a
/// character count, so the view can give wrapped continuations a hanging indent.
public struct Line: Equatable, Sendable {
    public let indent: Int
    public let text: String
    public init(indent: Int, text: String) { self.indent = indent; self.text = text }
}

public enum CommandFormatter {

    /// Lays out a command for review. A `sh -c SCRIPT` (or bash/zsh/dash) puts the
    /// script one step per line under the shell, so a long chain cannot hide a
    /// step mid-line; anything else is the shell-quoted argv on one line.
    public static func lines(for argv: [String]) -> [Line] {
        guard let first = argv.first else { return [] }
        let shells: Set<String> = ["sh", "bash", "zsh", "dash"]
        let shell = String(first.split(separator: "/").last ?? "")
        if argv.count >= 3, shells.contains(shell), isDashC(argv[1]) {
            var lines = [Line(indent: 0, text: "\(quote(first)) \(argv[1])")]
            lines += splitScript(argv[2]).map { Line(indent: 1, text: $0) }
            if argv.count > 3 {
                lines.append(Line(indent: 0, text: argv[3...].map(quote).joined(separator: " ")))
            }
            return lines
        }
        return [Line(indent: 0, text: argv.map(quote).joined(separator: " "))]
    }

    /// `-c`, or a cluster ending in it such as `-ec` / `-lc`.
    static func isDashC(_ arg: String) -> Bool {
        arg.hasPrefix("-") && arg.hasSuffix("c") && arg.dropFirst().allSatisfy(\.isLetter)
    }

    /// Single-quotes an argument only when it needs it, so typical commands read
    /// as typed rather than as a wall of backslashes.
    public static func quote(_ arg: String) -> String {
        let safe = arg.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_@%+=:,./-".contains($0)) }
        if !arg.isEmpty && safe { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Splits a shell script into steps at top-level `&&`, `||`, `;`, `|` and
    /// newlines, keeping the operator at the end of its step. Quotes, escapes,
    /// comments, backticks and parentheses (`$(…)`, subshells) are respected.
    /// Display only: this is not a shell parser and does not need to be.
    public static func splitScript(_ script: String) -> [String] {
        let chars = Array(script)
        var steps: [String] = []
        var current = ""
        var single = false, double = false, backtick = false, comment = false
        var depth = 0

        func flush() {
            let step = current.trimmingCharacters(in: .whitespaces)
            if !step.isEmpty { steps.append(step) }
            current = ""
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            defer { i += 1 }

            if comment {
                if c == "\n" { comment = false; flush() } else { current.append(c) }
                continue
            }
            if single {
                current.append(c); if c == "'" { single = false }
                continue
            }
            if c == "\\", let next {
                current.append(c); current.append(next); i += 1
                continue
            }
            if double {
                current.append(c); if c == "\"" { double = false }
                continue
            }
            switch c {
            case "'": single = true
            case "\"": double = true
            case "`": backtick.toggle()
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            case "#" where current.last.map(\.isWhitespace) ?? true:
                comment = true
            default: break
            }
            let topLevel = depth == 0 && !backtick
            if topLevel, (c == "&" && next == "&") || (c == "|" && next == "|") {
                current.append(c); current.append(next!); i += 1; flush()
            } else if topLevel, c == ";" || c == "|" {
                current.append(c); flush()
            } else if topLevel, c == "\n" {
                flush()
            } else {
                current.append(c)
            }
        }
        flush()
        return steps
    }
}

