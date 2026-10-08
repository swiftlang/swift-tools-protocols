//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A SourceKit-LSP-specific tag on a symbol.
///
/// Clients must ignore tags they don't know.
///
/// **(LSP Extension)**
public struct SourceKitSymbolTag: RawRepresentable, Codable, Hashable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// A type member declared `static`, such as a Swift `static` member or a C++ static member.
  public static let `static` = SourceKitSymbolTag(rawValue: "static")

  /// A type member declared `class`, such as a Swift `class` member or an Objective-C class method.
  public static let `class` = SourceKitSymbolTag(rawValue: "class")
}
