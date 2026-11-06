import XCTest
@testable import SudoPromptCore

final class ResolvedCommandTests: XCTestCase {
    private func encode(_ args: [String]) -> String {
        Data(args.map { $0 + "\0" }.joined().utf8).base64EncodedString()
    }

    func testDecodeRoundTrip() {
        let args = ["/usr/bin/sudo", "-A", "-k", "sh", "-c", "echo \"a b\" && id", ""]
        XCTAssertEqual(ResolvedCommand.decodeClaimed(encode(args)), args)
        XCTAssertNil(ResolvedCommand.decodeClaimed(nil))
        XCTAssertNil(ResolvedCommand.decodeClaimed("not base64!"))
        XCTAssertNil(ResolvedCommand.decodeClaimed(Data("no-terminator".utf8).base64EncodedString()))
    }

    func testMatchingClaimIsExact() {
        let argv = ["/usr/bin/sudo", "-A", "-k", "sh", "-c", "echo \"a b\" && id"]
        let resolved = ResolvedCommand.resolve(claimed: argv, psArgs: #"/usr/bin/sudo -A -k sh -c echo "a b" && id"#)
        XCTAssertEqual(resolved, .exact(SudoInvocation(argv: argv), sudoArgv: argv))
    }

    func testMismatchedClaimFallsBackToPs() {
        let ps = "/usr/bin/sudo -A -k rm -rf /"
        XCTAssertEqual(ResolvedCommand.resolve(claimed: ["/usr/bin/sudo", "-A", "-k", "true"], psArgs: ps),
                       .approximate(ps))
        XCTAssertEqual(ResolvedCommand.resolve(claimed: nil, psArgs: ps), .approximate(ps))
    }

    func testNoPsIsUnknown() {
        XCTAssertEqual(ResolvedCommand.resolve(claimed: ["sudo", "true"], psArgs: nil), .unknown)
    }
}
