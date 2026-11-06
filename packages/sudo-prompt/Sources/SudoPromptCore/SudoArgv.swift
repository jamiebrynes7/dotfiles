/// A `sudo` invocation split into sudo's own options and the command it will run.
public struct SudoInvocation: Equatable, Sendable {
    public let options: [String]
    public let command: [String]
    /// Target user from `-u`/`--user`, or nil for the default (root).
    public let user: String?

    public init(options: [String], command: [String], user: String?) {
        self.options = options; self.command = command; self.user = user
    }

    /// Parses the full argv of a `sudo` process (argv[0] included).
    public init(argv: [String]) {
        var options: [String] = []
        var user: String?
        var i = 1
        parsing: while i < argv.count {
            let arg = argv[i]
            if arg == "--" {
                options.append(arg); i += 1; break
            }
            if arg.hasPrefix("--") {
                options.append(arg)
                let name = String(arg.dropFirst(2).prefix { $0 != "=" })
                if Self.longWithValue.contains(name) {
                    var value: String?
                    if let eq = arg.firstIndex(of: "=") {
                        value = String(arg[arg.index(after: eq)...])
                    } else if i + 1 < argv.count {
                        i += 1; value = argv[i]; options.append(argv[i])
                    }
                    if name == "user" { user = value }
                }
                i += 1; continue
            }
            guard arg.hasPrefix("-"), arg.count > 1 else { break parsing }

            // A cluster like `-Ak` or `-uroot`: a value-taking flag consumes the
            // rest of the cluster, or the next argument if the cluster ends there.
            options.append(arg)
            let flags = Array(arg.dropFirst())
            for (j, flag) in flags.enumerated() where Self.shortWithValue.contains(flag) {
                let rest = String(flags[(j + 1)...])
                var value: String?
                if !rest.isEmpty {
                    value = rest
                } else if i + 1 < argv.count {
                    i += 1; value = argv[i]; options.append(argv[i])
                }
                if flag == "u" { user = value }
                break
            }
            i += 1
        }
        self.init(options: options, command: Array(argv[min(i, argv.count)...]), user: user)
    }

    // From sudo(8). `-h` is left out: alone it means help, and `-h host` is rare.
    static let shortWithValue: Set<Character> = ["C", "D", "g", "p", "R", "r", "T", "t", "U", "u"]
    static let longWithValue: Set<String> = [
        "close-from", "chdir", "chroot", "group", "host", "prompt", "role",
        "type", "command-timeout", "other-user", "user",
    ]
}
