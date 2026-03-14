// swift-tools-version:6.1

import CompilerPluginSupport
import PackageDescription

let android = Context.environment["TARGET_OS_ANDROID"] ?? "0" != "0"

let package = Package(
  name: "swift-composable-architecture",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v16),
    .watchOS(.v9),
  ],
  products: [
    .library(
      name: "ComposableArchitecture",
      targets: ["ComposableArchitecture"]
    )
  ],
  traits: [
    .trait(
      name: "ComposableArchitecture2Deprecations",
      description: """
        Prepare for the next major release by enabling some of the more viral deprecations.
        """
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
    .package(path: "../combine-schedulers"),
    .package(path: "../swift-case-paths"),
    .package(path: "../swift-clocks"),
    .package(path: "../swift-concurrency-extras"),
    .package(path: "../swift-custom-dump"),
    .package(path: "../swift-dependencies"),
    .package(path: "../swift-identified-collections"),
    .package(path: "../swift-macro-testing"),
    .package(path: "../swift-navigation"),
    .package(path: "../swift-perception"),
    .package(path: "../swift-sharing"),
    .package(path: "../xctest-dynamic-overlay"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"603.0.0"),
  ]
    + (android ? [
      .package(url: "https://source.skip.tools/skip-bridge.git", "0.16.4"..<"2.0.0"),
      .package(path: "../skip-android-bridge"),
      .package(url: "https://source.skip.tools/swift-jni.git", "0.3.1"..<"2.0.0"),
      .package(path: "../skip-fuse-ui"),
    ] : []),
  targets: [
    .target(
      name: "ComposableArchitecture",
      dependencies: [
        "ComposableArchitectureMacros",
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "CombineSchedulers", package: "combine-schedulers"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "OpenCombineShim", package: "OpenCombine"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "Perception", package: "swift-perception"),
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
      ]
        + (android
          ? [
            .product(name: "SkipBridge", package: "skip-bridge"),
            .product(name: "SkipAndroidBridge", package: "skip-android-bridge"),
            .product(name: "SwiftJNI", package: "swift-jni"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
          ]
          : [.product(name: "UIKitNavigation", package: "swift-navigation")]),
      resources: [
        .process("Resources/PrivacyInfo.xcprivacy")
      ]
    ),
    .testTarget(
      name: "ComposableArchitectureTests",
      dependencies: [
        "ComposableArchitecture",
        .product(name: "IssueReportingTestSupport", package: "xctest-dynamic-overlay"),
        .product(name: "OpenCombineShim", package: "OpenCombine"),
      ]
    ),
    .macro(
      name: "ComposableArchitectureMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "ComposableArchitectureMacrosTests",
      dependencies: [
        "ComposableArchitectureMacros",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)

for target in package.targets {
  target.swiftSettings = target.swiftSettings ?? []
  target.swiftSettings?.append(contentsOf: [
    .enableUpcomingFeature("ExistentialAny")
  ])
}

for target in package.targets where target.type == .system || target.type == .test {
  target.swiftSettings?.append(contentsOf: [
    .swiftLanguageMode(.v5),
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
  ])
}
