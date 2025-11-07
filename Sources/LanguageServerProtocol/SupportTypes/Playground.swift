//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A `Playground` represents a usage of the #Playground macro, providing the editor with the
/// location of the playground and identifiers to allow executing the playground through a "swift play" command.
///
/// **(LSP Extension)**
public struct Playground: ResponseType, Equatable, LSPAnyCodable {
  /// Unique identifier for the `Playground`. Client can run the playground by executing `swift play <id>`.
  ///
  /// This property is always present whether the `Playground` has a `label` or not.
  ///
  /// Follows the format output by `swift play --list`.
  public var id: String

  /// The label that can be used as a display name for the playground. This optional property is only available
  /// for named playgrounds. For example: `#Playground("hello") { print("Hello!) }` would have a `label` of `"hello"`.
  public var label: String?

  /// The location of where the #Playground macro was used in the source code.
  public var location: Location

  public init(
    id: String,
    label: String?,
    location: Location,
  ) {
    self.id = id
    self.label = label
    self.location = location
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard
      case .string(let id) = dictionary["id"],
      case .dictionary(let locationDict) = dictionary["location"],
      let location = Location(fromLSPDictionary: locationDict)
    else {
      return nil
    }
    self.id = id
    self.location = location
    if case .string(let label) = dictionary["label"] {
      self.label = label
    }
  }

  public func encodeToLSPAny() -> LSPAny {
    var dict: [String: LSPAny] = [
      "id": .string(id),
      "location": location.encodeToLSPAny(),
    ]

    if let label {
      dict["label"] = .string(label)
    }

    return .dictionary(dict)
  }
}
