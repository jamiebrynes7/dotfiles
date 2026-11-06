import XCTest
@testable import SudoPromptCore

final class SudoArgvTests: XCTestCase {
    func testWrapperFlagsAreStripped() {
        let inv = SudoInvocation(argv: ["/usr/bin/sudo", "-A", "-k", "-p", "x", "sh", "-c", "id"])
        XCTAssertEqual(inv.command, ["sh", "-c", "id"])
        XCTAssertNil(inv.user)
    }

    func testClusteredAndAttachedValues() {
        XCTAssertEqual(SudoInvocation(argv: ["sudo", "-Ak", "whoami"]).command, ["whoami"])
        let attached = SudoInvocation(argv: ["sudo", "-Akupostgres", "psql"])
        XCTAssertEqual(attached.command, ["psql"])
        XCTAssertEqual(attached.user, "postgres")
        let separate = SudoInvocation(argv: ["sudo", "-u", "postgres", "psql", "-c", "select 1"])
        XCTAssertEqual(separate.command, ["psql", "-c", "select 1"])
        XCTAssertEqual(separate.user, "postgres")
    }

    func testLongOptions() {
        XCTAssertEqual(SudoInvocation(argv: ["sudo", "--user=bob", "ls"]).user, "bob")
        let spaced = SudoInvocation(argv: ["sudo", "--user", "bob", "--askpass", "ls", "-l"])
        XCTAssertEqual(spaced.user, "bob")
        XCTAssertEqual(spaced.command, ["ls", "-l"])
    }

    func testDoubleDashEndsOptions() {
        XCTAssertEqual(SudoInvocation(argv: ["sudo", "-A", "--", "-weird"]).command, ["-weird"])
    }

    func testNoCommand() {
        let inv = SudoInvocation(argv: ["sudo", "-A", "-v"])
        XCTAssertEqual(inv.command, [])
        XCTAssertEqual(inv.options, ["-A", "-v"])
    }

    func testCommandArgsThatLookLikeFlagsAreKept() {
        XCTAssertEqual(SudoInvocation(argv: ["sudo", "-A", "rm", "-rf", "/tmp/x"]).command,
                       ["rm", "-rf", "/tmp/x"])
    }
}
