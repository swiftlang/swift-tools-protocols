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

/// A reference-typed container for a single value, useful for sharing non-copyable
/// values (such as `Mutex<T>` or `Atomic<T>`) by reference — including capturing them
/// in `@Sendable` closures, which can't otherwise capture `~Copyable` types.
@_spi(SourceKitLSP) public final class RefBox<Value: ~Copyable> {
  public let value: Value

  public init(_ value: consuming Value) {
    self.value = value
  }
}

extension RefBox: Sendable where Value: ~Copyable & Sendable {}
