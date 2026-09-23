import ProjectDescription

private let iosBundleID = "dev.natten.rekkert"

/// Set `TUIST_DEVELOPMENT_TEAM` to run on a real iPhone and Apple Watch. Simulator builds
/// need no team, so it stays unset by default. Put it in a gitignored `mise.local.toml`:
///
///     [env]
///     TUIST_DEVELOPMENT_TEAM = "ABCDE12345"
private let developmentTeam = Environment.developmentTeam.getString(default: "")

private var signingSettings: SettingsDictionary {
    developmentTeam.isEmpty ? [:] : ["DEVELOPMENT_TEAM": .string(developmentTeam)]
}

let project = Project(
    name: "Rekkert",
    organizationName: "natten.dev",
    packages: [.package(path: "Packages/RekkertKit")],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
            "SWIFT_STRICT_MEMORY_SAFETY": "NO",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "CODE_SIGN_STYLE": "Automatic",
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "51",
        ].merging(signingSettings) { _, signing in signing }
    ),
    targets: [
        .target(
            name: "Rekkert",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: iosBundleID,
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "Rekkert",
                // Tuist's default plist hard-codes these, which would pin the app at 1.0 (1)
                // however the build settings are set.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                // Sharing a match with the other phones at the court. Bonjour over
                // Network.framework needs no entitlement — the multicast one is for raw
                // sockets and is request-only from Apple.
                "NSLocalNetworkUsageDescription":
                    "Rekkert finds the other phones at your court, so everyone can follow and score the same match.",
                "NSBonjourServices": ["_rekkert-score._tcp"],
                // The local network is the better link by every measure except the one that
                // decides a match: the system takes it away when the app stops being in front
                // of somebody, so a phone in a pocket stops carrying the score. Bluetooth is
                // the only link iOS will let an app hold open with the screen off, and both
                // halves are needed — a host advertises and a guest scans.
                "UIBackgroundModes": ["bluetooth-central", "bluetooth-peripheral"],
                "NSBluetoothAlwaysUsageDescription":
                    "Rekkert keeps the score in step with the other phones at your court, even while your phone is locked in a bag.",
                // Declared up front so App Store Connect stops asking on every upload. The
                // only cryptography here is Apple's own — TLS from Security.framework, and
                // HKDF and ChaChaPoly from CryptoKit — which is exempt.
                "ITSAppUsesNonExemptEncryption": false,
                // Recording a workout is the watch's job; the phone only asks it to start
                // one and is told when it does. It never reads a workout back out of Health
                // — it keeps its own copy of the summary — but the sheet the button puts up
                // belongs on the device the button is on.
                "NSHealthShareUsageDescription":
                    "Rekkert shows the heart rate your Apple Watch reads while you play.",
                "NSHealthUpdateUsageDescription":
                    "Rekkert saves the session your Apple Watch records as a workout in Health.",
            ]),
            sources: ["App/Sources/**", "Shared/**"],
            resources: ["App/Resources/**"],
            entitlements: .dictionary(["com.apple.developer.healthkit": true]),
            dependencies: [
                .package(product: "RekkertCore"),
                .package(product: "RekkertSync"),
                .target(name: "RekkertWatch"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            ])
        ),
        .target(
            name: "RekkertWatch",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "\(iosBundleID).watchkitapp",
            deploymentTargets: .watchOS("26.0"),
            // Spelled out rather than generated. `WKBackgroundModes` is an array and has no
            // `INFOPLIST_KEY_` of its own, so the generator cannot express it — and mixing a
            // generated plist with a real one relies on merge behaviour that has moved
            // between Xcode versions. Every key the generator was supplying is stated here,
            // and `scripts/verify.sh` asserts the load-bearing ones survived.
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Rekkert",
                // As on the iPhone target: Tuist's default hard-codes these, which would pin
                // the watch app at 1.0 (1) while the phone moves on — a pair App Store
                // Connect rejects.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                // Not in Tuist's watch default: it came from the generator. Without it the
                // watch app does not install at all.
                "WKApplication": true,
                "WKCompanionAppBundleIdentifier": .string(iosBundleID),
                "WKRunsIndependentlyOfCompanionApp": false,
                // The reason this target has a plist at all. Without it watchOS suspends the
                // app the moment the wrist drops, and the workout stops collecting.
                "WKBackgroundModes": ["workout-processing"],
                "NSHealthShareUsageDescription":
                    "Rekkert reads your heart rate and energy while a workout you started is running, and your age and resting rate to place that heart rate in a zone.",
                "NSHealthUpdateUsageDescription":
                    "Rekkert saves what you played as a tennis workout in Health.",
            ]),
            sources: ["WatchApp/Sources/**", "Shared/**"],
            resources: ["WatchApp/Resources/**"],
            entitlements: .dictionary(["com.apple.developer.healthkit": true]),
            dependencies: [
                .package(product: "RekkertCore"),
                .package(product: "RekkertSync"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            ])
        ),
    ]
)
