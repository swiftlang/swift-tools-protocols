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

import Testing
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

struct AsyncQueueTests {
  /// Two metadata kinds where:
  ///   - `.concurrent` is *not* self-serializing (concurrent with itself)
  ///   - `.serial` is self-serializing
  ///   - `.concurrent` is a dependency of `.serial
  ///
  /// In this configuration, a `.serial` task depends on a bucket whose
  /// entries do not depend on each other, so the dependency list cannot
  /// collapse to just the last entry — every concurrent task in the bucket
  /// must be awaited individually.
  private enum Meta: Hashable, Sendable, DependencyTracker {
    case concurrent
    case serial

    func isDependency(of other: Meta) -> Bool {
      switch (self, other) {
      case (.concurrent, .concurrent): return false
      case (.concurrent, .serial): return true
      case (.serial, .concurrent): return false
      case (.serial, .serial): return true
      }
    }
  }

  /// A task depending on a non-self-serializing bucket must wait on every
  /// task in that bucket, not just the last one.
  @Test func serialTaskWaitsForAllConcurrentDependencies() async throws {
    let queue = AsyncQueue<Meta>()

    // Three concurrent tasks held until we yield to their respective streams.
    let (stream1, cont1) = AsyncStream<Void>.makeStream()
    let (stream2, cont2) = AsyncStream<Void>.makeStream()
    let (stream3, cont3) = AsyncStream<Void>.makeStream()
    let (startedStream, startedCont) = AsyncStream<Void>.makeStream()

    for stream in [stream1, stream2, stream3] {
      queue.async(metadata: .concurrent) {
        startedCont.yield()
        for await _ in stream {}
      }
    }

    // Wait for all three concurrent tasks to be in flight before scheduling
    // the serial dependent — otherwise the bucket might not have all three
    // entries when the serial task computes its dependencies.
    var startCount = 0
    for await _ in startedStream {
      startCount += 1
      if startCount == 3 { break }
    }

    let serialRan = ThreadSafeBox<Bool>(initialValue: false)
    let serialTask = queue.async(metadata: .serial) {
      serialRan.value = true
    }

    // Release only the last concurrent task. The serial task must still wait
    // for the first two before running.
    cont3.finish()

    // Give the serial task time to (incorrectly) run. The first two
    // concurrent tasks are still blocked, so the serial task must not have
    // run yet.
    try await Task.sleep(for: .milliseconds(200))
    #expect(
      !serialRan.value,
      "Serial task ran before all concurrent dependencies completed"
    )

    // Release the remaining concurrent tasks; the serial task should now run.
    cont1.finish()
    cont2.finish()
    await serialTask.value
    #expect(serialRan.value)
  }
}
