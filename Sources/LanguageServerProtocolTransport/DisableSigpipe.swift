//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

#if !os(Windows)
// This is a lazily initialised global variable that when read for the first time, will ignore SIGPIPE.
private let globallyIgnoredSIGPIPE: Bool = {
  // No F_SETNOSIGPIPE on Linux
  _ = signal(SIGPIPE, SIG_IGN)
  return true
}()
#endif

/// We receive a `SIGPIPE` if we write to a closed pipe. This can happen if the target of a `JSONRPCConnection` has
/// crashed and we try to receive/send messages, or if eg. swift-format crashes and we try to send the source file to
/// it.
///
/// Globally ignore `SIGPIPE` across platforms to prevent us from crashing in these cases. This is a no-op on Windows.
package func globallyDisableSigpipeIfNeeded() {
  #if !os(Windows)
  let haveWeIgnoredSIGPIEThisIsHereToTriggerIgnoringIt = globallyIgnoredSIGPIPE
  guard haveWeIgnoredSIGPIEThisIsHereToTriggerIgnoringIt else {
    fatalError("globallyIgnoredSIGPIPE should always be true")
  }
  #endif
}
