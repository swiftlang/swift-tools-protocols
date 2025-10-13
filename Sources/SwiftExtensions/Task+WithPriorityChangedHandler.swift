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

/// Runs `operation`. If the task's priority changes while the operation is running, calls `taskPriorityChanged`.
///
/// Since Swift Concurrency doesn't support direct observation of a task's priority, this polls the task's priority at
/// `pollingInterval`.
/// The function assumes that the original priority of the task is `initialPriority`. If the task priority changed
/// compared to `initialPriority`, the `taskPriorityChanged` will be called.
@_spi(SourceKitLSP) public func withTaskPriorityChangedHandler<T: Sendable>(
  initialPriority: TaskPriority = Task.currentPriority,
  pollingInterval: Duration = .seconds(0.1),
  @_inheritActorContext operation: @escaping @Sendable () async throws -> T,
  taskPriorityChanged: @escaping @Sendable () -> Void
) async throws -> T {
  let lastPriority = ThreadSafeBox(initialValue: initialPriority)
  let result: T? = try await withThrowingTaskGroup(of: Optional<T>.self) { taskGroup in
    defer {
      // We leave this closure when either we have received a result or we registered cancellation. In either case, we
      // want to make sure that we don't leave the body task or the priority watching task running.
      taskGroup.cancelAll()
    }
    taskGroup.addTask(priority: initialPriority) {
      while true {
        if Task.isCancelled {
          break
        }
        let newPriority = Task.currentPriority
        let didChange = lastPriority.withLock { lastPriority in
          if newPriority != lastPriority {
            lastPriority = newPriority
            return true
          }
          return false
        }
        if didChange {
          taskPriorityChanged()
        }
        do {
          try await Task.sleep(for: pollingInterval)
        } catch {
          break
        }
      }
      return nil
    }
    taskGroup.addTask {
      try await operation()
    }
    // The first task that watches the priority never finishes unless it is cancelled, so we are effectively await the
    // `operation` task here.
    // We do need to await the observation task as well so that priority escalation also affects the observation task.
    for try await case let value? in taskGroup {
      return value
    }
    return nil
  }
  guard let result else {
    throw CancellationError()
  }
  return result
}
