//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
public import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
@_spi(SourceKitLSP) public import ToolsProtocolsSwiftExtensions

/// Side structure in which `QueueBasedMessageHandler` can keep track of active requests etc.
///
/// All of these could be requirements on `QueueBasedMessageHandler` but having them in a separate type means that
/// types conforming to `QueueBasedMessageHandler` only have to have a single member and it also ensures that these
/// fields are not accessible outside of the implementation of `QueueBasedMessageHandler`.
public final class QueueBasedMessageHandlerHelper: Sendable {
  private struct State {
    /// The requests that we are currently handling.
    ///
    /// Used to cancel the tasks if the client requests cancellation. `cancellationError` is the error that should be
    /// returned to the client if `task` is cancelled.
    var inProgressRequestsByID: [RequestID: (task: Task<(), Never>, cancellationError: ResponseError?)] = [:]

    /// Up to 10 request IDs that have recently finished.
    ///
    /// This is only used so we don't log an error when receiving a `CancelRequestNotification` for a request that has
    /// just returned a response.
    var recentlyFinishedRequests: [RequestID] = []
  }

  /// The category in which signposts for message handling should be logged.
  fileprivate let signpostLoggingCategory: String

  /// Whether a new logging scope should be created when handling a notification / request.
  private let createLoggingScope: Bool

  /// Notifications don't have an ID. This represents the next ID we can use to identify a notification.
  private let notificationIDForLogging = AtomicUInt32(initialValue: 1)

  private let state = ThreadSafeBox(initialValue: State())

  public init(signpostLoggingCategory: String, createLoggingScope: Bool) {
    self.signpostLoggingCategory = signpostLoggingCategory
    self.createLoggingScope = createLoggingScope
  }

  /// Cancel the request with the given ID.
  ///
  /// Cancellation is performed automatically when a `$/cancelRequest` notification is received. This can be called to
  /// implicitly cancel requests based on some criteria.
  ///
  /// `cancellationError` is the error that should be returned to the client for the cancelled request.
  @_spi(SourceKitLSP) public func cancelRequest(id: RequestID, error cancellationError: ResponseError) {
    self.state.withLock { state in
      if let task = state.inProgressRequestsByID[id]?.task {
        if state.inProgressRequestsByID[id]?.cancellationError == nil {
          // If we already have a cancellation error, stick with that one instead of overriding it.
          state.inProgressRequestsByID[id]?.cancellationError = cancellationError
        }
        task.cancel()
        return
      }
      if !state.recentlyFinishedRequests.contains(id) {
        logger.error(
          "Cannot cancel request \(id, privacy: .public) because it hasn't been scheduled for execution yet"
        )
      }
    }
  }

  /// The error that should be returned to the client when the request with the given ID has ben cancelled by calling
  /// `cancelRequest(id:)`.
  fileprivate func cancellationError(for id: RequestID) -> ResponseError? {
    state.withLock { state in
      // We don't need to hop onto `cancellationMessageHandlingQueue` here because we will have already set the
      // `cancellationError` in `inProgressRequestsByID` before cancelling the `Task`.
      state.inProgressRequestsByID[id]?.cancellationError
    }
  }

  fileprivate func setInProgressRequest(id: RequestID, request: some RequestType, task: Task<(), Never>?) {
    self.state.withLock { state in
      if let task {
        state.inProgressRequestsByID[id] = (task, nil)
      } else {
        state.inProgressRequestsByID[id] = nil
        state.recentlyFinishedRequests.append(id)
        while state.recentlyFinishedRequests.count > 10 {
          state.recentlyFinishedRequests.removeFirst()
        }
      }
    }
  }

  fileprivate func withNotificationLoggingScopeIfNecessary(_ body: () -> Void) {
    guard createLoggingScope else {
      body()
      return
    }
    // Only use the last two digits of the notification ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running notifications.
    let notificationID = notificationIDForLogging.fetchAndIncrement()
    withLoggingScope("notification-\(notificationID % 100)") {
      body()
    }
  }

  fileprivate func withRequestLoggingScopeIfNecessary(
    id: RequestID,
    _ body: @Sendable () async -> Void
  ) async {
    guard createLoggingScope else {
      await body()
      return
    }
    // Only use the last two digits of the request ID for the logging scope to avoid creating too many scopes.
    // See comment in `withLoggingScope`.
    // The last 2 digits should be sufficient to differentiate between multiple concurrently running requests.
    await withLoggingScope("request-\(id.numericValue % 100)") {
      await body()
    }
  }
}

public protocol QueueBasedMessageHandlerDependencyTracker: DependencyTracker {
  init(_ notification: some NotificationType)
  init(_ request: some RequestType)
}

/// A `MessageHandler` that handles all messages on an `AsyncQueue` and tracks dependencies between requests using
/// `DependencyTracker`, ensuring that requests which depend on each other are not executed out-of-order.
public protocol QueueBasedMessageHandler: MessageHandler {
  associatedtype DependencyTracker: QueueBasedMessageHandlerDependencyTracker

  /// The queue on which all messages (notifications, requests, responses) are
  /// handled.
  ///
  /// The queue is blocked until the message has been sufficiently handled to
  /// avoid out-of-order handling of messages. For sourcekitd, this means that
  /// a request has been sent to sourcekitd and for clangd, this means that we
  /// have forwarded the request to clangd.
  ///
  /// The actual semantic handling of the message happens off this queue.
  var messageHandlingQueue: AsyncQueue<DependencyTracker> { get }

  var messageHandlingHelper: QueueBasedMessageHandlerHelper { get }

  /// Called when a notification has been received but before it is being handled in `messageHandlingQueue`.
  ///
  /// Adopters can use this to implicitly cancel requests when a notification is received.
  func didReceive(notification: some NotificationType)

  /// Called when a request has been received but before it is being handled in `messageHandlingQueue`.
  ///
  /// Adopters can use this to implicitly cancel requests when a notification is received.
  func didReceive(request: some RequestType, id: RequestID)

  /// Perform the actual handling of `notification`.
  func handle(notification: some NotificationType) async

  /// Perform the actual handling of `request`.
  func handle<Request: RequestType>(
    request: Request,
    id: RequestID,
    reply: @Sendable @escaping (Result<Request.Response, any Error>) -> Void
  ) async
}

extension QueueBasedMessageHandler {
  public func didReceive(notification: some NotificationType) {}
  public func didReceive(request: some RequestType, id: RequestID) {}

  public func handle(_ notification: some NotificationType) {
    messageHandlingHelper.withNotificationLoggingScopeIfNecessary {
      // Request cancellation needs to be able to overtake any other message we
      // are currently handling. Ordering is not important here. We thus don't
      // need to execute it on `messageHandlingQueue`.
      if let notification = notification as? CancelRequestNotification {
        logger.log("Received cancel request notification: \(notification.forLogging)")
        self.messageHandlingHelper.cancelRequest(id: notification.id, error: .cancelled)
        return
      }
      self.didReceive(notification: notification)

      let signposter = Logger(
        subsystem: LoggingScope.subsystem,
        category: messageHandlingHelper.signpostLoggingCategory
      )
      .makeSignposter()
      let signpostID = signposter.makeSignpostID()
      let state = signposter.beginInterval(
        "Notification",
        id: signpostID,
        "\(type(of: notification).method, privacy: .public)"
      )
      messageHandlingQueue.async(metadata: DependencyTracker(notification)) {
        signposter.emitEvent("Start handling", id: signpostID)
        await self.handle(notification: notification)
        signposter.endInterval("Notification", state, "Done")
      }
    }
  }

  public func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) {
    let signposter = Logger(subsystem: LoggingScope.subsystem, category: messageHandlingHelper.signpostLoggingCategory)
      .makeSignposter()
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("Request", id: signpostID, "\(Request.method, privacy: .public)")

    self.didReceive(request: request, id: id)

    let task = messageHandlingQueue.async(metadata: DependencyTracker(request)) {
      signposter.emitEvent("Start handling", id: signpostID)
      await self.messageHandlingHelper.withRequestLoggingScopeIfNecessary(id: id) {
        await withTaskCancellationHandler {
          await self.handle(request: request, id: id) { result in
            switch result {
            case .success(let response):
              reply(.success(response))
            case .failure(let error as CancellationError):
              guard let cancellationError = self.messageHandlingHelper.cancellationError(for: id) else {
                return reply(.failure(ResponseError(error)))
              }
              reply(.failure(cancellationError))
            case .failure(let error):
              reply(.failure(ResponseError(error)))
            }
          }
          signposter.endInterval("Request", state, "Done")
        } onCancel: {
          signposter.emitEvent("Cancelled", id: signpostID)
        }
      }
      // We have handled the request and can't cancel it anymore.
      // Stop keeping track of it to free the memory.
      self.messageHandlingHelper.setInProgressRequest(id: id, request: request, task: nil)
    }
    // Keep track of the ID -> Task management with low priority. Once we cancel
    // a request, the cancellation task runs with a high priority and depends on
    // this task, which will elevate this task's priority.
    self.messageHandlingHelper.setInProgressRequest(id: id, request: request, task: task)
  }
}

fileprivate extension RequestID {
  /// Returns a numeric value for this request ID.
  ///
  /// For request IDs that are numbers, this is straightforward. For string-based request IDs, this uses a hash to
  /// convert the string into a number.
  var numericValue: Int {
    switch self {
    case .number(let number): return number
    case .string(let string): return Int(string) ?? abs(string.hashValue)
    }
  }
}
