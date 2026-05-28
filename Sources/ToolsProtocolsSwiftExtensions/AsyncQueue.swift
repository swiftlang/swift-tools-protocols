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

import Foundation
import Synchronization

/// Abstraction layer so we can store a heterogeneous collection of tasks in an
/// array.
private protocol AnyTask: Sendable {
  func waitForCompletion() async
}

extension Task: AnyTask {
  func waitForCompletion() async {
    _ = await result
  }
}

/// A type that is able to track dependencies between tasks.
public protocol DependencyTracker: Sendable, Hashable {
  /// Whether the task described by `self` needs to finish executing before `other` can start executing.
  func isDependency(of other: Self) -> Bool
}

/// A dependency tracker where each task depends on every other, i.e. a serial
/// queue.
public struct Serial: DependencyTracker {
  public func isDependency(of other: Serial) -> Bool {
    return true
  }
}

private struct RegisteredTask: Sendable {
  let task: any AnyTask

  /// A unique value used to identify the task. This allows tasks to get
  /// removed from `dependencyCandidates` again after they finished executing.
  let id: UUID
}

/// Schedules async tasks with metadata-driven dependency ordering.
///
/// Each submitted task carries a ``DependencyTracker`` metadata value. Before a
/// new task executes, the queue waits for any already-pending tasks whose
/// metadata satisfies `isDependency(of:)` for the new task's metadata. Tasks
/// with no dependency relationship run concurrently.
///
/// `AsyncQueue<Serial>` makes every task depend on all others, producing a
/// classic serial FIFO queue.
public final class AsyncQueue<TaskMetadata: DependencyTracker>: Sendable {
  /// Tasks visible to future schedulings as potential dependencies.
  ///
  /// - For self-serializing metadata, only the latest task is stored - earlier in-flight
  ///   tasks were removed on insert because the latest transitively depends on them, so
  ///   future schedulings only need to wait on the latest.
  /// - For non-self-serializing metadata, all in-flight tasks are stored.
  ///
  /// The retain cycle (AsyncQueue -> dependencyCandidates -> Task -> self) is intentional.
  /// It keeps the queue alive until all tasks complete so their cleanup always runs.
  /// Each task breaks the cycle on exit.
  private let dependencyCandidates = Mutex<[TaskMetadata: [RegisteredTask]]>([:])

  public init() {}

  /// Schedule `operation` to run on the queue.
  ///
  /// The operation begins after all already-scheduled tasks whose metadata is a
  /// dependency of `metadata` have completed.
  @discardableResult
  public func async<Success: Sendable>(
    priority: TaskPriority? = nil,
    metadata: TaskMetadata,
    @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async -> Success
  ) -> Task<Success, Never> {
    self.registerTask(for: metadata) { id, deps in
      Task(priority: priority) {
        await self.runRegistered(id: id, for: metadata, awaiting: deps, body: operation)
      }
    }
  }

  /// Same as ``AsyncQueue/async(priority:metadata:operation:)`` but allows the
  /// operation to throw.
  ///
  /// - Important: The caller is responsible for handling any errors thrown from
  ///   the operation by awaiting the result of the returned task.
  public func asyncThrowing<Success: Sendable>(
    priority: TaskPriority? = nil,
    metadata: TaskMetadata,
    @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async throws -> Success
  ) -> Task<Success, any Error> {
    self.registerTask(for: metadata) { id, deps in
      Task(priority: priority) {
        try await self.runRegistered(id: id, for: metadata, awaiting: deps, body: operation)
      }
    }
  }

  /// Atomically computes the dependencies for a new task with `metadata`, lets `makeTask`
  /// build the Task using those, and registers it as a dependency candidate.
  private func registerTask<T: AnyTask>(
    for metadata: TaskMetadata,
    _ makeTask: (_ newTaskId: UUID, _ dependencies: [RegisteredTask]) -> T
  ) -> T {
    dependencyCandidates.withLock { candidates in
      let id = UUID()

      // Tasks that must finish before this one can execute.
      let dependencies: [RegisteredTask] = candidates.flatMap { candidateMetadata, tasks in
        candidateMetadata.isDependency(of: metadata) ? tasks : []
      }

      let task = makeTask(id, dependencies)

      // Register the task as a dependency candidate.
      if metadata.isDependency(of: metadata) {
        // For self-serializing metadata, only the latest task matters as a dependency,
        // it transitively covers all previous ones. Replace rather than append.
        candidates[metadata] = [RegisteredTask(task: task, id: id)]
      } else {
        candidates[metadata, default: []].append(RegisteredTask(task: task, id: id))
      }
      return task
    }
  }

  /// Run `operation` after `dependencies` complete, removing this task from the queue on exit.
  private func runRegistered<Success: Sendable>(
    id: UUID,
    for metadata: TaskMetadata,
    awaiting dependencies: [RegisteredTask],
    body operation: () async throws -> Success
  ) async rethrows -> Success {
    defer {
      self.dependencyCandidates.withLock { candidates in
        guard var bucket = candidates[metadata] else { return }
        bucket.removeAll { $0.id == id }
        candidates[metadata] = bucket.isEmpty ? nil : bucket
      }
    }
    // Await all dependencies concurrently so that a priority escalation on this task
    // propagates to every dependency at once, not just to the one currently being awaited.
    await dependencies.concurrentForEach { dependency in
      await dependency.task.waitForCompletion()
    }
    return try await operation()
  }
}

/// Convenience overloads for serial queues.
extension AsyncQueue where TaskMetadata == Serial {
  /// Same as ``async(priority:metadata:operation:)`` but specialized for serial
  /// queues that don't specify any metadata.
  @discardableResult
  public func async<Success: Sendable>(
    priority: TaskPriority? = nil,
    @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async -> Success
  ) -> Task<Success, Never> {
    return self.async(priority: priority, metadata: Serial(), operation: operation)
  }

  /// Same as ``asyncThrowing(priority:metadata:operation:)`` but specialized
  /// for serial queues that don't specify any metadata.
  public func asyncThrowing<Success: Sendable>(
    priority: TaskPriority? = nil,
    @_inheritActorContext operation: nonisolated(nonsending) @escaping @Sendable () async throws -> Success
  ) -> Task<Success, any Error> {
    return self.asyncThrowing(priority: priority, metadata: Serial(), operation: operation)
  }
}
