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

import Synchronization

/// Runs `operation`. If the task's priority changes while the operation is running, calls `taskPriorityChanged`
/// with the new priority.
///
/// `taskPriorityChanged` is only called with priorities higher than `initialPriority` and than the priorities it was
/// called with before. If the current task is already escalated from `initialPriority` at entry,
/// `taskPriorityChanged` is called with the escalated priority — escalations that happened before the handler was
/// registered would otherwise be invisible to the caller.
///
/// On platforms without the runtime-provided priority escalation hook (pre SwiftStdlib 6.2), falls back to
/// polling `Task.currentPriority` every `pollingInterval`.
@_spi(SourceKitLSP) @inlinable
public func withTaskPriorityChangedHandler<T: Sendable>(
  initialPriority: TaskPriority = Task.currentPriority,
  pollingInterval: Duration = .seconds(0.1),
  @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async throws -> T,
  taskPriorityChanged: @escaping @Sendable (_ newPriority: TaskPriority) -> Void
) async rethrows -> T {
  if #available(macOS 26, iOS 26, macCatalyst 26, *) {
    // Depending on the runtime, the escalation handler is also called when it is installed, with the task's current
    // priority, which isn't necessarily a change. Only report priorities that are higher than any reported before.
    let reporter = PriorityIncreaseReporter(initialPriority: initialPriority, taskPriorityChanged: taskPriorityChanged)
    return try await withTaskPriorityEscalationHandler(
      operation: {
        // If the task was escalated before the handler was installed, the runtime might not report it.
        reporter.reportIfHigher(Task.currentPriority)
        return try await operation()
      },
      onPriorityEscalated: { _, newPriority in reporter.reportIfHigher(newPriority) }
    )
  } else {
    return try await withTaskPriorityChangedHandlerLegacy(
      initialPriority: initialPriority,
      pollingInterval: pollingInterval,
      operation: operation,
      taskPriorityChanged: taskPriorityChanged
    )
  }
}

/// Calls `taskPriorityChanged` with priorities that are higher than the initial priority and than any priority it was
/// called with before.
@usableFromInline
final class PriorityIncreaseReporter: Sendable {
  private let highestReportedPriority: Atomic<TaskPriority.RawValue>
  private let taskPriorityChanged: @Sendable (_ newPriority: TaskPriority) -> Void

  @usableFromInline
  init(
    initialPriority: TaskPriority,
    taskPriorityChanged: @escaping @Sendable (_ newPriority: TaskPriority) -> Void
  ) {
    self.highestReportedPriority = Atomic(initialPriority.rawValue)
    self.taskPriorityChanged = taskPriorityChanged
  }

  @usableFromInline
  func reportIfHigher(_ priority: TaskPriority) {
    let previous = highestReportedPriority.max(priority.rawValue, ordering: .relaxed).oldValue
    if previous < priority.rawValue {
      taskPriorityChanged(priority)
    }
  }
}

/// Polling-based fallback for ``withTaskPriorityChangedHandler`` on platforms without
/// `withTaskPriorityEscalationHandler`. Exposed under `@_spi(Testing)` so tests can
/// exercise this path even on platforms where the inlinable wrapper would dispatch to
/// the stdlib hook.
@_spi(Testing)
public func withTaskPriorityChangedHandlerLegacy<T: Sendable>(
  initialPriority: TaskPriority,
  pollingInterval: Duration,
  @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async throws -> T,
  taskPriorityChanged: @escaping @Sendable (_ newPriority: TaskPriority) -> Void
) async rethrows -> T {
  let lastPriority = RefBox(Atomic<TaskPriority.RawValue>(initialPriority.rawValue))
  return try await withThrowingTaskGroup(of: Optional<T>.self) { taskGroup in
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
        let newPriority = Task.currentPriority.rawValue
        if newPriority != lastPriority.value.exchange(newPriority, ordering: .relaxed) {
          taskPriorityChanged(TaskPriority(rawValue: newPriority))
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
    // The watcher loops forever until cancelled, so iterating the group effectively awaits
    // `operation`. The watcher is structured into the same task group so it inherits the
    // parent's priority and is automatically escalated alongside `operation`.
    for try await case let value? in taskGroup {
      return value
    }
    preconditionFailure("Task group exits only via operation's value or throw")
  }
}
