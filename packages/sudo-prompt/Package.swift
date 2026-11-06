// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SudoPrompt",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SudoPromptCore"),
        .executableTarget(name: "sudo-prompt", dependencies: ["SudoPromptCore"]),
        .testTarget(name: "SudoPromptCoreTests", dependencies: ["SudoPromptCore"]),
    ]
)
