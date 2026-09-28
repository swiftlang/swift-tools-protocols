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

/// SourceKit-specific reply-level metadata carried on a Swift completion response's
/// `CompletionList.listData`.
///
/// These fields describe the whole reply rather than an individual item, so they can't live on
/// `CompletionItem`. sourcekit-lsp populates them for clients that opt in via the
/// `sourcekit-lsp.completion.extendedItems` experimental capability and omits the field entirely
/// otherwise. Every field is optional and is absent when sourcekitd didn't provide it.
public struct SourceKitCompletionListData: Codable, Hashable, Sendable {
  /// The base-expression type names of the member access being completed (sourcekitd's
  /// `key.member_access_types`). A client uses these to pick the popularity scope.
  public var memberAccessTypes: [String]?

  /// The number of completions produced before filtering (sourcekitd's `key.unfiltered_result_count`).
  public var unfilteredResultCount: Int?

  public init(memberAccessTypes: [String]? = nil, unfilteredResultCount: Int? = nil) {
    self.memberAccessTypes = memberAccessTypes
    self.unfilteredResultCount = unfilteredResultCount
  }
}
