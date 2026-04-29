//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public final class MessageRegistry: Sendable {
  private let methodToRequest: [String: _RequestType.Type]
  private let methodToNotification: [String: NotificationType.Type]

  public init(
    requests: [_RequestType.Type],
    notifications: [NotificationType.Type],
    legacyNames: [String: String] = [:]
  ) {
    var methodToRequest: [String: _RequestType.Type] = Dictionary(
      uniqueKeysWithValues: requests.map { ($0.method, $0) }
    )
    for request in requests {
      if let legacy = legacyNames[request.method] { methodToRequest[legacy] = request }
    }
    self.methodToRequest = methodToRequest

    var methodToNotification: [String: NotificationType.Type] = Dictionary(
      uniqueKeysWithValues: notifications.map { ($0.method, $0) }
    )
    for notification in notifications {
      if let legacy = legacyNames[notification.method] { methodToNotification[legacy] = notification }
    }
    self.methodToNotification = methodToNotification
  }

  /// Returns the type of the message named `method`, or nil if it is unknown.
  public func requestType(for method: String) -> _RequestType.Type? {
    return methodToRequest[method]
  }

  /// Returns the type of the message named `method`, or nil if it is unknown.
  public func notificationType(for method: String) -> NotificationType.Type? {
    return methodToNotification[method]
  }

}
