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

public import Foundation

/// Wrapper around a task that allows multiple clients to depend on the task's value.
///
/// If all of the dependents are cancelled, the underlying task is cancelled as well.
@_spi(SourceKitLSP) public actor RefCountedCancellableTask<Success: Sendable> {
  @_spi(SourceKitLSP) public let task: Task<Success, Error>

  /// The number of clients that depend on the task's result and that are not cancelled.
  private var refCount: Int = 0

  /// Whether the task has been cancelled.
  @_spi(SourceKitLSP) public private(set) var isCancelled: Bool = false

  @_spi(SourceKitLSP) public init(
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable @concurrent () async throws -> Success
  ) {
    self.task = Task(priority: priority, operation: operation)
  }

  private func decrementRefCount() {
    refCount -= 1
    if refCount == 0 {
      self.cancel()
    }
  }

  /// Get the task's value.
  ///
  /// If all callers of `value` are cancelled, the underlying task gets cancelled as well.
  @_spi(SourceKitLSP) public var value: Success {
    get async throws {
      if isCancelled {
        throw CancellationError()
      }
      refCount += 1
      return try await withTaskCancellationHandler {
        return try await task.value
      } onCancel: {
        Task {
          await self.decrementRefCount()
        }
      }
    }
  }

  /// Cancel the task and throw a `CancellationError` to all clients that are awaiting the value.
  @_spi(SourceKitLSP) public func cancel() {
    isCancelled = true
    task.cancel()
  }
}

public extension Task {
  /// Awaits the value of the result.
  ///
  /// If the current task is cancelled, this will cancel the subtask as well.
  var valuePropagatingCancellation: Success {
    get async throws {
      try await withTaskCancellationHandler {
        return try await self.value
      } onCancel: {
        self.cancel()
      }
    }
  }
}

extension Task where Failure == Never {
  /// Awaits the value of the result.
  ///
  /// If the current task is cancelled, this will cancel the subtask as well.
  public var valuePropagatingCancellation: Success {
    get async {
      await withTaskCancellationHandler {
        return await self.value
      } onCancel: {
        self.cancel()
      }
    }
  }
}

/// Allows the execution of a cancellable operation that returns the results
/// via a completion handler.
///
/// `operation` must invoke the continuation's `resume` method exactly once.
///
/// If the task executing `withCancellableCheckedThrowingContinuation` gets
/// cancelled, `cancel` is invoked with the handle that `operation` provided.
@_spi(SourceKitLSP) public func withCancellableCheckedThrowingContinuation<Handle: Sendable, Result>(
  _ operation: (_ continuation: CheckedContinuation<Result, any Error>) -> Handle,
  cancel: @Sendable (Handle) -> Void
) async throws -> Result {
  let handleWrapper = ThreadSafeBox<Handle?>(initialValue: nil)

  @Sendable
  func callCancel() {
    /// Take the request ID out of the box. This ensures that we only send the
    /// cancel notification once in case the `Task.isCancelled` and the
    /// `onCancel` check race.
    if let handle = handleWrapper.takeValue() {
      cancel(handle)
    }
  }

  return try await withTaskCancellationHandler(
    operation: {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let handle = operation(continuation)
        handleWrapper.withLock { $0 = handle }

        // Check if the task was cancelled. This ensures we send a
        // CancelNotification even if the task gets cancelled after we register
        // the cancellation handler but before we set the `requestID`.
        if Task.isCancelled {
          callCancel()
        }
      }
    },
    onCancel: callCancel
  )
}

extension Collection where Self: Sendable, Element: Sendable {
  /// Transforms all elements in the collection concurrently and returns the transformed collection.
  // Workaround formatter issue: https://github.com/swiftlang/swift-format/issues/1081
  // swift-format-ignore
  @_spi(SourceKitLSP) public func concurrentMap<TransformedElement: Sendable>(
    maxConcurrentTasks: Int = ProcessInfo.processInfo.activeProcessorCount,
    _ transform: nonisolated(nonsending) @escaping @Sendable (Element) async -> TransformedElement
  ) async -> [TransformedElement] {
    let indexedResults = await withTaskGroup(of: (index: Int, element: TransformedElement).self) { taskGroup in
      var indexedResults: [(index: Int, element: TransformedElement)] = []
      for (index, element) in self.enumerated() {
        if index >= maxConcurrentTasks {
          // Wait for one item to finish being transformed so we don't exceed the maximum number of concurrent tasks.
          if let (index, transformedElement) = await taskGroup.next() {
            indexedResults.append((index, transformedElement))
          }
        }
        taskGroup.addTask {
          return (index, await transform(element))
        }
      }

      // Wait for all remaining elements to be transformed.
      for await (index, transformedElement) in taskGroup {
        indexedResults.append((index, transformedElement))
      }
      return indexedResults
    }
    return [TransformedElement](unsafeUninitializedCapacity: indexedResults.count) { buffer, count in
      for (index, transformedElement) in indexedResults {
        (buffer.baseAddress! + index).initialize(to: transformedElement)
      }
      count = indexedResults.count
    }
  }

  /// Invoke `body` for every element in the collection and wait for all calls of `body` to finish
  // Workaround formatter issue: https://github.com/swiftlang/swift-format/issues/1081
  // swift-format-ignore
  @_spi(SourceKitLSP) public func concurrentForEach(_ body: nonisolated(nonsending) @escaping @Sendable (Element) async -> Void) async {
    await withDiscardingTaskGroup { taskGroup in
      for element in self {
        taskGroup.addTask {
          await body(element)
        }
      }
    }
  }
}

@_spi(SourceKitLSP) public struct TimeoutError: Error, CustomStringConvertible {
  @_spi(SourceKitLSP) public var description: String { "Timed out" }

  @_spi(SourceKitLSP) public let handle: TimeoutHandle?

  @_spi(SourceKitLSP) public init(handle: TimeoutHandle?) {
    self.handle = handle
  }
}

@_spi(SourceKitLSP) public final class TimeoutHandle: Equatable, Sendable {
  @_spi(SourceKitLSP) public init() {}

  @_spi(SourceKitLSP) public static func == (_ lhs: TimeoutHandle, _ rhs: TimeoutHandle) -> Bool {
    return lhs === rhs
  }
}

@_spi(SourceKitLSP) @frozen
public enum WithTimeoutResult<T: Sendable>: Sendable {
  case result(T)
  case timedOut
}

/// Executes `body` with a `duration` timeout.
///
/// Returns `.result(value)` if `body` finishes within `duration`, otherwise `.timedOut`.
///
/// On timeout: if `resultReceivedAfterTimeout` is provided, `body` keeps running and its
/// eventual result is passed to that callback. Otherwise, `body` is cancelled.
@_spi(SourceKitLSP)
public func withTimeoutResult<T: Sendable>(
  _ timeout: Duration,
  body: @escaping @Sendable () async throws -> T,
  resultReceivedAfterTimeout: (@Sendable (_ result: T) async -> Void)? = nil
) async throws -> WithTimeoutResult<T> {
  // Capture the priority here so it stays consistent across `bodyTask`, timeoutTask`,
  // and `withTaskPriorityChangedHandler`'s initial state.
  let priority = Task.currentPriority

  let (stream, continuation) = AsyncStream<WithTimeoutResult<Result<T, any Error>>>.makeStream()
  let bodyTask = Task(priority: priority) {
    do {
      let value = try await body()
      continuation.yield(.result(.success(value)))
      return value
    } catch {
      continuation.yield(.result(.failure(error)))
      throw error
    }
  }
  let timeoutTask = Task(priority: priority) {
    do { try await Task.sleep(for: timeout) } catch { return }
    continuation.yield(.timedOut)
  }

  let outcome = await withTaskPriorityChangedHandler(initialPriority: priority) {
    () -> WithTimeoutResult<Result<T, any Error>> in
    for await value in stream {
      return value
    }
    // The for-await exits without a value only if the consuming task is cancelled.
    return .result(.failure(CancellationError()))
  } taskPriorityChanged: {
    // Spawning fresh tasks that await `bodyTask` and `timeoutTask` forces the runtime to
    // escalate their priorities via the await chain so `body`'s `Task.currentPriority`
    // reflects the elevated value.
    let newPriority = Task.currentPriority
    Task(priority: newPriority) { _ = await bodyTask.result }
    Task(priority: newPriority) { _ = await timeoutTask.value }
  }

  // Stop the still-pending timer; no-op if it already elapsed.
  timeoutTask.cancel()

  switch outcome {
  case .result(let r):
    // Cancel `bodyTask` if it's still running (cancellation-fallback case); no-op otherwise.
    bodyTask.cancel()
    return try .result(r.get())
  case .timedOut:
    if let resultReceivedAfterTimeout {
      // Late-result dispatch: await body and deliver via callback.
      Task { try? await resultReceivedAfterTimeout(bodyTask.value) }
    } else {
      bodyTask.cancel()
    }
    return .timedOut
  }
}

/// Executes `body`. If it doesn't finish after `duration`, throws a `TimeoutError` and cancels `body`.
///
/// `TimeoutError` is thrown immediately; the function does not wait for `body` to honor the cancellation.
///
/// If a `handle` is passed in and this `withTimeout` call times out, the thrown `TimeoutError` contains this handle.
/// This way a caller can identify whether this call to `withTimeout` timed out or if a nested call timed out.
@_spi(SourceKitLSP) @inlinable
public func withTimeout<T: Sendable>(
  _ duration: Duration,
  handle: TimeoutHandle? = nil,
  _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
  switch try await withTimeoutResult(duration, body: body) {
  case .result(let value): return value
  case .timedOut: throw TimeoutError(handle: handle)
  }
}

/// Executes `body`. If it doesn't finish after `duration`, return `nil` and continue running body. When `body` returns
/// a value or throws an error after the timeout, `resultReceivedAfterTimeout` is called with the outcome.
///
/// - Important: `body` will not be cancelled when the timeout is received. Use the other overload of `withTimeout` if
///   `body` should be cancelled after `timeout`.
@_spi(SourceKitLSP) @inlinable
public func withTimeout<T: Sendable>(
  _ timeout: Duration,
  body: @escaping @Sendable () async throws -> T,
  resultReceivedAfterTimeout: @escaping @Sendable (_ result: T) async -> Void
) async throws -> T? {
  switch try await withTimeoutResult(timeout, body: body, resultReceivedAfterTimeout: resultReceivedAfterTimeout) {
  case .result(let value): return value
  case .timedOut: return nil
  }
}

/// Same as `withTimeout` above but allows `body` to return an optional value.
@_spi(SourceKitLSP) @inlinable
public func withTimeout<T: Sendable>(
  _ timeout: Duration,
  body: @escaping @Sendable () async throws -> T?,
  resultReceivedAfterTimeout: @escaping @Sendable (_ result: T?) async -> Void
) async throws -> T? {
  switch try await withTimeoutResult(timeout, body: body, resultReceivedAfterTimeout: resultReceivedAfterTimeout) {
  case .result(let value): return value
  case .timedOut: return nil
  }
}
