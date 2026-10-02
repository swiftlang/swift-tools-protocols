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

/// SourceKit-specific per-item metadata carried on a Swift `CompletionItem`'s `data`.
///
/// sourcekit-lsp populates these fields for clients that opt in via the
/// `sourcekit-lsp.completion.extendedItems` experimental capability, letting a client recover the
/// completion detail that sourcekitd exposes but that plain LSP `CompletionItem` fields don't carry.
/// Every field is optional and is absent when sourcekitd didn't provide it.
///
/// It is encoded flat alongside sourcekit-lsp's completion-item resolve data, so a client can decode it
/// straight from `CompletionItem.data` with `SourceKitCompletionItemData(fromLSPAny:)`.
public struct SourceKitCompletionItemData: Codable, LSPAnyCodable, Hashable, Sendable {
  /// The module that defines the completion (sourcekitd's `key.modulename`).
  public var module: String?

  /// Groups overloads of the same declaration (sourcekitd's `key.group_id`).
  public var groupID: Int?

  /// Whether the completion comes from a system module (sourcekitd's `key.is_system`).
  public var isSystem: Bool?

  /// Whether the completion has an associated diagnostic (sourcekitd's `key.has_diagnostic`).
  public var hasDiagnostic: Bool?

  /// The annotated-description XML for the completion's label, as produced by sourcekitd.
  public var annotatedDescription: String?

  /// The annotated-description XML for the completion's type name, as produced by sourcekitd.
  public var annotatedTypeName: String?

  /// The completion's semantic score, used for ranking (sourcekitd's `key.semantic_score`).
  public var semanticScore: Double?

  /// The USRs associated with the completion (sourcekitd's `key.associated_usrs`), populated during resolve.
  public var associatedUSRs: [String]?

  /// The completion's brief documentation (sourcekitd's `key.doc.brief`), populated during resolve.
  public var docBrief: String?

  /// The completion's full doc-comment XML (sourcekitd's `key.doc.full_as_xml`), populated during resolve.
  public var docFullAsXML: String?

  /// The diagnostic associated with the completion, if any, populated during resolve when `hasDiagnostic` is set.
  public var diagnostic: Diagnostic?

  public init(
    module: String? = nil,
    groupID: Int? = nil,
    isSystem: Bool? = nil,
    hasDiagnostic: Bool? = nil,
    annotatedDescription: String? = nil,
    annotatedTypeName: String? = nil,
    semanticScore: Double? = nil,
    associatedUSRs: [String]? = nil,
    docBrief: String? = nil,
    docFullAsXML: String? = nil,
    diagnostic: Diagnostic? = nil
  ) {
    self.module = module
    self.groupID = groupID
    self.isSystem = isSystem
    self.hasDiagnostic = hasDiagnostic
    self.annotatedDescription = annotatedDescription
    self.annotatedTypeName = annotatedTypeName
    self.semanticScore = semanticScore
    self.associatedUSRs = associatedUSRs
    self.docBrief = docBrief
    self.docFullAsXML = docFullAsXML
    self.diagnostic = diagnostic
  }
}

extension SourceKitCompletionItemData {
  /// A diagnostic produced for a completion item, such as a deprecation warning.
  public struct Diagnostic: Codable, Hashable, Sendable {
    /// The severity of the diagnostic.
    public var severity: DiagnosticSeverity?

    /// The diagnostic message.
    public var message: String

    public init(severity: DiagnosticSeverity? = nil, message: String) {
      self.severity = severity
      self.message = message
    }
  }
}
