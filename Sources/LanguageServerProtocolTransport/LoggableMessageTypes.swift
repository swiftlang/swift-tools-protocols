//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
public import LanguageServerProtocol
@_spi(SourceKitLSP) public import SKLogging

// MARK: - RequestType

@_spi(SourceKitLSP) public struct AnyRequestType: CustomLogStringConvertible {
  let request: any RequestType

  @_spi(SourceKitLSP) public init(request: any RequestType) {
    self.request = request
  }

  @_spi(SourceKitLSP) public var description: String {
    return """
      \(type(of: request).method)
      \(request.prettyPrintedJSON)
      """
  }

  @_spi(SourceKitLSP) public var redactedDescription: String {
    return """
      \(type(of: request).method)
      \(request.prettyPrintedRedactedJSON)
      """
  }
}

extension RequestType {
  @_spi(SourceKitLSP) public var forLogging: CustomLogStringConvertibleWrapper {
    return AnyRequestType(request: self).forLogging
  }
}

// MARK: - NotificationType

@_spi(SourceKitLSP) public struct AnyNotificationType: CustomLogStringConvertible {
  let notification: any NotificationType

  @_spi(SourceKitLSP) public init(notification: any NotificationType) {
    self.notification = notification
  }

  @_spi(SourceKitLSP) public var description: String {
    return """
      \(type(of: notification).method)
      \(notification.prettyPrintedJSON)
      """
  }

  @_spi(SourceKitLSP) public var redactedDescription: String {
    return """
      \(type(of: notification).method)
      \(notification.prettyPrintedRedactedJSON)
      """
  }
}

extension NotificationType {
  @_spi(SourceKitLSP) public var forLogging: CustomLogStringConvertibleWrapper {
    return AnyNotificationType(notification: self).forLogging
  }
}

// MARK: - ResponseType

@_spi(SourceKitLSP) public struct AnyResponseType: CustomLogStringConvertible {
  let response: any ResponseType

  @_spi(SourceKitLSP) public init(response: any ResponseType) {
    self.response = response
  }

  @_spi(SourceKitLSP) public var description: String {
    return """
      \(type(of: response))
      \(response.prettyPrintedJSON)
      """
  }

  @_spi(SourceKitLSP) public var redactedDescription: String {
    return """
      \(type(of: response))
      \(response.prettyPrintedRedactedJSON)
      """
  }
}

extension ResponseType {
  @_spi(SourceKitLSP) public var forLogging: CustomLogStringConvertibleWrapper {
    return AnyResponseType(response: self).forLogging
  }
}
