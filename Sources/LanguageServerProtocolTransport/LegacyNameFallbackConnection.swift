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

public import LanguageServerProtocol
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// A `Connection` wrapper that retries requests using a legacy method name when the peer
/// responds with `methodNotFound` for a `sourcekit/`-prefixed method.
///
/// On the first successful response to a legacy name the wrapper sets a flag and from that
/// point on sends requests with the legacy name directly, skipping the primary method.
///
/// Pass `MessageRegistry.lspLegacyNames` or `MessageRegistry.bspLegacyNames` as `legacyNames`
/// as appropriate.
public final class LegacyNameFallbackConnection: Connection, Sendable {
  /// The underlying transport connection.
  public let inner: any Connection

  /// Maps current method names to legacy names (new → old).
  private let legacyNames: [String: String]

  /// Set to `true` once the peer successfully responds to a legacy method name,
  /// after which requests that have a legacy name are sent using that name directly.
  private let prefersLegacyMethodNames: AtomicBool = .init(initialValue: false)

  public init(_ inner: any Connection, legacyNames: [String: String]) {
    self.inner = inner
    self.legacyNames = legacyNames
  }

  public func nextRequestID() -> RequestID {
    inner.nextRequestID()
  }

  public func send(_ notification: some NotificationType) {
    inner.send(notification)
  }

  public func send<R: RequestType>(
    _ request: R,
    method: String,
    id: RequestID,
    reply: @escaping @Sendable (LSPResult<R.Response>) -> Void
  ) {
    guard let legacyName = legacyNames[method] else {
      inner.send(request, method: method, id: id, reply: reply)
      return
    }
    if prefersLegacyMethodNames.value {
      inner.send(request, method: legacyName, id: id, reply: reply)
      return
    }
    inner.send(request, method: method, id: id) { [weak self] result in
      guard let self else {
        reply(result)
        return
      }
      if case .failure(let error) = result, error.code == .methodNotFound {
        self.inner.send(request, method: legacyName, id: self.inner.nextRequestID()) { [weak self] legacyResult in
          if case .success = legacyResult {
            self?.prefersLegacyMethodNames.value = true
          }
          reply(legacyResult)
        }
      } else {
        reply(result)
      }
    }
  }

  /// Forward to the inner `JSONRPCConnection.changeReceiveHandler` if the inner connection is a
  /// `JSONRPCConnection`. No-op for other connection types.
  public func changeReceiveHandler(_ handler: any MessageHandler) {
    (inner as? JSONRPCConnection)?.changeReceiveHandler(handler)
  }
}
