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

/// Returns structured location information for a list of exact symbol names.
///
/// Unlike the standard `workspace/symbol` request (which accepts a fuzzy query string),
/// this request takes exact names — typically obtained from ``WorkspaceAllSymbolNamesRequest`` —
/// and returns all index occurrences for each name across every workspace.
///
/// For each name the response contains zero or more ``WorkspaceSymbolItem`` values:
/// - Source-file symbols carry a `SymbolInformation` with a `file://` URI and the exact 0-based
///   line/column.
/// - SDK/stdlib symbols carry a `WorkspaceSymbol` with `location: .uri(...)` pointing at the
///   `file://` URI of the `.swiftinterface` or `.swiftmodule` file from the index record, with the
///   fully-qualified module name appended as a `?module=` query parameter. The symbol's USR is
///   stored in `data["usr"]`. Call `workspaceSymbol/resolve` to obtain the exact ``Location``
///   within the generated interface. The client must advertise `workspace.symbol.resolveSupport`;
///   without it, the raw `file://` URI is returned as `SymbolInformation` instead.
///
/// **(LSP Extension)**
public struct WorkspaceSymbolInfoRequest: LSPRequest, Hashable {

  public static let method: String = "sourcekit/workspace/symbolInfo"
  public typealias Response = WorkspaceSymbolInfoResponse

  /// Symbol names to match.
  public var names: [String]

  public init(names: [String]) {
    self.names = names
  }
}

/// Response to a `workspace/symbolInfo` request.
public struct WorkspaceSymbolInfoResponse: ResponseType {
  public var results: [WorkspaceSymbolItem]

  public init(results: [WorkspaceSymbolItem]) {
    self.results = results
  }
}
