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

/// A member of a type, returned by ``WorkspaceMembersRequest``.
///
/// **(LSP Extension)**
public struct SourceKitSymbolMember: ResponseType, Codable, Hashable, Sendable {
  /// The member's name, e.g. `foo(x:)`.
  public var name: String

  public var kind: SymbolKind

  /// The member's primary definition or declaration.
  public var location: Location

  /// Identifies the member for further queries.
  public var symbol: SourceKitSymbolIdentifier

  /// Tags for this member, e.g. whether it is a `static` or `class` member.
  public var tags: [SourceKitSymbolTag]?

  public init(
    name: String,
    kind: SymbolKind,
    location: Location,
    symbol: SourceKitSymbolIdentifier,
    tags: [SourceKitSymbolTag]? = nil
  ) {
    self.name = name
    self.kind = kind
    self.location = location
    self.symbol = symbol
    self.tags = tags
  }
}
