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
/// names from indexed system modules (stdlib, SDK frameworks), or of the members of a container.
///
/// Clients use this list to drive a local search UI (fuzzy matching, prefix filtering, etc.)
/// without a round-trip per keystroke. After the user selects a name, send a
/// ``WorkspaceSymbolInfoRequest`` to resolve it to concrete locations.
///
/// **(LSP Extension)**
public struct WorkspaceSymbolNamesRequest: LSPRequest, Hashable {

  public static let method: String = "sourcekit/workspace/symbolNames"
  public typealias Response = WorkspaceSymbolNamesResponse

  /// When set, the response contains the fully-qualified names of the members of the container(s)
  /// named by this value instead of every symbol name in the workspace.
  ///
  /// The value may name a chain of containers separated by `.` or `::`, e.g. `Outer.Inner`. The
  /// innermost name is matched case-insensitively and exactly, and the enclosing names are matched as
  /// a suffix, so `Inner` also matches a container declared as `Outer.Inner`. Because more than one
  /// container can match, the names in the response are fully qualified.
  ///
  /// Only members are returned, never the containers themselves, and members that are only inherited
  /// are not included. A name from the response can be passed verbatim to
  /// ``WorkspaceSymbolInfoRequest``, which matches such a name exactly.
  public var containerName: String?

  public init(containerName: String? = nil) {
    self.containerName = containerName
  }
}

/// Response to a `workspace/symbolNames` request.
public struct WorkspaceSymbolNamesResponse: ResponseType {
  public var names: [String]

  public init(names: [String]) {
    self.names = names
  }
}
