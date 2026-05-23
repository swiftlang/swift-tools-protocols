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

/// A wrapper around a heap-allocated `RefBox<Mutex<Value>>`, providing ergonomic
/// thread-safe access to a mutable shared state.
///
/// Compound mutations that need to be observed atomically (e.g. read-modify-write
/// on the wrapped value) must use ``withLock(_:)``; `var value`'s getter and setter
/// each take the lock independently.
@_spi(SourceKitLSP) @frozen public struct ThreadSafeBox<Value: ~Copyable>: Sendable {
  @usableFromInline let box: RefBox<Mutex<Value>>

  @inlinable public init(initialValue: consuming sending Value) {
    self.box = RefBox(Mutex(initialValue))
  }

  @inlinable public func withLock<Result, E: Error>(
    _ body: (inout sending Value) throws(E) -> sending Result
  ) throws(E) -> sending Result {
    try box.value.withLock(body)
  }
}

extension ThreadSafeBox where Value: Sendable {
  public var value: Value {
    @inlinable get { withLock { $0 } }
    @inlinable nonmutating set { withLock { $0 = newValue } }
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
