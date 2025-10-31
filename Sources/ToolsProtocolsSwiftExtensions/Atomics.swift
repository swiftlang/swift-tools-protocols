//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ToolsProtocolsCAtomics

// TODO: Use atomic types from the standard library (https://github.com/swiftlang/sourcekit-lsp/issues/1949)
@_spi(SourceKitLSP) public final class AtomicBool: Sendable {
  private nonisolated(unsafe) let atomic: UnsafeMutablePointer<CAtomicUInt32>

  @_spi(SourceKitLSP) public init(initialValue: Bool) {
    self.atomic = atomic_uint32_create(initialValue ? 1 : 0)
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  @_spi(SourceKitLSP) public var value: Bool {
    get {
      atomic_uint32_get(atomic) != 0
    }
    set {
      atomic_uint32_set(atomic, newValue ? 1 : 0)
    }
  }

  /// Sets the boolean to the new value and returns the previous value.
  @_spi(SourceKitLSP) public func setAndGet(newValue: Bool) -> Bool {
    return atomic_uint32_get_and_set(atomic, newValue ? 1 : 0) != 0
  }
}

@_spi(SourceKitLSP) public final class AtomicUInt8: Sendable {
  private nonisolated(unsafe) let atomic: UnsafeMutablePointer<CAtomicUInt32>

  @_spi(SourceKitLSP) public init(initialValue: UInt8) {
    self.atomic = atomic_uint32_create(UInt32(initialValue))
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  @_spi(SourceKitLSP) public var value: UInt8 {
    get {
      UInt8(atomic_uint32_get(atomic))
    }
    set {
      atomic_uint32_set(atomic, UInt32(newValue))
    }
  }
}

@_spi(SourceKitLSP) public final class AtomicUInt32: Sendable {
  private nonisolated(unsafe) let atomic: UnsafeMutablePointer<CAtomicUInt32>

  @_spi(SourceKitLSP) public init(initialValue: UInt32) {
    self.atomic = atomic_uint32_create(initialValue)
  }

  @_spi(SourceKitLSP) public var value: UInt32 {
    get {
      atomic_uint32_get(atomic)
    }
    set {
      atomic_uint32_set(atomic, newValue)
    }
  }

  deinit {
    atomic_uint32_destroy(atomic)
  }

  @_spi(SourceKitLSP) public func fetchAndIncrement() -> UInt32 {
    return atomic_uint32_fetch_and_increment(atomic)
  }
}

@_spi(SourceKitLSP) public final class AtomicInt32: Sendable {
  private nonisolated(unsafe) let atomic: UnsafeMutablePointer<CAtomicInt32>

  @_spi(SourceKitLSP) public init(initialValue: Int32) {
    self.atomic = atomic_int32_create(initialValue)
  }

  @_spi(SourceKitLSP) public var value: Int32 {
    get {
      atomic_int32_get(atomic)
    }
    set {
      atomic_int32_set(atomic, newValue)
    }
  }

  deinit {
    atomic_int32_destroy(atomic)
  }

  @_spi(SourceKitLSP) public func fetchAndIncrement() -> Int32 {
    return atomic_int32_fetch_and_increment(atomic)
  }
}
