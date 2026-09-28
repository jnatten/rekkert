// Build numbers for TestFlight, read from App Store Connect rather than from Project.swift.
//
//     swift scripts/build-number.swift next      # the number the next upload should carry
//     swift scripts/build-number.swift wait 57   # returns once App Store Connect lists 57
//     swift scripts/build-number.swift notes 57 notes.txt   # notes.txt as 57's What to Test
//
// Needs APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and the key at
// ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 — the same three release.sh uses.
//
// `next` is one past the highest build App Store Connect has, or Project.swift's number if
// that is higher, so a number raised by hand is still honoured. `wait` is what keeps two
// uploads in a row from picking the same one: a build is not listed the moment the upload
// ends, and the next run asks for the latest as soon as it starts. `notes` works as soon as
// `wait` returns, while the build is still processing, and replaces whatever 57 said before.
import CryptoKit
import Foundation

let bundleID = "dev.natten.rekkert"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let environment = ProcessInfo.processInfo.environment
guard let keyID = environment["APP_STORE_CONNECT_KEY_ID"], !keyID.isEmpty,
      let issuer = environment["APP_STORE_CONNECT_ISSUER_ID"], !issuer.isEmpty
else { fail("Set APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID.") }

let keyURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".appstoreconnect/private_keys/AuthKey_\(keyID).p8")
guard let pem = try? String(contentsOf: keyURL, encoding: .utf8) else { fail("No API key at \(keyURL.path)") }
guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    fail("\(keyURL.path) is not an App Store Connect API key.")
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func token() -> String {
    let now = Int(Date().timeIntervalSince1970)
    let header = try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
    let claims = try! JSONSerialization.data(withJSONObject: [
        "iss": issuer, "iat": now, "exp": now + 1_200, "aud": "appstoreconnect-v1",
    ] as [String: Any])
    let unsigned = base64URL(header) + "." + base64URL(claims)
    guard let signature = try? key.signature(for: Data(unsigned.utf8)) else { fail("Could not sign the token.") }
    return unsigned + "." + base64URL(signature.rawRepresentation)
}

@discardableResult
func send(_ method: String, _ path: String, _ query: [String: String] = [:], body: [String: Any]? = nil) async -> Any? {
    var components = URLComponents(string: "https://api.appstoreconnect.apple.com\(path)")!
    if !query.isEmpty {
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.setValue("Bearer \(token())", forHTTPHeaderField: "Authorization")
    if let body {
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    guard let (data, response) = try? await URLSession.shared.data(for: request) else {
        fail("Could not reach App Store Connect.")
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        fail("\(method) \(path) answered \(status): \(String(decoding: data, as: UTF8.self))")
    }
    let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return answer?["data"]
}

func get(_ path: String, _ query: [String: String]) async -> [[String: Any]] {
    await send("GET", path, query) as? [[String: Any]] ?? []
}

let apps = await get("/v1/apps", ["filter[bundleId]": bundleID, "fields[apps]": "bundleId,primaryLocale"])
guard let appID = apps.first?["id"] as? String else { fail("App Store Connect has no app \(bundleID).") }
let primaryLocale = (apps.first?["attributes"] as? [String: Any])?["primaryLocale"] as? String ?? "en-US"

func buildNumbers(_ query: [String: String]) async -> [Int] {
    let builds = await get("/v1/builds", query.merging(["filter[app]": appID, "fields[builds]": "version"]) { $1 })
    return builds.compactMap { (($0["attributes"] as? [String: Any])?["version"] as? String).flatMap(Int.init) }
}

func projectBuildNumber() -> Int {
    let project = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Project.swift")
    let source = (try? String(contentsOf: project, encoding: .utf8)) ?? ""
    return source.firstMatch(of: #/"CURRENT_PROJECT_VERSION": "(\d+)"/#).flatMap { Int($0.1) } ?? 1
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "next":
    // By upload date and not by version, which App Store Connect sorts as text: "9" > "55".
    let latest = await buildNumbers(["sort": "-uploadedDate", "limit": "200"]).max() ?? 0
    print(max(latest + 1, projectBuildNumber()))

case "wait" where arguments.count == 2 && Int(arguments[1]) != nil:
    let number = arguments[1]
    let deadline = Date().addingTimeInterval(15 * 60)
    while Date() < deadline {
        if await !buildNumbers(["filter[version]": number]).isEmpty {
            print("Build \(number) is on App Store Connect.")
            exit(0)
        }
        try await Task.sleep(for: .seconds(30))
    }
    print("::warning::Build \(number) was uploaded but App Store Connect has not listed it yet, so the next upload could pick the same number and be refused by validation.")

case "notes" where arguments.count == 3 && Int(arguments[1]) != nil:
    let number = arguments[1]
    guard let file = try? String(contentsOfFile: arguments[2], encoding: .utf8) else { fail("Could not read \(arguments[2]).") }
    // App Store Connect refuses the whole thing over one character past 4000.
    var notes = file.trimmingCharacters(in: .whitespacesAndNewlines)
    if notes.count > 4_000 {
        notes = String(notes.prefix(4_000))
        notes = String(notes[..<(notes.lastIndex(of: "\n") ?? notes.endIndex)])
    }

    let builds = await get("/v1/builds", ["filter[app]": appID, "filter[version]": number, "fields[builds]": "version"])
    guard let buildID = builds.first?["id"] as? String else { fail("App Store Connect has no build \(number).") }
    let localizations = await get(
        "/v1/builds/\(buildID)/betaBuildLocalizations", ["fields[betaBuildLocalizations]": "locale"]
    )
    let existing = localizations.first { (($0["attributes"] as? [String: Any])?["locale"] as? String) == primaryLocale }
        ?? localizations.first
    if let id = existing?["id"] as? String {
        await send("PATCH", "/v1/betaBuildLocalizations/\(id)", body: ["data": [
            "type": "betaBuildLocalizations", "id": id, "attributes": ["whatsNew": notes],
        ]])
    } else {
        await send("POST", "/v1/betaBuildLocalizations", body: ["data": [
            "type": "betaBuildLocalizations",
            "attributes": ["locale": primaryLocale, "whatsNew": notes],
            "relationships": ["build": ["data": ["type": "builds", "id": buildID]]],
        ]])
    }
    print("Build \(number) says what to test.")

default:
    fail("usage: swift scripts/build-number.swift next | wait <number> | notes <number> <file>")
}
