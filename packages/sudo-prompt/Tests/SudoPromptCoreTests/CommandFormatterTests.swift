import XCTest
@testable import SudoPromptCore

final class CommandFormatterTests: XCTestCase {
    func testQuoting() {
        XCTAssertEqual(CommandFormatter.quote("/usr/bin/true"), "/usr/bin/true")
        XCTAssertEqual(CommandFormatter.quote("--flake=./#macbook"), "'--flake=./#macbook'")
        XCTAssertEqual(CommandFormatter.quote("hello world"), "'hello world'")
        XCTAssertEqual(CommandFormatter.quote("it's"), #"'it'\''s'"#)
        XCTAssertEqual(CommandFormatter.quote(""), "''")
    }

    func testPlainCommandIsOneLine() {
        XCTAssertEqual(CommandFormatter.lines(for: ["darwin-rebuild", "switch", "--flake", "./#macbook"]),
                       [Line(indent: 0, text: "darwin-rebuild switch --flake './#macbook'")])
    }

    func testShellScriptIsSplitIntoSteps() {
        let lines = CommandFormatter.lines(for: ["/bin/sh", "-c", "cp a b && chown root b; ls | wc -l || echo no"])
        XCTAssertEqual(lines, [
            Line(indent: 0, text: "/bin/sh -c"),
            Line(indent: 1, text: "cp a b &&"),
            Line(indent: 1, text: "chown root b;"),
            Line(indent: 1, text: "ls |"),
            Line(indent: 1, text: "wc -l ||"),
            Line(indent: 1, text: "echo no"),
        ])
    }

    func testShellFlagClusters() {
        XCTAssertEqual(CommandFormatter.lines(for: ["bash", "-ec", "a && b"]).count, 3)
        XCTAssertEqual(CommandFormatter.lines(for: ["bash", "-x", "a && b"]).count, 1)
    }

    func testTrailingPositionalArgs() {
        XCTAssertEqual(CommandFormatter.lines(for: ["sh", "-c", "echo $1", "sh", "hi there"]).last,
                       Line(indent: 0, text: "sh 'hi there'"))
    }

    func testSplitRespectsQuotesEscapesAndNesting() {
        XCTAssertEqual(CommandFormatter.splitScript(#"echo "a && b" && echo 'c; d'"#),
                       [#"echo "a && b" &&"#, "echo 'c; d'"])
        XCTAssertEqual(CommandFormatter.splitScript(#"echo a\;b; echo c"#), [#"echo a\;b;"#, "echo c"])
        XCTAssertEqual(CommandFormatter.splitScript("x=$(a && b) && echo `c; d`"),
                       ["x=$(a && b) &&", "echo `c; d`"])
        XCTAssertEqual(CommandFormatter.splitScript("cmd >out 2>&1 &"), ["cmd >out 2>&1 &"])
    }

    func testSplitHandlesNewlinesAndComments() {
        XCTAssertEqual(CommandFormatter.splitScript("a\n  b # c; d && e\nf"), ["a", "b # c; d && e", "f"])
        XCTAssertEqual(CommandFormatter.splitScript("echo a#b; c"), ["echo a#b;", "c"])
    }

    /// The prototype's disguise example: every step must get its own line.
    func testLongChainShowsEveryStep() {
        let script = """
        cp ./config/agent.plist /Library/LaunchDaemons/com.example.agent.plist && \
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
        dscl . -append /Groups/admin GroupMembership helper && \
        rm -rf /var/log/install.log && echo done
        """
        let steps = CommandFormatter.lines(for: ["sh", "-c", script]).dropFirst().map(\.text)
        XCTAssertEqual(steps.count, 5)
        XCTAssertTrue(steps[1].hasPrefix(#"echo "PermitRootLogin yes""#))
        XCTAssertTrue(steps[2].hasPrefix("dscl . -append /Groups/admin"))
    }
}
