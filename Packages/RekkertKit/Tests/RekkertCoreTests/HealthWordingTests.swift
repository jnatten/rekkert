import Foundation
import Testing

/// App Review asks for "Apple Health" on screen, never Health alone and never the framework's
/// name, so every string literal in either app is held to it.
@Suite("Apple Health is called by its name")
struct HealthWordingTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let scanned = ["App/Sources", "WatchApp/Sources", "Shared", "Packages/RekkertKit/Sources/RekkertCore/Help"]

    private static func literals() throws -> [(file: String, text: String)] {
        let literal = /"([^"\n]*)"/
        var found: [(String, String)] = []
        for folder in scanned {
            let files = FileManager.default.enumerator(at: root.appending(path: folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let path = String(url.path.dropFirst(root.path.count + 1))
                let text = try String(contentsOf: url, encoding: .utf8)
                for match in text.matches(of: literal) { found.append((path, String(match.output.1))) }
            }
        }
        return found
    }

    /// Asset names, which are never shown.
    private static let assets: Set = ["AppleHealth"]

    @Test func noLiteralSaysHealthOnItsOwn() throws {
        for (file, text) in try Self.literals() where !Self.assets.contains(text) {
            let bare = text.contains("HealthKit")
                || text.contains("the Health app")
                || text.replacing("Apple Health", with: "").contains("Health")
            #expect(!bare, "\(file): \"\(text)\" should say Apple Health")
        }
    }
}
