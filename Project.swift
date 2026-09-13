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
            "CURRENT_PROJECT_VERSION": "10",
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
            ]),
            sources: ["App/Sources/**", "Shared/**"],
            resources: ["App/Resources/**"],
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
            infoPlist: nil,
            sources: ["WatchApp/Sources/**", "Shared/**"],
            resources: ["WatchApp/Resources/**"],
            dependencies: [
                .package(product: "RekkertCore"),
                .package(product: "RekkertSync"),
            ],
            settings: .settings(base: [
                "GENERATE_INFOPLIST_FILE": true,
                "INFOPLIST_KEY_CFBundleDisplayName": "Rekkert",
                "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": .string(iosBundleID),
                "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": false,
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            ])
        ),
    ]
)
