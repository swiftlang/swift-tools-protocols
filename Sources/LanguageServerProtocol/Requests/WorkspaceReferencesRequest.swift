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

/// Request to find all references to a symbol, identified by its USR, across the workspace.
///
/// Unlike `textDocument/references`, the symbol is not looked up from a source position, so the
/// request does not require an open document. The USR can be obtained from `textDocument/symbolInfo`
/// or from the `data` of a call or type hierarchy item.
///
/// **(LSP Extension)**
public struct WorkspaceReferencesRequest: LSPRequest, Hashable {
  public static let method: String = "sourcekit/workspace/references"
  public typealias Response = [Location]

  /// The symbol to find references to.
  public var symbol: SourceKitSymbolIdentifier

  /// Whether to include the declaration and definition of the symbol. Defaults to `false`.
  public var includeDeclaration: Bool?

  public init(symbol: SourceKitSymbolIdentifier, includeDeclaration: Bool? = nil) {
    self.symbol = symbol
    self.includeDeclaration = includeDeclaration
  }
}
