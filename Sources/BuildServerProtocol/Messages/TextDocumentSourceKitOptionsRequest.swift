//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public import LanguageServerProtocol

/// The purpose a `TextDocumentSourceKitOptionsRequest` is being made for, so the build server can tailor the
/// returned settings to the consumer.
@frozen public enum SourceKitOptionsPurpose: String, Hashable, Codable, Sendable {
  /// The options are requested to drive live editor functionality (completion, diagnostics, etc.).
  case editor
  /// The options are requested to drive a background index build.
  case index
}

/// The `TextDocumentSourceKitOptionsRequest` request is sent from the client to the server to query for the list of
/// compiler options necessary to compile this file in the given target.
///
/// The build settings are considered up-to-date and can be cached by SourceKit-LSP until a
/// `DidChangeBuildTargetNotification` is sent for the requested target.
///
/// The request may return `nil` if it doesn't have any build settings for this file in the given target.
public struct TextDocumentSourceKitOptionsRequest: BSPRequest, Hashable {
  public static let method: String = "sourcekit/textDocument/sourceKitOptions"
  public typealias Response = TextDocumentSourceKitOptionsResponse?

  /// The URI of the document to get options for
  public var textDocument: TextDocumentIdentifier

  /// The target for which the build setting should be returned.
  ///
  /// A source file might be part of multiple targets and might have different compiler arguments in those two targets,
  /// thus the target is necessary in this request.
  public var target: BuildTargetIdentifier

  /// The language with which the document was opened in the editor.
  public var language: Language

  /// The purpose of the request. `nil` when sent by a client that predates this field; the server then treats it as
  /// `.editor`, so explicit-built-module inputs are only grafted for requests that explicitly ask for `.index`.
  public var purpose: SourceKitOptionsPurpose?

  public init(
    textDocument: TextDocumentIdentifier,
    target: BuildTargetIdentifier,
    language: Language,
    purpose: SourceKitOptionsPurpose? = nil
  ) {
    self.textDocument = textDocument
    self.target = target
    self.language = language
    self.purpose = purpose
  }
}

public struct TextDocumentSourceKitOptionsResponse: ResponseType, Hashable {
  /// The compiler options required for the requested file.
  public var compilerArguments: [String]

  /// The working directory for the compile command.
  public var workingDirectory: String?

  /// Additional data that will not be interpreted by SourceKit-LSP but made available to clients in the
  /// `workspace/_sourceKitOptions` LSP requests.
  public var data: LSPAny?

  public init(compilerArguments: [String], workingDirectory: String? = nil, data: LSPAny? = nil) {
    self.compilerArguments = compilerArguments
    self.workingDirectory = workingDirectory
    self.data = data
  }
}
