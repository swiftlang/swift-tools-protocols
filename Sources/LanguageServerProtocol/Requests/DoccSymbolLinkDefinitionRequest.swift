//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request that resolves a DocC symbol link to the location of the symbol it refers to
/// **(LSP Extension)**.
///
/// Primarily designed to support jump-to-definition when a symbol link is clicked within the live
/// preview of Swift documentation in editors.
///
/// This request takes a DocC symbol link string (e.g. `"Foo/bar(_:)"`) along with the document it was
/// clicked in and resolves it via the index to the location of the symbol's definition or declaration.
///
/// Resolution can fail for a number of reasons, most commonly because the symbol link could not be
/// parsed, or because no matching symbol could be found in the index. In such cases the request
/// returns `nil` rather than failing, since a symbol link not resolving is an expected outcome that
/// the live preview editor can display to the user (e.g. "Symbol link could not be resolved" or
/// "Symbol not found"), not a failure of the request itself.
///
/// At the moment this request is only available on macOS and Linux. SourceKit-LSP will advertise
/// `textDocument/doccSymbolLinkDefinition` in its experimental server capabilities if it supports it.
///
/// - Parameters:
///   - textDocument: The document the symbol link was clicked in, used to resolve the link relative
///     to the correct workspace and index.
///   - symbolLink: The DocC symbol link to resolve.
///
/// - Returns: The `Location` of the symbol's definition or declaration, or `nil` if the symbol link
///   could not be parsed or no matching symbol was found in the index.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP.
/// The client is expected to navigate to the returned location, or display an appropriate error
/// message to the user if the response is `nil`.
public struct DocCSymbolLinkDefinitionRequest: TextDocumentRequest, Hashable {
  public static let method: String = "sourcekit/textDocument/doccSymbolLinkDefinition"
  public typealias Response = LocationsOrLocationLinksResponse?

  /// The document the symbol link was clicked in.
  public var textDocument: TextDocumentIdentifier

  /// The DocC symbol link to resolve.
  public var symbolLink: String

  public init(textDocument: TextDocumentIdentifier, symbolLink: String) {
    self.textDocument = textDocument
    self.symbolLink = symbolLink
  }
}
