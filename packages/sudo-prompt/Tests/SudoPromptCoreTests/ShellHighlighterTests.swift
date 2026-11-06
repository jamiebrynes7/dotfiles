import XCTest
@testable import SudoPromptCore

final class ShellHighlighterTests: XCTestCase {
    /// Non-whitespace tokens, for readable assertions.
    private func words(_ line: String) -> [Token] {
        ShellHighlighter.tokens(line).filter { $0.kind != .plain || !$0.text.allSatisfy(\.isWhitespace) }
    }

    func testRoundTripsExactly() {
        for line in ["  cp a  b &&", #"echo "x y" >> /etc/f 2>&1"#, "a # c", "FOO=1 $(id -u) | tee x"] {
            XCTAssertEqual(ShellHighlighter.tokens(line).map(\.text).joined(), line)
        }
    }

    func testKinds() {
        XCTAssertEqual(words(#"echo "PermitRootLogin yes" >> /etc/ssh/sshd_config &&"#), [
            Token("echo", .command), Token(#""PermitRootLogin yes""#, .string),
            Token(">>", .op), Token("/etc/ssh/sshd_config", .plain), Token("&&", .op),
        ])
        XCTAssertEqual(words("rm -rf $HOME/x"), [
            Token("rm", .command), Token("-rf", .flag), Token("$HOME/x", .variable),
        ])
    }

    func testCommandPositions() {
        XCTAssertEqual(words("a | b; c").filter { $0.kind == .command }.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(words("FOO=1 env").map(\.kind), [.variable, .command])
        XCTAssertEqual(words("x $(id -u)").map(\.kind), [.command, .op, .command, .flag, .op])
    }

    func testRedirectsAndComments() {
        XCTAssertEqual(words("cmd 2>&1"), [Token("cmd", .command), Token("2", .plain), Token(">&1", .op)])
        XCTAssertEqual(words("ls # list it").last, Token("# list it", .comment))
    }
}
