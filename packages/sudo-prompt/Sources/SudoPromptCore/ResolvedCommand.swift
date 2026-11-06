import Foundation

/// What sudo is about to run, as far as we can tell.
public enum ResolvedCommand: Equatable, Sendable {
    /// Exact argv, confirmed against the live sudo process.
    case exact(SudoInvocation, sudoArgv: [String])
    /// Only `ps`'s space-joined view is available, so argument boundaries are unknown.
    case approximate(String)
    case unknown

    /// The askpass helper cannot read a root process's argv directly (only the
    /// setuid `/bin/ps` can, and only space-joined), so the wrapper hands over
    /// the exact argv in an env var. That claim is trusted only if it joins to
    /// exactly what `ps` reports for the real sudo, so a caller can't make the
    /// dialog show something other than what will run.
    public static func resolve(claimed: [String]?, psArgs: String?) -> ResolvedCommand {
        guard let psArgs, !psArgs.isEmpty else { return .unknown }
        if let claimed, claimed.joined(separator: " ") == psArgs {
            return .exact(SudoInvocation(argv: claimed), sudoArgv: claimed)
        }
        return .approximate(psArgs)
    }

    /// Decodes the wrapper's `SUDO_PROMPT_ARGV`: base64 of NUL-terminated args.
    public static func decodeClaimed(_ value: String?) -> [String]? {
        guard let value, let data = Data(base64Encoded: value, options: .ignoreUnknownCharacters),
              data.last == 0 else { return nil }
        return data.dropLast().split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
    }
}
