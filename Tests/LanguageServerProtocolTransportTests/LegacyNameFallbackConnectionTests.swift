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

import LanguageServerProtocol
import LanguageServerProtocolTransport
import Testing

// MARK: - Fixture request types

private struct NoLegacyRequest: RequestType {
  static let method = "sourcekit/noLegacy"
  typealias Response = VoidResponse
}

private struct WithLegacyRequest: RequestType {
  static let method = "sourcekit/one"
  typealias Response = VoidResponse
}

private let testLegacyNames: [String: String] = [
  WithLegacyRequest.method: "sourcekit-lsp/one"
]

// MARK: - Mock connection

/// A controllable `Connection` for unit tests.
///
/// Calls are recorded in `calls`. `responses` maps method names to explicit
/// results; any method not in the dictionary defaults to `.methodNotFound`.
private final class MockConnection: Connection, @unchecked Sendable {
  struct Call: Equatable {
    var method: String
    var id: RequestID
  }

  var calls: [Call] = []
  var responses: [String: LSPResult<VoidResponse>] = [:]
  private var nextIDValue: Int = 0

  func nextRequestID() -> RequestID {
    nextIDValue += 1
    return .number(nextIDValue)
  }

  func send(_ notification: some NotificationType) {}

  func send<Request: RequestType>(
    _ request: Request,
    method: String,
    id: RequestID,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) {
    calls.append(Call(method: method, id: id))
    let voidResult = responses[method] ?? .failure(.methodNotFound(method))
    switch voidResult {
    case .failure(let error):
      reply(.failure(error))
    case .success(let voidResponse):
      if let response = voidResponse as? Request.Response {
        reply(.success(response))
      } else {
        reply(.failure(.internalError("MockConnection: unsupported response type")))
      }
    }
  }
}

// MARK: - Tests

@Suite struct LegacyNameFallbackConnectionTests {

  // No legacyName: pass through regardless of the reply – no retries, flag never set.
  @Test func testNoLegacyMethods_passesThroughWithoutRetry() async {
    let mock = MockConnection()  // "sourcekit/noLegacy" → methodNotFound (default)
    let conn = LegacyNameFallbackConnection(mock, legacyNames: testLegacyNames)

    let error = await #expect(throws: ResponseError.self) {
      try await conn.send(NoLegacyRequest())
    }
    #expect(error?.code == .methodNotFound)
    #expect(mock.calls.count == 1)
    #expect(mock.calls[0].method == "sourcekit/noLegacy")

    // Confirm the flag was NOT set: a fresh send still uses the primary name.
    mock.calls.removeAll()
    _ = try? await conn.send(NoLegacyRequest())
    #expect(mock.calls.count == 1)
    #expect(mock.calls[0].method == "sourcekit/noLegacy")
  }

  // Primary method succeeds: no fallback, flag stays false.
  @Test func testSuccess_neverRetries() async throws {
    let mock = MockConnection()
    mock.responses["sourcekit/one"] = .success(VoidResponse())
    let conn = LegacyNameFallbackConnection(mock, legacyNames: testLegacyNames)

    _ = try await conn.send(WithLegacyRequest())

    #expect(mock.calls.count == 1)
    #expect(mock.calls[0].method == "sourcekit/one")
  }

  // Primary returns methodNotFound: falls back to the single legacy name.
  @Test func testMethodNotFound_retriesOneLegacy() async throws {
    // "sourcekit/one" not in responses → methodNotFound; legacy succeeds.
    let mock = MockConnection()
    mock.responses["sourcekit-lsp/one"] = .success(VoidResponse())
    let conn = LegacyNameFallbackConnection(mock, legacyNames: testLegacyNames)

    _ = try await conn.send(WithLegacyRequest())

    #expect(mock.calls.count == 2)
    #expect(mock.calls[0].method == "sourcekit/one")
    #expect(mock.calls[1].method == "sourcekit-lsp/one")
  }

  // Both primary and legacy return methodNotFound: error is propagated, flag stays false.
  @Test func testLegacyMethodNotFound_returnsError() async {
    let mock = MockConnection()  // all methods default to methodNotFound
    let conn = LegacyNameFallbackConnection(mock, legacyNames: testLegacyNames)

    let error = await #expect(throws: ResponseError.self) {
      try await conn.send(WithLegacyRequest())
    }
    #expect(error?.code == .methodNotFound)
    #expect(mock.calls.count == 2)

    // Flag should NOT have been set: next request still tries the primary first.
    mock.calls.removeAll()
    _ = try? await conn.send(WithLegacyRequest())
    #expect(mock.calls.count == 2)
    #expect(mock.calls[0].method == "sourcekit/one")
    #expect(mock.calls[1].method == "sourcekit-lsp/one")
  }

  // After the flag is set, subsequent requests skip the primary method entirely.
  @Test func testFlagSticksAfterFirstMethodNotFound() async throws {
    let mock = MockConnection()
    mock.responses["sourcekit-lsp/one"] = .success(VoidResponse())
    let conn = LegacyNameFallbackConnection(mock, legacyNames: testLegacyNames)

    // First request: triggers flag.
    _ = try await conn.send(WithLegacyRequest())
    #expect(mock.calls.count == 2)

    // Second request: should go directly to legacy name, bypassing the primary.
    mock.calls.removeAll()
    _ = try await conn.send(WithLegacyRequest())

    #expect(mock.calls.count == 1)
    #expect(mock.calls[0].method == "sourcekit-lsp/one")
  }

  // A non-methodNotFound error does not flip the flag; the next request still tries primary first.
  @Test func testNonMethodNotFoundError_doesNotFlipFlag() async {
    let mock = MockConnection()
    mock.responses["sourcekit/one"] = .failure(.internalError("unexpected error"))
    let conn = LegacyNameFallbackConnection(mock, legacyNames: testLegacyNames)

    let error = await #expect(throws: ResponseError.self) {
      try await conn.send(WithLegacyRequest())
    }
    #expect(error?.code == .internalError)
    #expect(mock.calls.count == 1)
    #expect(mock.calls[0].method == "sourcekit/one")

    // Flag should NOT have been set: next request still tries the primary method.
    mock.responses["sourcekit/one"] = .success(VoidResponse())
    mock.calls.removeAll()
    _ = try? await conn.send(WithLegacyRequest())
    #expect(mock.calls.count == 1)
    #expect(mock.calls[0].method == "sourcekit/one")
  }

  // Notifications are forwarded to the inner connection unchanged.
  @Test func testNotification_forwardedToInner() {
    let mock = MockConnection()
    let conn = LegacyNameFallbackConnection(mock, legacyNames: testLegacyNames)
    conn.send(CancelRequestNotification(id: .number(42)))
    // Notifications don't appear in `calls`; just ensure it doesn't crash.
  }
}
