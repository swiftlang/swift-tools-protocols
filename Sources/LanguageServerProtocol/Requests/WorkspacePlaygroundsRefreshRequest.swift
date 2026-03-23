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

/// Sent from the server to the client. Servers can use this to ask clients to
/// refresh playground list.
///
/// The server should send this when the first scanning is completed, or
/// whenever the files with playgrounds are updated and the test list has
/// changed since the last `workspace/playgrounds/refresh` request was sent.
///
/// **(LSP Extension)**
public struct WorkspacePlaygroundsRefreshRequest: LSPRequest {
  public static let method: String = "workspace/playgrounds/refresh"
  public typealias Response = VoidResponse

  public init() {}
}
