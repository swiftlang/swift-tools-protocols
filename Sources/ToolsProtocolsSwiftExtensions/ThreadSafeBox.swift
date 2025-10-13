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

/// A thread safe container that contains a value of type `T`.
///
/// - Note: Unchecked sendable conformance because value is guarded by a lock.
@_spi(SourceKitLSP) public class ThreadSafeBox<T: Sendable>: @unchecked Sendable {
  /// Lock guarding `_value`.
  private let lock = NSLock()

  private var _value: T

  @_spi(SourceKitLSP) public var value: T {
    get {
      return lock.withLock {
        return _value
      }
    }
    set {
      lock.withLock {
        _value = newValue
      }
    }
    _modify {
      lock.lock()
      defer { lock.unlock() }
      yield &_value
    }
  }

  @_spi(SourceKitLSP) public init(initialValue: T) {
    _value = initialValue
  }

  @_spi(SourceKitLSP) public func withLock<Result>(_ body: (inout T) throws -> Result) rethrows -> Result {
    return try lock.withLock {
      return try body(&_value)
    }
  }

  /// If the value in the box is an optional, return it and reset it to `nil`
  /// in an atomic operation.
  @_spi(SourceKitLSP) public func takeValue<U>() -> T where U? == T {
    lock.withLock {
      guard let value = self._value else { return nil }
      self._value = nil
      return value
    }
  }
}
