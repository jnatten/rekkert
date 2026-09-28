// Build numbers for TestFlight, read from App Store Connect rather than from Project.swift.
//
//     swift scripts/build-number.swift next      # the number the next upload should carry
//     swift scripts/build-number.swift wait 57   # returns once App Store Connect lists 57
//
// Needs APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and the key at
// ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 — the same three release.sh uses.
//
// `next` is one past the highest build App Store Connect has, or Project.swift's number if
// that is higher, so a number raised by hand is still honoured. `wait` is what keeps two
// uploads in a row from picking the same one: a build is not listed the moment the upload
// ends, and the next run asks for the latest as soon as it starts.
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

func get(_ path: String, _ query: [String: String]) async -> [[String: Any]] {
    var components = URLComponents(string: "https://api.appstoreconnect.apple.com\(path)")!
    components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(token())", forHTTPHeaderField: "Authorization")

    guard let (data, response) = try? await URLSession.shared.data(for: request) else {
        fail("Could not reach App Store Connect.")
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
        fail("GET \(path) answered \(status): \(String(decoding: data, as: UTF8.self))")
    }
    let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return body?["data"] as? [[String: Any]] ?? []
}

let apps = await get("/v1/apps", ["filter[bundleId]": bundleID, "fields[apps]": "bundleId"])
guard let appID = apps.first?["id"] as? String else { fail("App Store Connect has no app \(bundleID).") }

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

default:
    fail("usage: swift scripts/build-number.swift next | wait <number>")
}
