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

public import Synchronization

/// A heap-allocated `Mutex<Value>` wrapper providing ergonomic thread-safe
/// access to a mutable shared state.
///
/// `var value` is read-only. Writes must go through ``withLock(_:)`` so that
/// read-modify-write patterns (e.g. `+=`, `append`) hold the lock for the
/// entire operation rather than acquiring it twice.
@_spi(SourceKitLSP) public final class ThreadSafeBox<Value: ~Copyable>: Sendable {
  @usableFromInline let mtx: Mutex<Value>

  @inlinable public init(initialValue: consuming sending Value) {
    self.mtx = Mutex(initialValue)
  }

  @inlinable public func withLock<Result: ~Copyable, E: Error>(
    _ body: (inout sending Value) throws(E) -> sending Result
  ) throws(E) -> sending Result {
    try mtx.withLock(body)
  }
}

extension ThreadSafeBox where Value: Sendable {
  /// Atomically reads the wrapped value. Writes must go through ``withLock(_:)``.
  @inlinable public var value: Value {
    withLock { $0 }
  }
}

extension ThreadSafeBox {
  /// Atomically reads the wrapped optional value and resets it to `nil`.
  @inlinable public func takeValue<Wrapped>() -> sending Wrapped? where Value == Wrapped? {
    withLock { state in
      // Don't use `Optional.take()` because the compiler can't see through `take()`
      // to prove the returned value is disjoint from `state`.
      let result = state
      state = nil
      return result
    }
  }
}
