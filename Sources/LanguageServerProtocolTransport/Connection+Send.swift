//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public import LanguageServerProtocol
@_spi(SourceKitLSP) private import ToolsProtocolsSwiftExtensions

extension Connection {
  public func send<R: RequestType>(_ request: R, method: String = R.method) async throws -> R.Response {
    return try await withCancellableCheckedThrowingContinuation { continuation in
      let id = self.nextRequestID()
      self.send(request, method: method, id: id) { result in
        continuation.resume(with: result)
      }
      return id
    } cancel: { requestID in
      self.send(CancelRequestNotification(id: requestID))
    }
  }
}
