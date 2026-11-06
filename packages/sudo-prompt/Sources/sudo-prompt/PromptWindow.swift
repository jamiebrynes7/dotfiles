import AppKit
import SudoPromptCore

/// What the dialog shows. `lines` is nil when sudo's argv could not be read.
struct PromptRequest {
    let user: String
    let lines: [Line]?
    let warning: String?
    let requestedBy: String
    let directory: String
}

@MainActor
final class PromptWindow: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let password = NSSecureTextField()
    private let code: NSScrollView
    private let onFinish: (String?) -> Void

    // One Dark-ish, to match the code blocks in Paseo.
    private enum Palette {
        static let background = NSColor(srgbRed: 0x28 / 255, green: 0x2C / 255, blue: 0x34 / 255, alpha: 1)
        static func color(_ kind: TokenKind) -> NSColor {
            switch kind {
            case .command:  return hex(0x61AFEF)
            case .flag:     return hex(0xD19A66)
            case .string:   return hex(0x98C379)
            case .variable: return hex(0xE06C75)
            case .op:       return hex(0xC678DD)
            case .comment:  return hex(0x7F848E)
            case .plain:    return hex(0xABB2BF)
            }
        }
        static func hex(_ v: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
    }

    private static let width: CGFloat = 620
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    init(_ request: PromptRequest, onFinish: @escaping (String?) -> Void) {
        self.onFinish = onFinish
        code = Self.codeBlock(request.lines)
        panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()

        panel.title = "sudo"
        // Spawned from the background, so make sure it lands on the current Space
        // (full-screen ones included) above everything, not behind other apps.
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Panels hide when their app deactivates by default; this one must stay
        // up until answered, since sudo is blocked on it.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let icon = NSImageView(image: NSImage(named: NSImage.cautionName) ?? NSImage())
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let title = NSTextField(labelWithString: "Run as \(request.user)?")
        title.font = .boldSystemFont(ofSize: 15)
        let context = NSStackView(views: [
            title,
            Self.detail("Requested by", request.requestedBy),
            Self.detail("In", request.directory),
        ])
        context.orientation = .vertical
        context.alignment = .leading
        context.spacing = 4

        let header = NSStackView(views: [icon, context])
        header.alignment = .top
        header.spacing = 14

        password.placeholderString = "Password for \(NSUserName())"
        password.target = self
        password.action = #selector(allow)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let allow = NSButton(title: "Allow", target: self, action: #selector(allow))
        allow.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, allow])

        var views: [NSView] = [header, code]
        if let warning = request.warning {
            let label = NSTextField(wrappingLabelWithString: warning)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .systemOrange
            views.append(label)
        }
        views += [password, buttons]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for view in stack.arrangedSubviews where view !== header {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: Self.width + 40).isActive = true

        panel.contentView = stack
        panel.initialFirstResponder = password
    }

    func show() {
        // Centre on the screen under the pointer: NSScreen.main follows the key
        // window, which belongs to some other app.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.1))
        }
        // A background process asking to activate is often refused on macOS 14+,
        // so order the panel front regardless of whether activation succeeds.
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        // A command tall enough to scroll otherwise opens a few points below its top.
        panel.layoutIfNeeded()
        code.documentView?.scroll(.zero)
        NSSound.beep()
    }

    @objc private func allow() { finish(password.stringValue) }
    @objc private func cancel() { finish(nil) }
    func windowWillClose(_ notification: Notification) { onFinish(nil) }

    private func finish(_ result: String?) {
        panel.delegate = nil
        panel.close()
        onFinish(result)
    }

    private static func detail(_ label: String, _ value: String) -> NSTextField {
        let text = NSMutableAttributedString(string: "\(label): ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        text.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
        ]))
        let field = NSTextField(labelWithAttributedString: text)
        field.isSelectable = true
        field.lineBreakMode = .byTruncatingMiddle
        field.preferredMaxLayoutWidth = width - 62
        return field
    }

    /// The command, highlighted, in a scrolling block capped at 60% of the screen.
    /// Nothing is truncated; wrapped continuations get a hanging indent so they
    /// can't be mistaken for a new step.
    private static func codeBlock(_ lines: [Line]?) -> NSScrollView {
        let charWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let text = NSMutableAttributedString()

        if let lines {
            for (n, line) in lines.enumerated() {
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = CGFloat(line.indent) * 2 * charWidth
                style.headIndent = style.firstLineHeadIndent + 4 * charWidth
                style.lineBreakMode = .byCharWrapping
                style.paragraphSpacing = 2
                for token in ShellHighlighter.tokens(line.text) {
                    text.append(NSAttributedString(string: token.text, attributes: [
                        .font: font, .foregroundColor: Palette.color(token.kind), .paragraphStyle: style,
                    ]))
                }
                if n < lines.count - 1 { text.append(NSAttributedString(string: "\n")) }
            }
        } else {
            text.append(NSAttributedString(string: "Couldn't read the command sudo is about to run.\nCancel unless you know what asked for this.",
                                           attributes: [.font: font, .foregroundColor: Palette.hex(0xE06C75)]))
        }

        let inset = NSSize(width: 12, height: 10)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = inset
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        textView.textStorage?.setAttributedString(text)

        var height: CGFloat = 40
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            height = layout.usedRect(for: container).height + inset.height * 2
        }
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) * 0.6

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = height > maxHeight
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.background
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.masksToBounds = true
        scroll.heightAnchor.constraint(equalToConstant: min(height, maxHeight)).isActive = true
        return scroll
    }
}
