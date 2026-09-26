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

  public init(
    module: String? = nil,
    groupID: Int? = nil,
    isSystem: Bool? = nil,
    hasDiagnostic: Bool? = nil,
    annotatedDescription: String? = nil,
    annotatedTypeName: String? = nil
  ) {
    self.module = module
    self.groupID = groupID
    self.isSystem = isSystem
    self.hasDiagnostic = hasDiagnostic
    self.annotatedDescription = annotatedDescription
    self.annotatedTypeName = annotatedTypeName
  }
}
