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

/// Runs `operation`. If the task's priority changes while the operation is running, calls `taskPriorityChanged`.
///
/// Unlike `withTaskPriorityEscalationHandler`, this also calls `taskPriorityChanged` once at entry if the
/// current task is already escalated from `initialPriority` — escalations that happened before the handler
/// was registered would otherwise be invisible to the caller.
///
/// On platforms without the runtime-provided priority escalation hook (pre SwiftStdlib 6.2), falls back to
/// polling `Task.currentPriority` every `pollingInterval`.
@_spi(SourceKitLSP) @inlinable
public func withTaskPriorityChangedHandler<T: Sendable>(
  initialPriority: TaskPriority = Task.currentPriority,
  pollingInterval: Duration = .seconds(0.1),
  @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async throws -> T,
  taskPriorityChanged: @escaping @Sendable () -> Void
) async rethrows -> T {
  if #available(macOS 26, iOS 26, macCatalyst 26, *) {
    return try await withTaskPriorityEscalationHandler(
      operation: {
        // If the task is already escalated from `initialPriority`, notify the caller;
        // otherwise it wouldn't know about it because the handler hasn't been registered until now.
        if Task.currentPriority > initialPriority {
          Task { taskPriorityChanged() }
        }
        return try await operation()
      },
      onPriorityEscalated: { _, _ in taskPriorityChanged() }
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

/// Polling-based fallback for ``withTaskPriorityChangedHandler`` on platforms without
/// `withTaskPriorityEscalationHandler`. Exposed under `@_spi(Testing)` so tests can
/// exercise this path even on platforms where the inlinable wrapper would dispatch to
/// the stdlib hook.
@_spi(Testing)
public func withTaskPriorityChangedHandlerLegacy<T: Sendable>(
  initialPriority: TaskPriority,
  pollingInterval: Duration,
  @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async throws -> T,
  taskPriorityChanged: @escaping @Sendable () -> Void
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
    // The watcher loops forever until cancelled, so iterating the group effectively awaits
    // `operation`. The watcher is structured into the same task group so it inherits the
    // parent's priority and is automatically escalated alongside `operation`.
    for try await case let value? in taskGroup {
      return value
    }
    preconditionFailure("Task group exits only via operation's value or throw")
  }
}
