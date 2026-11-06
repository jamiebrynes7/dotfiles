public enum TokenKind: Equatable, Sendable {
    case command, flag, string, variable, op, comment, plain
}

public struct Token: Equatable, Sendable {
    public let text: String
    public let kind: TokenKind
    public init(_ text: String, _ kind: TokenKind) { self.text = text; self.kind = kind }
}

/// Splits one display line into coloured tokens. Concatenating the tokens'
/// text always reproduces the input exactly, whitespace included.
public enum ShellHighlighter {

    public static func tokens(_ line: String) -> [Token] {
        let chars = Array(line)
        var out: [Token] = []
        var expectCommand = true
        var i = 0

        func take(while pred: (Character) -> Bool) -> String {
            let start = i
            while i < chars.count, pred(chars[i]) { i += 1 }
            return String(chars[start..<i])
        }

        while i < chars.count {
            let c = chars[i]

            if c.isWhitespace {
                out.append(Token(take { $0.isWhitespace }, .plain))
            } else if c == "#" {
                out.append(Token(String(chars[i...]), .comment)); i = chars.count
            } else if Self.opChars.contains(c) {
                let op = take { Self.opChars.contains($0) }
                // `2>&1`'s target digit belongs to the redirect, not the next word.
                let fd = op.hasSuffix("&") ? take { $0.isNumber } : ""
                out.append(Token(op + fd, .op))
                // Redirects are followed by a file; everything else by a command.
                expectCommand = !(op.contains(">") || op.contains("<"))
            } else if c == "$" && i + 1 < chars.count && chars[i + 1] == "(" {
                out.append(Token("$(", .op)); i += 2; expectCommand = true
            } else {
                let word = takeWord(chars, &i)
                out.append(Token(word, kind(of: word, expectCommand: &expectCommand)))
            }
        }
        return out
    }

    static let opChars: Set<Character> = ["&", "|", ";", "<", ">", "(", ")"]

    /// A word runs to whitespace or an operator, consuming quoted spans whole
    /// (so `"a && b"` stays one string) and backslash escapes.
    static func takeWord(_ chars: [Character], _ i: inout Int) -> String {
        let start = i
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || opChars.contains(c) { break }
            if c == "\\" { i = min(i + 2, chars.count); continue }
            if c == "'" || c == "\"" {
                i += 1
                while i < chars.count, chars[i] != c {
                    if c == "\"" && chars[i] == "\\" { i += 1 }
                    i += 1
                }
                i = min(i + 1, chars.count)
                continue
            }
            if c == "$" && i + 1 < chars.count && chars[i + 1] == "(" && i > start { break }
            i += 1
        }
        return String(chars[start..<i])
    }

    static func kind(of word: String, expectCommand: inout Bool) -> TokenKind {
        if let first = word.first, first == "'" || first == "\"" {
            expectCommand = false
            return .string
        }
        if word.hasPrefix("$") { expectCommand = false; return .variable }
        if expectCommand {
            // `FOO=bar cmd`: the assignment is not the command; the next word is.
            if let eq = word.firstIndex(of: "="), eq != word.startIndex,
               word[..<eq].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                return .variable
            }
            expectCommand = false
            return .command
        }
        if word.hasPrefix("-") { return .flag }
        return .plain
    }
}
