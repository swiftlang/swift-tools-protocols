//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import SKLogging
@_spi(SourceKitLSP) @_spi(Testing) import ToolsProtocolsSwiftExtensions
import ToolsProtocolsTestSupport
import XCTest

#if os(Windows)
import WinSDK
#elseif canImport(Android)
import Android
#endif

final class AsyncUtilsTests: XCTestCase {
  override func setUp() async throws {
    LoggingScope.configureDefaultLoggingSubsystem("org.swift.swift-tools-protocols-tests")
  }

  func testWithTimeout() async throws {
    let expectation = self.expectation(description: "withTimeout body finished")
    await assertThrowsError(
      try await withTimeout(.seconds(0.1)) {
        try? await Task.sleep(for: .seconds(10))
        XCTAssert(Task.isCancelled)
        expectation.fulfill()
      }
    ) { error in
      XCTAssert(error is TimeoutError, "Received unexpected error \(error)")
    }
    try await fulfillmentOfOrThrow(expectation)
  }

  func testWithTimeoutReturnsImmediatelyEvenIfBodyDoesntCooperateInCancellation() async throws {
    let start = Date()
    await assertThrowsError(
      try await withTimeout(.seconds(0.1)) {
        #if os(Windows)
        Sleep(10_000 /*ms*/)
        #else
        sleep(10 /*s*/)
        #endif
      }
    ) { error in
      XCTAssert(error is TimeoutError, "Received unexpected error \(error)")
    }
    XCTAssert(Date().timeIntervalSince(start) < 5)
  }

  func testWithTimeoutEscalatesPriority() async throws {
    let expectation = self.expectation(description: "Timeout started")
    let task = Task(priority: .background) {
      // We don't actually hit the timeout. It's just a large value.
      try await withTimeout(.seconds(defaultTimeout * 2)) {
        expectation.fulfill()
        try await repeatUntilExpectedResult(sleepInterval: .seconds(0.1)) {
          logger.debug("Current priority: \(Task.currentPriority.rawValue)")
          return Task.currentPriority > .background
        }
      }
    }
    try await fulfillmentOfOrThrow(expectation)
    try await Task(priority: .high) {
      try await task.value
    }.value
  }

  func testWithTaskPriorityChangedHandlerCallsCallbackIfAlreadyEscalated() async throws {
    // Verify `taskPriorityChanged` is called even when the escalation happens before the handler
    // is registered.
    let callbackCalled = ThreadSafeBox(initialValue: false)
    let task = Task(priority: .background) {
      try await withTaskPriorityChangedHandler(
        initialPriority: .background,
        pollingInterval: .milliseconds(50),
        operation: {
          try await repeatUntilExpectedResult(timeout: .seconds(10), sleepInterval: .milliseconds(50)) {
            return callbackCalled.value
          }
        },
        taskPriorityChanged: { _ in
          callbackCalled.withLock { $0 = true }
        }
      )
    }
    try await Task(priority: .high) {
      try await task.value
    }.value
    XCTAssertTrue(callbackCalled.value)
  }

  func testWithTaskPriorityChangedHandlerLegacyReturnsOptionalNilFromOperation() async throws {
    // When the operation's `T` is itself an `Optional`, verify `nil` return
    // value is propagated as the operation's result.
    let result: String? = try await withTaskPriorityChangedHandlerLegacy(
      initialPriority: Task.currentPriority,
      pollingInterval: .milliseconds(100),
      operation: {
        let value: String? = nil
        return value
      },
      taskPriorityChanged: { _ in }
    )
    XCTAssertNil(result)
  }

  func testWithTaskPriorityChangedHandlerLegacyDetectsPriorityEscalation() async throws {
    let started = self.expectation(description: "Operation started")
    let callbackCalled = ThreadSafeBox(initialValue: false)
    let task = Task(priority: .background) {
      try await withTaskPriorityChangedHandlerLegacy(
        initialPriority: .background,
        pollingInterval: .milliseconds(50),
        operation: {
          started.fulfill()
          try await repeatUntilExpectedResult(sleepInterval: .milliseconds(100)) {
            return callbackCalled.value
          }
        },
        taskPriorityChanged: { _ in
          callbackCalled.withLock { $0 = true }
        }
      )
    }
    try await fulfillmentOfOrThrow(started)
    try await Task(priority: .high) {
      try await task.value
    }.value
    XCTAssertTrue(callbackCalled.value)
  }

  func testWithTaskPriorityChangedHandlerLegacyRethrowsError() async throws {
    struct TestError: Error {}
    await assertThrowsError(
      try await withTaskPriorityChangedHandlerLegacy(
        initialPriority: Task.currentPriority,
        pollingInterval: .milliseconds(100),
        operation: { throw TestError() },
        taskPriorityChanged: { _ in }
      )
    ) { error in
      XCTAssert(error is TestError, "Received unexpected error \(error)")
    }
  }

  func testWithTaskPriorityChangedHandlerLegacyExitsCleanly() async throws {
    // Verify the operation's error propagates out when the outer task is cancelled and the
    // operation delays honoring cancellation, instead of tripping the post-loop precondition.
    struct OperationError: Error {}
    let task = Task {
      try await withTaskPriorityChangedHandlerLegacy(
        initialPriority: Task.currentPriority,
        pollingInterval: .milliseconds(50),
        operation: {
          // Ignore cancellation for a short window, then surface a custom error from the operation.
          for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(20))
          }
          throw OperationError()
        },
        taskPriorityChanged: { _ in }
      )
    }
    // Cancel after operation has started.
    try await Task.sleep(for: .milliseconds(10))
    task.cancel()
    await assertThrowsError(try await task.value) { error in
      XCTAssert(error is OperationError, "Received unexpected error \(error)")
    }
  }
}
