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

/// Request to find the members of a type, identified by its USR.
///
/// Returns the members declared in the type and in its extensions. Implicit members, i.e. members
/// synthesized by the compiler or added by a macro expansion, are not included. Nested types are
/// members, but their own members are not included. The result is sorted by location.
///
/// **(LSP Extension)**
public struct WorkspaceMembersRequest: LSPRequest, Hashable {
  public static let method: String = "sourcekit/workspace/members"
  public typealias Response = [SourceKitSymbolMember]

  /// The type whose members to return.
  public var symbol: SourceKitSymbolIdentifier

  public init(symbol: SourceKitSymbolIdentifier) {
    self.symbol = symbol
  }
}
