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

/// A request that returns the location and identifiers for all the #Playground macro playgrounds within the current workspace.
///
/// **(LSP Extension)**
public struct WorkspacePlaygroundsRequest: LSPRequest, Hashable {
  public static let method: String = "workspace/playgrounds"
  public typealias Response = [Playground]

  public init() {}
}
