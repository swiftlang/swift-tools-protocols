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

#if canImport(os) && !SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER
@_exported public import os  // os_log

@_spi(SourceKitLSP) public typealias LogLevel = os.OSLogType
public typealias Logger = os.Logger
@_spi(SourceKitLSP) public typealias Signposter = OSSignposter

// -user-module-version of the 'os' module is 1062.100.1 in Xcode 16.3, which added the conformance of
// `OSSignpostIntervalState` to `Sendable`
#if !canImport(os, _version: 1062.100)
extension OSSignpostIntervalState: @retroactive @unchecked Sendable {}
#endif

#if compiler(>=6.4)
#warning(
  "Remove retroactive conformance of OSSignpostIntervalState to Sendable if we no longer need to support building SourceKit-LSP with SDKs from Xcode <16.3"
)
#endif

extension os.Logger {
  @_spi(SourceKitLSP) public func makeSignposter() -> Signposter {
    return OSSignposter(logger: self)
  }
}
#else
@_spi(SourceKitLSP) public typealias LogLevel = NonDarwinLogLevel
public typealias Logger = NonDarwinLogger
@_spi(SourceKitLSP) public typealias Signposter = NonDarwinSignposter
#endif

/// The logger that is used to log any messages.
@_spi(SourceKitLSP) public var logger: Logger {
  Logger(subsystem: LoggingScope.subsystem, category: LoggingScope.scope)
}
