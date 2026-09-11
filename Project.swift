import ProjectDescription

private let iosBundleID = "dev.natten.rekkert"

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
            "CURRENT_PROJECT_VERSION": "1",
        ]
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
            ]),
            sources: ["App/Sources/**"],
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
            sources: ["WatchApp/Sources/**"],
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
