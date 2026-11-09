// Puts the product page header and search results images on an App Store version, which
// deliver has no field for.
//
//     swift scripts/creative-upload.swift 1.1 fastlane/creative
//
// Reads <folder>/<locale>/header.png and search.png. Each replaces the one already placed on
// that version and locale, and the image it replaces is deleted from the asset library once
// nothing uses it. They are reviewed with the version, so it has to be one you are preparing.
//
// Needs the same key as build-number.swift.
import CryptoKit
import Foundation

let bundleID = "dev.natten.rekkert"
let placementTypes = [("header.png", "PRODUCT_PAGE_HEADER_ASSET"), ("search.png", "APP_STORE_SEARCH_RESULTS_ASSET")]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else { fail("usage: swift scripts/creative-upload.swift <version> <folder>") }
let versionString = arguments[0]
let folder = URL(filePath: arguments[1])

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

typealias Resource = [String: Any]

@discardableResult
func send(_ method: String, _ path: String, _ query: [String: String] = [:], body: Resource? = nil,
          orElse: ((Int, String) -> Void)? = nil) async -> Resource {
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
        let answer = String(decoding: data, as: UTF8.self)
        guard let orElse else { fail("\(method) \(path) answered \(status): \(answer)") }
        orElse(status, answer)
        return [:]
    }
    return (try? JSONSerialization.jsonObject(with: data) as? Resource) ?? [:]
}

func list(_ path: String, _ query: [String: String] = [:]) async -> [Resource] {
    await send("GET", path, query)["data"] as? [Resource] ?? []
}

func one(_ path: String, _ query: [String: String] = [:]) async -> Resource {
    await send("GET", path, query)["data"] as? Resource ?? [:]
}

func attributes(_ resource: Resource) -> Resource { resource["attributes"] as? Resource ?? [:] }

func related(_ resource: Resource, _ name: String) -> [Resource] {
    let relationship = (resource["relationships"] as? Resource)?[name] as? Resource
    if let many = relationship?["data"] as? [Resource] { return many }
    if let single = relationship?["data"] as? Resource { return [single] }
    return []
}

func upload(_ file: URL, into library: String) async -> String {
    guard let bytes = try? Data(contentsOf: file) else { fail("Could not read \(file.path).") }
    let image = await send("POST", "/v1/appAssetLibraryImages", body: ["data": [
        "type": "appAssetLibraryImages",
        "attributes": [
            "category": "CREATIVE_ASSETS", "fileName": file.lastPathComponent, "fileSize": bytes.count,
            "referenceName": "\(versionString) \(file.deletingLastPathComponent().lastPathComponent) \(file.lastPathComponent)",
        ],
        "relationships": ["assetLibrary": ["data": ["type": "appAssetLibraries", "id": library]]],
    ]])["data"] as? Resource ?? [:]
    guard let id = image["id"] as? String else { fail("App Store Connect made no image for \(file.path).") }

    for operation in attributes(image)["uploadOperations"] as? [Resource] ?? [] {
        guard let url = (operation["url"] as? String).flatMap(URL.init(string:)),
              let offset = operation["offset"] as? Int, let length = operation["length"] as? Int
        else { fail("App Store Connect gave an upload operation with no address.") }
        var request = URLRequest(url: url)
        request.httpMethod = operation["method"] as? String ?? "PUT"
        for header in operation["requestHeaders"] as? [Resource] ?? [] {
            request.setValue(header["value"] as? String, forHTTPHeaderField: header["name"] as? String ?? "")
        }
        guard let (_, response) = try? await URLSession.shared.upload(for: request, from: bytes[offset..<offset + length]),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { fail("Could not upload \(file.path).") }
    }
    await send("PATCH", "/v1/appAssetLibraryImages/\(id)", body: ["data": [
        "type": "appAssetLibraryImages", "id": id, "attributes": ["uploaded": true],
    ]])

    // Placing it while App Store Connect is still processing it works, and the placement turns
    // active once that is done. Waiting first is what catches a file it refuses.
    let deadline = Date().addingTimeInterval(15 * 60)
    while Date() < deadline {
        let state = attributes(await one("/v1/appAssetLibraryImages/\(id)"))
        switch state["state"] as? String {
        case "AWAITING_UPLOAD", "UPLOAD_COMPLETE":
            try? await Task.sleep(for: .seconds(10))
        case "FAILED":
            fail("App Store Connect refused \(file.path): \(state["stateDetails"] ?? "no reason given")")
        default:
            return id
        }
    }
    print("    still processing after 15 minutes; placing it anyway")
    return id
}

let apps = await list("/v1/apps", ["filter[bundleId]": bundleID])
guard let appID = apps.first?["id"] as? String else { fail("App Store Connect has no app \(bundleID).") }

let versions = await list("/v1/apps/\(appID)/appStoreVersions", ["filter[platform]": "IOS", "filter[versionString]": versionString])
guard let version = versions.first, let versionID = version["id"] as? String else {
    fail("App Store Connect has no iOS version \(versionString).")
}
print("  version \(versionString), \(attributes(version)["appVersionState"] ?? attributes(version)["appStoreState"] ?? "")")

guard let library = await one("/v1/apps/\(appID)/assetLibrary")["id"] as? String else {
    fail("App Store Connect has no asset library for \(bundleID).")
}

let localizations = await list("/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations")
let locales = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
guard !locales.isEmpty else { fail("Nothing in \(folder.path) - run scripts/shots.sh --store first.") }

for locale in locales {
    guard let localization = localizations.first(where: { attributes($0)["locale"] as? String == locale }),
          let localizationID = localization["id"] as? String
    else { fail("Version \(versionString) has no \(locale) localization.") }

    for (name, placementType) in placementTypes {
        let file = folder.appending(path: locale).appending(path: name)
        guard FileManager.default.fileExists(atPath: file.path) else { continue }
        print("  \(file.path)")

        let image = await upload(file, into: library)
        let replaced = await list("/v1/appStoreVersionLocalizations/\(localizationID)/placements",
                                  ["filter[placementType]": placementType, "include": "image"])
        for placement in replaced {
            await send("DELETE", "/v1/appAssetLibraryPlacements/\(placement["id"] as! String)")
        }
        await send("POST", "/v1/appAssetLibraryPlacements", body: ["data": [
            "type": "appAssetLibraryPlacements",
            "attributes": ["placementType": placementType],
            "relationships": [
                "image": ["data": ["type": "appAssetLibraryImages", "id": image]],
                "appStoreVersionLocalization": ["data": ["type": "appStoreVersionLocalizations", "id": localizationID]],
            ],
        ]])
        print("    placed as \(placementType)")

        for old in Set(replaced.flatMap { related($0, "image") }.compactMap { $0["id"] as? String }) where old != image {
            let kept: (Int, String) -> Void = { status, _ in
                print("    kept the image it replaced, which App Store Connect would not delete (\(status))")
            }
            let found = await send("GET", "/v1/appAssetLibraryImages/\(old)", ["include": "placements"], orElse: kept)
            guard let oldImage = found["data"] as? Resource, related(oldImage, "placements").isEmpty else { continue }
            await send("DELETE", "/v1/appAssetLibraryImages/\(old)", orElse: kept)
        }
    }
}
