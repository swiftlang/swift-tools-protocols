//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Protocol for capability registration options, which must be encodable to
/// `LSPAny` so they can be included in a `Registration`.
public protocol RegistrationOptions: Hashable, LSPAnyCodable, Codable {

}

/// General text document registration options.
public struct TextDocumentRegistrationOptions: RegistrationOptions, Hashable {
  /// A document selector to identify the scope of the registration. If not set,
  /// the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  public init(documentSelector: DocumentSelector? = nil) {
    self.documentSelector = documentSelector
  }
}

/// Protocol for a type which structurally represents`TextDocumentRegistrationOptions`.
public protocol TextDocumentRegistrationOptionsProtocol {
  var textDocumentRegistrationOptions: TextDocumentRegistrationOptions { get }
}

/// Code completiion registration options.
public struct CompletionRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var completionOptions: CompletionOptions

  public init(documentSelector: DocumentSelector? = nil, completionOptions: CompletionOptions) {
    self.textDocumentRegistrationOptions =
      TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.completionOptions = completionOptions
  }
}

/// Signature help registration options.
public struct SignatureHelpRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var signatureHelpOptions: SignatureHelpOptions

  public init(documentSelector: DocumentSelector? = nil, signatureHelpOptions: SignatureHelpOptions) {
    self.textDocumentRegistrationOptions =
      TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.signatureHelpOptions = signatureHelpOptions
  }
}

/// Folding range registration options.
public struct FoldingRangeRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var foldingRangeOptions: FoldingRangeOptions

  public init(documentSelector: DocumentSelector? = nil, foldingRangeOptions: FoldingRangeOptions) {
    self.textDocumentRegistrationOptions =
      TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.foldingRangeOptions = foldingRangeOptions
  }
}

public struct SemanticTokensRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable
{
  /// Method for registration, which defers from the actual requests' methods
  /// since this registration handles multiple requests.
  public static let method: String = "textDocument/semanticTokens"

  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var semanticTokenOptions: SemanticTokensOptions

  public init(documentSelector: DocumentSelector? = nil, semanticTokenOptions: SemanticTokensOptions) {
    self.textDocumentRegistrationOptions =
      TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.semanticTokenOptions = semanticTokenOptions
  }
}

public struct InlayHintRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var inlayHintOptions: InlayHintOptions

  public init(
    documentSelector: DocumentSelector? = nil,
    inlayHintOptions: InlayHintOptions
  ) {
    textDocumentRegistrationOptions = TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.inlayHintOptions = inlayHintOptions
  }
}

/// Describe options to be used when registering for pull diagnostics. Since LSP 3.17.0
public struct DiagnosticRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var diagnosticOptions: DiagnosticOptions

  public init(
    documentSelector: DocumentSelector? = nil,
    diagnosticOptions: DiagnosticOptions
  ) {
    textDocumentRegistrationOptions = TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.diagnosticOptions = diagnosticOptions
  }
}

/// Describe options to be used when registering for code lenses.
public struct CodeLensRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var codeLensOptions: CodeLensOptions

  public init(
    documentSelector: DocumentSelector? = nil,
    codeLensOptions: CodeLensOptions
  ) {
    textDocumentRegistrationOptions = TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.codeLensOptions = codeLensOptions
  }
}

/// Describe options to be used when registering for file system change events.
public struct DidChangeWatchedFilesRegistrationOptions: RegistrationOptions {
  /// The watchers to register.
  public var watchers: [FileSystemWatcher]

  public init(watchers: [FileSystemWatcher]) {
    self.watchers = watchers
  }
}

/// Execute command registration options.
public struct ExecuteCommandRegistrationOptions: RegistrationOptions {
  /// The commands to be executed on this server.
  public var commands: [String]

  public init(commands: [String]) {
    self.commands = commands
  }
}
