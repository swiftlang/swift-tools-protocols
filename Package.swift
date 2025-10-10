// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// Swift settings that should be applied to every Swift target.
var globalSwiftSettings: [SwiftSetting] {
  let result: [SwiftSetting] = [
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ]
  return result
}

var products: [Product] = [
  .library(name: "BuildServerProtocol", targets: ["BuildServerProtocol"]),
  .library(name: "LanguageServerProtocol", targets: ["LanguageServerProtocol"]),
  .library(name: "LanguageServerProtocolTransport", targets: ["LanguageServerProtocolTransport"]),
  .library(name: "SKLogging", targets: ["SKLogging"]),
  .library(name: "_SKLoggingForPlugin", targets: ["_SKLoggingForPlugin"]),
  .library(name: "SwiftExtensions", targets: ["SwiftExtensions"]),
  .library(name: "_SwiftExtensionsForPlugin", targets: ["_SwiftExtensionsForPlugin"]),
]

var targets: [Target] = [
  // Formatting style:
  //  - One section for each target and its test target
  //  - Sections are sorted alphabetically
  //  - Dependencies are listed on separate lines
  //  - All array elements are sorted alphabetically

  // MARK: BuildServerProtocol

  .target(
    name: "BuildServerProtocol",
    dependencies: [
      "LanguageServerProtocol"
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "BuildServerProtocolTests",
    dependencies: [
      "BuildServerProtocol",
      "LanguageServerProtocol",
      "ToolsProtocolsTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: ToolsProtocolsCAtomics

  .target(
    name: "ToolsProtocolsCAtomics",
    dependencies: []
  ),

  // MARK: LanguageServerProtocol

  .target(
    name: "LanguageServerProtocol",
    dependencies: [],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "LanguageServerProtocolTests",
    dependencies: [
      "LanguageServerProtocol",
      "ToolsProtocolsTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: LanguageServerProtocolTransport

  .target(
    name: "LanguageServerProtocolTransport",
    dependencies: [
      "BuildServerProtocol",
      "LanguageServerProtocol",
      "SKLogging",
      "SwiftExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "LanguageServerProtocolTransportTests",
    dependencies: [
      "LanguageServerProtocolTransport",
      "ToolsProtocolsTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SKLogging

  .target(
    name: "SKLogging",
    dependencies: [
      "SwiftExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings + lspLoggingSwiftSettings
  ),

  // SourceKit-LSP SPI target. Builds SKLogging with an alternate module name to avoid runtime type collisions.
  .target(
    name: "_SKLoggingForPlugin",
    dependencies: [
      "_SwiftExtensionsForPlugin"
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings + lspLoggingSwiftSettings + [
      .define("SKLOGGING_FOR_PLUGIN"),
      .unsafeFlags([
        "-module-alias", "SwiftExtensions=_SwiftExtensionsForPlugin",
      ]),
    ]
  ),

  .testTarget(
    name: "SKLoggingTests",
    dependencies: [
      "SKLogging",
      "ToolsProtocolsTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: ToolsProtocolsTestSupport

  .target(
    name: "ToolsProtocolsTestSupport",
    dependencies: [
      "LanguageServerProtocol",
      "LanguageServerProtocolTransport",
      "SKLogging",
      "SwiftExtensions",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SwiftExtensions

  .target(
    name: "SwiftExtensions",
    dependencies: ["ToolsProtocolsCAtomics"],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // SourceKit-LSP SPI target. Builds SwiftExtensions with an alternate module name to avoid runtime type collisions.
  .target(
    name: "_SwiftExtensionsForPlugin",
    dependencies: ["ToolsProtocolsCAtomics"],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SwiftExtensionsTests",
    dependencies: [
      "SKLogging",
      "ToolsProtocolsTestSupport",
      "SwiftExtensions",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: Command plugins
  .plugin(
      name: "cmake-smoke-test",
      capability: .command(intent: .custom(
          verb: "cmake-smoke-test",
          description: "Build Swift Build using CMake for validation purposes"
      ))
  ),
]

if buildOnlyTests {
  products = []
  targets = targets.compactMap { target in
    guard target.isTest || target.name.contains("TestSupport") else {
      return nil
    }
    target.dependencies = target.dependencies.filter { dependency in
      if case .byNameItem(name: let name, _) = dependency, name.contains("TestSupport") {
        return true
      }
      return false
    }
    return target
  }
}

let package = Package(
  name: "swift-tools-protocols",
  platforms: [.macOS(.v14)],
  products: products,
  dependencies: dependencies,
  targets: targets,
  swiftLanguageModes: [.v6]
)

// MARK: - Parse build arguments

func hasEnvironmentVariable(_ name: String) -> Bool {
  return ProcessInfo.processInfo.environment[name] != nil
}

/// Use the `NonDarwinLogger` even if `os_log` can be imported.
///
/// This is useful when running tests using `swift test` because xctest will not display the output from `os_log` on the
/// command line.
var forceNonDarwinLogger: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER") }

// When building the toolchain on the CI, don't add the CI's runpath for the
// final build before installing.
var installAction: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_CI_INSTALL") }

/// Assume that all the package dependencies are checked out next to sourcekit-lsp and use that instead of fetching a
/// remote dependency.
var useLocalDependencies: Bool { hasEnvironmentVariable("SWIFTCI_USE_LOCAL_DEPS") }

/// Build only tests targets and test support modules.
///
/// This is used to test swift-format on Windows, where the modules required for the `swift-format` executable are
/// built using CMake. When using this setting, the caller is responsible for passing the required search paths to
/// the `swift test` invocation so that all pre-built modules can be found.
var buildOnlyTests: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_BUILD_ONLY_TESTS") }

// MARK: - Dependencies

// When building with the swift build-script, use local dependencies whose contents are controlled
// by the external environment. This allows sourcekit-lsp to take advantage of the automation used
// for building the swift toolchain, such as `update-checkout`, or cross-repo PR tests.

var dependencies: [Package.Dependency] {
  if buildOnlyTests {
    return []
  } else if useLocalDependencies {
    return []
  } else {
    let relatedDependenciesBranch = "main"

    return [
      // Not a build dependency. Used so the "Format Source Code" command plugin can be used to format sourcekit-lsp
      .package(url: "https://github.com/swiftlang/swift-format.git", branch: relatedDependenciesBranch),
    ]
  }
}

// MARK: - Compute custom build settings

var sourcekitLSPLinkSettings: [LinkerSetting] {
  if installAction {
    return [.unsafeFlags(["-no-toolchain-stdlib-rpath"], .when(platforms: [.linux, .android]))]
  } else {
    return []
  }
}

var lspLoggingSwiftSettings: [SwiftSetting] {
  if forceNonDarwinLogger {
    return [.define("SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER")]
  } else {
    return []
  }
}
