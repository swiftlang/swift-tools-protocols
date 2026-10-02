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

/// Identifies a symbol in the index of a SourceKit-LSP workspace.
///
/// Stored in `CallHierarchyItem.data` and `TypeHierarchyItem.data`, and used as the input of
/// ``WorkspaceReferencesRequest``. Clients may construct it from a USR they already know.
///
/// **(LSP Extension)**
public struct SourceKitSymbolIdentifier: LSPAnyCodable, Codable, Hashable, Sendable {
  /// The USR of the symbol.
  public var usr: String

  /// Any document in the workspace whose index should be queried. Only used to select the workspace.
  public var uri: DocumentURI

  public init(usr: String, uri: DocumentURI) {
    self.usr = usr
    self.uri = uri
  }
}
