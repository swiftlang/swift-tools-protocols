//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public import LanguageServerProtocol
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// A request and a callback that returns the request's reply
public final class RequestAndReply<Params: RequestType>: Sendable {
  /// The request that is handled by this `RequestAndReply` object.
  public let params: Params

  /// The closure that is invoked when the `body` closure passed to `reply` terminates.
  private let reply: @Sendable (Result<Params.Response, any Error>) -> Void

  /// Whether a reply has been made. Every request must reply exactly once.
  private let replied: AtomicBool = AtomicBool(initialValue: false)

  public init(_ request: Params, reply: @escaping @Sendable (Result<Params.Response, any Error>) -> Void) {
    self.params = request
    self.reply = reply
  }

  deinit {
    precondition(replied.value, "request never received a reply")
  }

  /// Call the `replyBlock` with the result produced by the given closure.
  public func reply(_ body: () async throws -> Params.Response) async {
    let didReply = replied.setAndGet(newValue: true)
    precondition(!didReply, "replied to request more than once")
    do {
      reply(.success(try await body()))
    } catch {
      reply(.failure(error))
    }
  }
}
