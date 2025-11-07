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

/// A `TextDocumentPlayground` item can be used to identify playground and identify it
/// to allow executing the playground through a "swift play" command. Differs from `Playground`
/// by only including the `range` instead of full `location` with the expectation being that
/// it is only returned as part of a textDocument/* request such as textDocument/codelens
public struct TextDocumentPlayground: ResponseType, Equatable, LSPAnyCodable {
  /// Unique identifier for the `Playground`. Client can run the playground by executing `swift play <id>`.
  ///
  /// This property is always present whether the `Playground` has a `label` or not.
  ///
  /// Follows the format output by `swift play --list`.
  public var id: String

  /// The label that can be used as a display name for the playground. This optional property is only available
  /// for named playgrounds. For example: `#Playground("hello") { print("Hello!) }` would have a `label` of `"hello"`.
  public var label: String?

  /// The full range of the #Playground macro body in the given file.
  public var range: Range<Position>

  public init(
    id: String,
    label: String?,
    range: Range<Position>
  ) {
    self.id = id
    self.label = label
    self.range = range
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard
      case .string(let id) = dictionary["id"],
      case .dictionary(let rangeDict) = dictionary["range"],
      let range = Range<Position>(fromLSPDictionary: rangeDict)
    else {
      return nil
    }
    self.id = id
    self.range = range
    if case .string(let label) = dictionary["label"] {
      self.label = label
    }
  }

  public func encodeToLSPAny() -> LSPAny {
    var dict: [String: LSPAny] = [
      "id": .string(id),
      "range": range.encodeToLSPAny(),
    ]
    if let label {
      dict["label"] = .string(label)
    }
    return .dictionary(dict)
  }
}
