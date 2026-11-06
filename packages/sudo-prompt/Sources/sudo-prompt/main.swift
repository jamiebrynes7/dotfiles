import AppKit
import SudoPromptCore

// SUDO_ASKPASS helper: sudo runs us with its prompt as argv[1] and reads the
// password from our stdout. Exiting non-zero tells sudo no password was given.

let sudoPID = getppid()
let resolved = ResolvedCommand.resolve(
    claimed: ResolvedCommand.decodeClaimed(ProcessInfo.processInfo.environment["SUDO_PROMPT_ARGV"]),
    psArgs: Proc.args(sudoPID)
)

var lines: [Line]?
var warning: String?
var user: String?
switch resolved {
case let .exact(invocation, sudoArgv):
    // No command (`sudo -v`, `sudo -l`): show the sudo invocation itself.
    lines = CommandFormatter.lines(for: invocation.command.isEmpty ? sudoArgv : invocation.command)
    user = invocation.user
case let .approximate(args):
    lines = [Line(indent: 0, text: args)]
    warning = "sudo was called directly rather than through the wrapper, so this is sudo's full command line with argument boundaries unknown."
case .unknown:
    break
}

let requester = Proc.parent(sudoPID).map { Proc.chain(from: $0, depth: 4) } ?? []
let home = NSHomeDirectory()
var cwd = FileManager.default.currentDirectoryPath
if cwd.hasPrefix(home) { cwd = "~" + cwd.dropFirst(home.count) }

let request = PromptRequest(
    user: user ?? "root",
    lines: lines,
    warning: warning,
    requestedBy: requester.isEmpty ? "unknown" : requester.joined(separator: " ← "),
    directory: cwd
)

// Top-level code runs on the main thread; assert it so the @MainActor window can be built.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // An accessory app has no menu bar, and without an Edit menu Cmd-V (pasting
    // from a password manager) does nothing in the password field.
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let editItem = NSMenuItem()
    editItem.submenu = editMenu
    app.mainMenu = NSMenu()
    app.mainMenu?.addItem(editItem)

    let window = PromptWindow(request) { password in
        guard let password else { exit(1) }
        FileHandle.standardOutput.write(Data((password + "\n").utf8))
        exit(0)
    }
    // NSApplication holds its delegate weakly; this local lives as long as run().
    let delegate = AppDelegate(window)
    app.delegate = delegate
    app.run()
}

/// Shows the window once launching finishes: asking to activate before then is
/// refused, leaving the panel on top but inactive (grey traffic lights, no
/// focus ring, keystrokes going to whatever app was frontmost).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let window: PromptWindow
    init(_ window: PromptWindow) { self.window = window }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.show()
    }
}
