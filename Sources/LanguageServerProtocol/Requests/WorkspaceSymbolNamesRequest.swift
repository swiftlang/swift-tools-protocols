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

/// Returns the flat, deduplicated list of every symbol name in the workspace index, including
/// names from indexed system modules (stdlib, SDK frameworks).
///
/// Clients use this list to drive a local search UI (fuzzy matching, prefix filtering, etc.)
/// without a round-trip per keystroke. After the user selects a name, send a
/// ``WorkspaceSymbolInfoRequest`` to resolve it to concrete locations.
///
/// **(LSP Extension)**
public struct WorkspaceSymbolNamesRequest: LSPRequest, Hashable {

  public static let method: String = "sourcekit/workspace/symbolNames"
  public typealias Response = WorkspaceSymbolNamesResponse

  public init() {}
}

/// Response to a `workspace/symbolNames` request.
public struct WorkspaceSymbolNamesResponse: ResponseType {
  public var names: [String]

  public init(names: [String]) {
    self.names = names
  }
}
