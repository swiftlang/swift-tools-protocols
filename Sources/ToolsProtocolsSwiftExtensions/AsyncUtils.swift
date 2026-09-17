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

/// The continuation of a task that is suspended by
/// ``withCancellableCheckedThrowingContinuation(_:cancel:)``.
///
/// This wraps a `CheckedContinuation` so that the continuation is owned by the helper rather than by
/// `operation`, which lets the helper resume the awaiting task itself.
@_spi(SourceKitLSP) public struct CancellableContinuation<Success: Sendable>: Sendable {
  private enum State: Sendable {
    /// The `CheckedContinuation` that suspends the awaiting task does not exist yet.
    case notStarted

    /// The awaiting task is suspended and has not been resumed.
    case waiting(CheckedContinuation<Success, any Error>)

    /// The awaiting task has been resumed with a `CancellationError`.
    ///
    /// The operation may still deliver a result that raced with the cancellation. That result is
    /// discarded because the awaiting task is already resumed.
    case cancelled

    /// The awaiting task has been resumed.
    case resumed
  }

  private let state: ThreadSafeBox<State>

  fileprivate init() {
    self.state = ThreadSafeBox(initialValue: .notStarted)
  }

  /// Provide the continuation that suspends the awaiting task.
  fileprivate func start(_ continuation: CheckedContinuation<Success, any Error>) {
    state.withLock { state in
      guard case .notStarted = state else {
        preconditionFailure("CancellableContinuation was started twice")
      }
      state = .waiting(continuation)
    }
  }

  /// Resume the awaiting task with the result of the operation.
  ///
  /// If the awaiting task was cancelled it is already resumed, in which case `result` is discarded.
  ///
  /// - Precondition: Must be called at most once.
  public func resume<Failure: Error>(with result: Result<Success, Failure>) {
    let continuation = state.withLock { state -> CheckedContinuation<Success, any Error>? in
      switch state {
      case .notStarted:
        preconditionFailure("CancellableContinuation was resumed before it was started")
      case .waiting(let continuation):
        state = .resumed
        return continuation
      case .cancelled:
        // The result raced with the cancellation of the awaiting task, which has already been
        // resumed with a `CancellationError`. Nobody is interested in the result anymore.
        state = .resumed
        return nil
      case .resumed:
        preconditionFailure("CancellableContinuation was resumed twice")
      }
    }
    continuation?.resume(with: result)
  }

  /// Resume the awaiting task by returning `value`.
  ///
  /// - Precondition: Must be called at most once.
  public func resume(returning value: Success) {
    resume(with: Result<Success, any Error>.success(value))
  }

  /// Resume the awaiting task by throwing `error`.
  ///
  /// - Precondition: Must be called at most once.
  public func resume(throwing error: any Error) {
    resume(with: Result<Success, any Error>.failure(error))
  }

  /// Resume the awaiting task by throwing a `CancellationError`, unless it has already been resumed.
  ///
  /// Unlike ``resume(with:)`` this may be called repeatedly because cancellation is observed both
  /// through `withTaskCancellationHandler` and by re-checking `Task.isCancelled` once the operation
  /// has been started.
  fileprivate func cancel() {
    let continuation = state.withLock { state -> CheckedContinuation<Success, any Error>? in
      guard case .waiting(let continuation) = state else {
        return nil
      }
      state = .cancelled
      return continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

/// Allows the execution of a cancellable operation that returns the results
/// via a completion handler.
///
/// `operation` must invoke the continuation's `resume` method exactly once.
///
/// If the task executing `withCancellableCheckedThrowingContinuation` gets
/// cancelled, `cancel` is invoked with the handle that `operation` provided and
/// the awaiting task is resumed with a `CancellationError` without waiting for
/// `operation` to deliver a result. `operation` may never deliver one, eg. while
/// it waits for a reply from an unresponsive peer. A result that arrives after
/// the cancellation is discarded.
@_spi(SourceKitLSP) public func withCancellableCheckedThrowingContinuation<Handle: Sendable, Success: Sendable>(
  _ operation: (_ continuation: CancellableContinuation<Success>) -> Handle,
  cancel: @Sendable (Handle) -> Void
) async throws -> Success {
  let handleWrapper = ThreadSafeBox<Handle?>(initialValue: nil)
  let continuation = CancellableContinuation<Success>()

  @Sendable
  func callCancel() {
    /// Take the request ID out of the box. This ensures that we only send the
    /// cancel notification once in case the `Task.isCancelled` and the
    /// `onCancel` check race.
    if let handle = handleWrapper.takeValue() {
      cancel(handle)
    }
    continuation.cancel()
  }

  return try await withTaskCancellationHandler(
    operation: {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { checkedContinuation in
        // Hand the continuation to `continuation` before running `operation` because `operation` may
        // resume it before it returns.
        continuation.start(checkedContinuation)
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
  } taskPriorityChanged: { newPriority in
    if #available(macOS 26, iOS 26, macCatalyst 26, *) {
      bodyTask.escalatePriority(to: newPriority)
      timeoutTask.escalatePriority(to: newPriority)
    } else {
      // Spawning fresh tasks that await `bodyTask` and `timeoutTask` forces the runtime to
      // escalate their priorities via the await chain so `body`'s `Task.currentPriority`
      // reflects the elevated value.
      Task(priority: newPriority) { _ = await bodyTask.result }
      Task(priority: newPriority) { _ = await timeoutTask.value }
    }
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
