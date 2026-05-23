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

import Synchronization
import Testing
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

struct RefBoxTests {
  /// `RefBox<Mutex<T>>` is `Sendable` and can be captured by a detached task.
  @Test func mutexBoxIsSendableAndShareable() async {
    let box = RefBox(Mutex<Int>(0))
    let task = Task { box.value.withLock { $0 += 1 } }
    await task.value
    #expect(box.value.withLock { $0 } == 1)
  }

  /// `withLock` returns the body's result and propagates mutations.
  @Test func mutexBoxWithLockReturnsAndMutates() {
    let box = RefBox(Mutex<[Int]>([]))
    let count = box.value.withLock { (arr: inout [Int]) -> Int in
      arr.append(1)
      arr.append(2)
      return arr.count
    }
    #expect(count == 2)
    #expect(box.value.withLock { $0 } == [1, 2])
  }

  /// `RefBox<Atomic<T>>` is `Sendable` and shareable across tasks.
  @Test func atomicBoxIsSendableAndShareable() async {
    let flag = RefBox(Atomic<Bool>(false))
    let task = Task { flag.value.store(true, ordering: .relaxed) }
    await task.value
    #expect(flag.value.load(ordering: .relaxed) == true)
  }
}
