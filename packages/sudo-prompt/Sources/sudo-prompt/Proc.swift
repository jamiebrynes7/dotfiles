import Foundation

/// Read-only views of other processes via `/bin/ps`. It is setuid root, which is
/// the only way to see the argv of the root-owned `sudo` that spawned us;
/// `sysctl(KERN_PROCARGS2)` refuses with EINVAL.
enum Proc {

    /// Space-joined argv of `pid`, untruncated.
    static func args(_ pid: pid_t) -> String? { ps(pid, "args") }

    static func parent(_ pid: pid_t) -> pid_t? { ps(pid, "ppid").flatMap { pid_t($0.trimmingCharacters(in: .whitespaces)) } }

    /// Executable basename, e.g. "Paseo Daemon".
    static func name(_ pid: pid_t) -> String? {
        ps(pid, "comm").map { ($0 as NSString).lastPathComponent }
    }

    /// Names of `pid` and up to `depth - 1` ancestors, nearest first, stopping at launchd.
    static func chain(from pid: pid_t, depth: Int) -> [String] {
        var names: [String] = []
        var current: pid_t? = pid
        while let p = current, p > 1, names.count < depth {
            names.append(name(p) ?? "pid \(p)")
            current = parent(p)
        }
        return names
    }

    private static func ps(_ pid: pid_t, _ field: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-o", "\(field)=", "-p", String(pid)]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        return text.isEmpty ? nil : text
    }
}
