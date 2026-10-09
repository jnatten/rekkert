#if canImport(AppKit)
import AppKit
#endif
import Foundation
import Testing
@testable import RekkertCore

@Suite("The help screen keeps up with the app")
struct HelpTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let scanned = ["App/Sources", "WatchApp/Sources", "Shared"]

    private static func isScanned(_ path: String) -> Bool {
        path.hasSuffix(".swift")
            && !path.hasPrefix("App/Sources/Help/")
            && !path.hasSuffix("DemoLaunch.swift")
    }

    #if canImport(AppKit)
    /// Every SF Symbol named in either app, and the files naming it. A literal counts when
    /// the system knows a symbol by that name, which is what keeps this free of guessing at
    /// call sites.
    private static func symbolsOnScreen() throws -> [String: [String]] {
        let literal = /"([a-z][a-z0-9]+(?:\.[a-z0-9]+)*)"/
        var found: [String: [String]] = [:]
        for folder in scanned {
            let base = root.appending(path: folder)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                let path = String(url.path.dropFirst(root.path.count + 1))
                guard isScanned(path) else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                for match in text.matches(of: literal) {
                    let name = String(match.output.1)
                    guard NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { continue }
                    found[name, default: []].append(path)
                }
            }
        }
        return found
    }

    @Test func everySymbolOnScreenIsExplained() throws {
        let explained = HelpCatalog.explainedSymbols
        let waived = Set(HelpCatalog.selfExplanatory.keys)
        for (symbol, files) in try Self.symbolsOnScreen().sorted(by: { $0.key < $1.key }) {
            #expect(
                explained.contains(symbol) || waived.contains(symbol),
                """
                "\(symbol)" is on screen in \(Set(files).sorted().joined(separator: ", ")) but not in the help. \
                Explain it in HelpCatalog, or add it to HelpCatalog.selfExplanatory with why it needs no explaining.
                """
            )
        }
    }

    @Test func everythingExplainedIsStillOnScreen() throws {
        let onScreen = try Self.symbolsOnScreen()
        let modes = Set(GameMode.allCases.map(\.symbol))
        for symbol in HelpCatalog.explainedSymbols.subtracting(modes).sorted() {
            #expect(onScreen[symbol] != nil, "The help explains \"\(symbol)\", which neither app shows any more")
        }
    }

    @Test func waiversAreStillOnScreenAndNotAlsoExplained() throws {
        let onScreen = try Self.symbolsOnScreen()
        for symbol in HelpCatalog.selfExplanatory.keys.sorted() {
            #expect(onScreen[symbol] != nil, "\"\(symbol)\" is waived in HelpCatalog.selfExplanatory but no longer on screen")
            #expect(!HelpCatalog.explainedSymbols.contains(symbol), "\"\(symbol)\" is both explained and waived")
        }
    }
    #endif

    @Test func everyFeatureInTheReadmeHasAPage() throws {
        let readme = try String(contentsOf: Self.root.appending(path: "README.md"), encoding: .utf8)
        let headings = readme.split(separator: "\n")
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)) }
        let first = try #require(headings.firstIndex(of: "Modes"))
        let end = try #require(headings.firstIndex(of: "Getting started"))
        let covered = Set(HelpCatalog.pages.flatMap(\.readme)).union(HelpCatalog.notInHelp.keys)

        for heading in headings[first..<end] {
            #expect(
                covered.contains(heading),
                """
                README has "## \(heading)" but no help page lists it in `readme`. \
                Add a page or item to HelpCatalog, or put it in HelpCatalog.notInHelp with why.
                """
            )
        }
        for heading in covered {
            #expect(headings[first..<end].contains(heading), "The help names a README section \"\(heading)\" that is not there")
        }
    }

    @Test func noWallsOfText() {
        for page in HelpCatalog.pages {
            #expect(page.items.count <= 9, "\(page.id) has \(page.items.count) items; split it")
            for item in page.items {
                #expect(item.what.count <= 80, "\(page.id) · \(item.label): what is \(item.what.count) characters")
                #expect(item.example.count <= 100, "\(page.id) · \(item.label): example is \(item.example.count) characters")
                #expect(!item.example.isEmpty, "\(page.id) · \(item.label) has no example")
            }
        }
        for mode in GameMode.allCases {
            #expect(mode.help.pickItWhen.count <= 90, "\(mode.title): pickItWhen is too long")
            #expect((1...3).contains(mode.help.points.count), "\(mode.title) needs one to three points")
            for point in mode.help.points {
                #expect(point.count <= 90, "\(mode.title): \"\(point)\" is \(point.count) characters")
            }
        }
    }

    @Test func pagesAreWellFormed() {
        let ids = HelpCatalog.pages.map(\.id)
        #expect(Set(ids).count == ids.count, "Page ids repeat")
        for page in HelpCatalog.pages {
            let labels = page.items.map(\.label)
            #expect(Set(labels).count == labels.count, "\(page.id) repeats a label")
            switch page.picture {
            case .board:
                #expect(page.items.isEmpty)
            case .watchScore, .phoneScore:
                #expect(!page.items.isEmpty)
                for item in page.items {
                    #expect(item.spot != nil, "\(page.id) · \(item.label) has no spot on the picture")
                }
            case .watchButtons, .phoneButtons:
                #expect(!page.items.isEmpty)
            }
        }
    }

    @Test func everyModeHasAPageAndABoard() throws {
        for mode in GameMode.allCases {
            #expect(HelpCatalog.pages.contains { $0.mode == mode }, "\(mode.title) has no page")
            let state = try #require(HelpSample.state(for: mode), "\(mode.title) has no sample")
            #expect(ScoreboardSnapshot.make(from: state) != nil, "\(mode.title)'s sample draws no board")
        }
        let golden = try #require(HelpSample.goldenPoint)
        #expect(ScoreboardSnapshot.make(from: golden)?.isSuddenDeath == true)
    }
}
