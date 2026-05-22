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

public import Foundation
public import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

#if canImport(Android)
import Android
#endif

/// A connection between a message handler (e.g. language server) in the same process as the connection object and a
/// remote message handler (e.g. language client) that may run in another process using JSON RPC messages sent over a
/// pair of in/out file descriptors.
public actor JSONRPCConnection: Connection {
  @frozen public enum TerminationReason: Sendable, Equatable {
    case exited(exitCode: Int32)
    case uncaughtSignal
  }

  // MARK: - Outgoing work item

  /// All outgoing sends are serialized through an `AsyncStream<OutgoingItem>`.
  /// The stream's `Continuation.yield` is synchronous and thread-safe, giving a guaranteed FIFO
  /// order that `Task { await … }` cannot provide.
  private enum OutgoingItem: Sendable {
    case notification(any NotificationType)
    /// Pre-built `OutstandingRequest` so the actor can register it before the bytes hit the wire.
    case request(any RequestType, id: RequestID, outstanding: OutstandingRequest)
    case reply(LSPResult<any ResponseType>, id: RequestID)
    case rawData(Data)
  }

  // MARK: - Constants (let properties are implicitly nonisolated)

  /// A name of the endpoint for this connection, used for logging, e.g. `clangd`.
  private let name: String

  /// File descriptor for reading input (eg. stdin for an LSP server)
  private let receiveFD: FileHandle
  /// If non-nil, all data received by `receiveFD` will be mirrored to this file handle
  private let receiveMirrorFile: FileHandle?

  /// File desciptor for sending output (eg. stdout for an LSP server)
  private let sendFD: FileHandle
  /// If non-nil, all output sent to `sendFD` will be mirrored to this file handle
  private let sendMirrorFile: FileHandle?

  private let messageRegistry: MessageRegistry
  private let nextRequestIDStorage = AtomicUInt32(initialValue: 0)

  // MARK: - Send-path (created in init — independent of receiveHandler/closeHandler)

  /// Yields to this continuation to enqueue an outgoing work item.
  /// `AsyncStream.Continuation` is `Sendable`; as a `let` property it is implicitly `nonisolated`.
  private let outgoingContinuation: AsyncStream<OutgoingItem>.Continuation

  /// Yields encoded bytes to this continuation for writing to `sendFD`.
  /// Only accessed from the actor-isolated `outgoingProcessorTask`.
  private let sendContinuation: AsyncStream<Data>.Continuation

  /// Drains `sendContinuation` and writes bytes to `sendFD` (detached — blocking I/O).
  /// Awaiting this in `_close()` transitively waits for the outgoing processor to finish too,
  /// because the processor calls `sendContinuation.finish()` before `sendLoopTask` can exit.
  /// Assigned last in `init` so that `self` is fully initialized before the fire-and-forget
  /// outgoing processor task captures it.
  private let sendLoopTask: Task<Void, Never>

  // MARK: - Receive-path (created in start — begins actual I/O)

  /// Decodes and dispatches incoming messages on the actor.
  /// `nil` until `start(receiveHandler:closeHandler:)` is called.
  private var receiveLoopTask: Task<Void, Never>? = nil

  // MARK: - Actor-isolated mutable state

  private var receiveHandler: MessageHandler? = nil
  private var closeHandler: (@Sendable () async -> Void)? = nil

  private enum State { case running, closing, closed }
  private var state: State = .running

  private struct OutstandingRequest: Sendable {
    var requestMethod: String
    var responseType: ResponseType.Type
    var replyHandler: @Sendable (LSPResult<Any>) -> Void
  }

  /// The set of currently outstanding outgoing requests along with information about how to decode and handle their
  /// responses.
  private var outstandingRequests: [RequestID: OutstandingRequest] = [:]

  // MARK: - Static start

  #if os(macOS) || !canImport(Darwin)
  /// Creates and starts a `JSONRPCConnection` that connects to a subprocess launched with the specified arguments.
  ///
  /// `client` is the message handler that handles the messages sent from the subprocess to SourceKit-LSP.
  public static func start(
    executable: URL,
    arguments: [String],
    name: StaticString,
    protocol messageRegistry: MessageRegistry,
    stderrLoggingCategory: String,
    client: MessageHandler,
    terminationHandler: @Sendable @escaping (_ terminationReason: TerminationReason) -> Void
  ) throws -> (connection: JSONRPCConnection, process: Process) {
    let clientToServer = Pipe()
    let serverToClient = Pipe()

    let connection = JSONRPCConnection(
      name: "\(name)",
      protocol: messageRegistry,
      receiveFD: serverToClient.fileHandleForReading,
      sendFD: clientToServer.fileHandleForWriting
    )

    connection.start(receiveHandler: client) {
      // Keep the pipes alive until we close the connection.
      withExtendedLifetime((clientToServer, serverToClient)) {}
    }

    logger.log(
      "Launching JSON-RPC connection to \(executable.description) with options [\(arguments.joined(separator: " "))]"
    )
    let process = Foundation.Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = serverToClient
    process.standardInput = clientToServer
    let logForwarder = PipeAsStringHandler {
      Logger(subsystem: LoggingScope.subsystem, category: stderrLoggingCategory).info("\($0)")
    }
    let stderrHandler = Pipe()
    stderrHandler.fileHandleForReading.readabilityHandler = { fileHandle in
      let newData = fileHandle.availableData
      if newData.count == 0 {
        stderrHandler.fileHandleForReading.readabilityHandler = nil
      } else {
        logForwarder.handleDataFromPipe(newData)
      }
    }
    process.standardError = stderrHandler
    process.terminationHandler = { process in
      logger.log(
        level: process.terminationReason == .exit ? .default : .error,
        "\(name) exited: \(process.terminationReason.rawValue) \(process.terminationStatus)"
      )
      connection.close()
      let terminationReason: TerminationReason
      switch process.terminationReason {
      case .exit:
        terminationReason = .exited(exitCode: process.terminationStatus)
      case .uncaughtSignal:
        terminationReason = .uncaughtSignal
      @unknown default:
        logger.fault(
          "Process terminated with unknown termination reason: \(process.terminationReason.rawValue, privacy: .public)"
        )
        terminationReason = .exited(exitCode: 0)
      }
      terminationHandler(terminationReason)
    }
    try process.run()

    return (connection, process)
  }
  #endif

  // MARK: - Lifecycle

  public init(
    name: String,
    protocol messageRegistry: MessageRegistry,
    receiveFD: FileHandle,
    sendFD: FileHandle,
    receiveMirrorFile: FileHandle? = nil,
    sendMirrorFile: FileHandle? = nil
  ) {
    globallyDisableSigpipeIfNeeded()

    self.name = name
    self.receiveFD = receiveFD
    self.sendFD = sendFD
    self.receiveMirrorFile = receiveMirrorFile
    self.sendMirrorFile = sendMirrorFile
    self.messageRegistry = messageRegistry

    // Create both streams before self is needed — continuations are let properties.
    let (outgoingStream, outgoingCont) = AsyncStream<OutgoingItem>.makeStream()
    let (sendStream, sendCont) = AsyncStream<Data>.makeStream()

    self.outgoingContinuation = outgoingCont
    self.sendContinuation = sendCont

    // Task.detached so the blocking sendFD.write does not hold the actor's executor.
    self.sendLoopTask = Task.detached {
      for await data in sendStream {
        orLog("Writing send mirror file") { try sendMirrorFile?.write(contentsOf: data) }
        do {
          try sendFD.write(contentsOf: data)
        } catch {
          logger.fault("IO error sending message to \(name): \(error.forLogging)")
        }
      }
    }

    // self is now fully initialized

    // Fire-and-forget: processes outgoing items in FIFO order on the actor; when the outgoing
    // stream ends (after _close drains it), calls sendContinuation.finish() so sendLoopTask exits.
    // _close() awaits sendLoopTask.value, which transitively waits for this task to finish first.
    Task {
      for await item in outgoingStream {
        await self.processOutgoing(item)
      }
      self.sendContinuation.finish()
    }
  }

  /// Register the message handler and start the receive-path I/O.
  ///
  /// - Important: Must be called before incoming messages can be dispatched.
  public nonisolated func start(
    receiveHandler: MessageHandler,
    closeHandler: nonisolated(nonsending) @escaping @Sendable () async -> Void = {}
  ) {
    Task { await self._start(receiveHandler: receiveHandler, closeHandler: closeHandler) }
  }

  public nonisolated func changeReceiveHandler(_ receiveHandler: MessageHandler) {
    Task { await self._changeReceiveHandler(receiveHandler) }
  }

  public nonisolated func close() {
    Task { await self._close() }
  }

  // MARK: - Connection protocol (nonisolated — yields directly to the FIFO outgoing stream)

  public nonisolated func send(_ notification: some NotificationType) {
    outgoingContinuation.yield(.notification(notification))
  }

  public nonisolated func nextRequestID() -> RequestID {
    return .string("sk-\(nextRequestIDStorage.fetchAndIncrement())")
  }

  public nonisolated func send<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) {
    let outstanding = OutstandingRequest(
      requestMethod: Request.method,
      responseType: Request.Response.self,
      replyHandler: { anyResult in reply(anyResult.map { $0 as! Request.Response }) }
    )
    outgoingContinuation.yield(.request(request, id: id, outstanding: outstanding))
  }

  @_spi(Testing)
  public nonisolated func sendReply(_ response: LSPResult<ResponseType>, id: RequestID) {
    outgoingContinuation.yield(.reply(response, id: id))
  }

  @_spi(Testing)
  public nonisolated func send(data: Data) {
    outgoingContinuation.yield(.rawData(data))
  }

  // MARK: - Private actor-isolated implementation

  private func _start(
    receiveHandler: MessageHandler,
    closeHandler: @escaping @Sendable () async -> Void
  ) {
    guard state == .running, self.receiveHandler == nil else { return }
    self.receiveHandler = receiveHandler
    self.closeHandler = closeHandler

    // Receive stream: background task frames complete messages; actor decodes and dispatches.
    let (receiveStream, receiveCont) = AsyncStream<Data>.makeStream()
    let receiveFD = self.receiveFD
    let receiveMirrorFile = self.receiveMirrorFile
    let name = self.name
    // Task.detached so the blocking receiveFD.read does not hold the actor's executor.
    Task.detached {
      let parser = JSONMessageParser<Data>(decoder: { $0 })
      while true {
        let data = orLog("Reading from \(name)") { try receiveFD.read(upToCount: parser.nextReadLength) }
        guard let data, !data.isEmpty else {
          // We have reached the end of `receiveFD`, close the connection.
          receiveCont.finish()
          return
        }

        orLog("Writing receive mirror file") {
          try receiveMirrorFile?.write(contentsOf: data)
        }

        if let messageBytes = parser.parse(chunk: data) {
          receiveCont.yield(messageBytes)
        }
      }
    }

    self.receiveLoopTask = Task {
      for await messageBytes in receiveStream {
        if let message = self.decodeJSONRPCMessage(messageBytes) {
          self.handle(message)
        }
      }
      await self._close()
    }
  }

  private func _changeReceiveHandler(_ receiveHandler: MessageHandler) {
    self.receiveHandler = receiveHandler
  }

  private func readyToSend(shouldLog: Bool = true) -> Bool {
    let ready = state == .running || state == .closing
    if shouldLog && !ready {
      logger.error("Ignoring message; state = \(String(reflecting: self.state), privacy: .public)")
    }
    return ready
  }

  /// Process one outgoing work item. Called from `outgoingProcessorTask` (actor-isolated, FIFO).
  private func processOutgoing(_ item: OutgoingItem) {
    switch item {
    case .notification(let notification):
      logger.info(
        """
        Sending notification to \(self.name, privacy: .public)
        \(notification.forLogging)
        """
      )
      sendEncoded(.notification(notification))

    case .request(let request, let id, let outstanding):
      guard readyToSend() else {
        outstanding.replyHandler(.failure(.serverCancelled))
        return
      }
      logger.info(
        """
        Sending request to \(self.name, privacy: .public) (id: \(id, privacy: .public)):
        \(request.forLogging)
        """
      )
      // Register before bytes reach sendFD: the peer can only respond after receiving the bytes,
      // so the response type is guaranteed to be registered before any response arrives.
      outstandingRequests[id] = outstanding
      sendEncoded(.request(request, id: id))

    case .reply(let response, let id):
      switch response {
      case .success(let result): sendEncoded(.response(result, id: id))
      case .failure(let error): sendEncoded(.errorResponse(error, id: id))
      }

    case .rawData(let data):
      guard readyToSend() else { return }
      sendContinuation.yield(data)
    }
  }

  private func _close() async {
    guard state == .running else { return }
    state = .closing

    logger.log("Closing JSONRPCConnection to \(self.name)")

    // Finish the outgoing stream; the fire-and-forget processor will drain remaining items,
    // then call sendContinuation.finish(). State is .closing so processOutgoing can still send.
    outgoingContinuation.finish()

    // Drain the send loop — waits transitively for the outgoing processor to finish first.
    await sendLoopTask.value

    state = .closed

    // IMPORTANT: sendFD must be closed first; otherwise Windows blocks in receiveFD.close()
    // waiting for the blocking read to return.
    orLog("Closing sendFD to \(name)") { try sendFD.close() }
    orLog("Closing receiveFD to \(name)") { try receiveFD.close() }
    orLog("Closing sendMirrorFile to \(name)") { try sendMirrorFile?.close() }
    orLog("Closing receiveMirrorFile to \(name)") { try receiveMirrorFile?.close() }

    receiveLoopTask?.cancel()
    receiveLoopTask = nil
    receiveHandler = nil

    for outstandingRequest in outstandingRequests.values {
      outstandingRequest.replyHandler(.failure(ResponseError.serverCancelled))
    }
    outstandingRequests = [:]

    await closeHandler?()
  }

  /// Handle received message.
  private func handle(_ message: JSONRPCMessage) {
    guard let receiveHandler, state != .closed else {
      logger.error("Ignoring message as the JSON-RPC connection is closed: \(message.prettyPrintedRedactedJSON)")
      return
    }

    switch message {
    case .notification(let notification):
      notification._handle(receiveHandler)
    case .request(let request, let id):
      request._handle(receiveHandler, id: id) { (response, id) in
        self.sendReply(response, id: id)
      }
    case .response(let response, let id):
      guard let outstanding = outstandingRequests.removeValue(forKey: id) else {
        logger.error("No outstanding requests for response ID \(id, privacy: .public)")
        return
      }
      logger.info(
        """
        Received reply for request \(id, privacy: .public) from \(self.name, privacy: .public)
        \(outstanding.requestMethod, privacy: .public)
        \(response.forLogging)
        """
      )
      outstanding.replyHandler(.success(response))
    case .errorResponse(let error, let id):
      guard let id = id else {
        logger.error("Received error response for unknown request: \(error.forLogging)")
        return
      }
      guard let outstanding = outstandingRequests.removeValue(forKey: id) else {
        logger.error("No outstanding requests for error response ID \(id, privacy: .public)")
        return
      }
      logger.error(
        """
        Received error for request \(id, privacy: .public) from \(self.name, privacy: .public)
        \(outstanding.requestMethod, privacy: .public)
        \(error.forLogging)
        """
      )
      outstanding.replyHandler(.failure(error))
    }
  }

  private func sendMessageCodingErrorNotificationToClient(message: String) {
    let showMessage = ShowMessageNotification(
      type: .error,
      message: """
        \(message). Please run 'sourcekit-lsp diagnose' to file an issue.
        """
    )
    sendEncoded(.notification(showMessage))
  }

  /// Decode a single JSONRPC message from the given `messageBytes`.
  ///
  /// `messageBytes` should be valid JSON, ie. this is the message sent from the client without the `Content-Length`
  /// header.
  ///
  /// If an error occurs during message parsing, this tries to recover as gracefully as possible and returns `nil`.
  /// Callers should consider the message handled and ignore it when this function returns `nil`.
  private func decodeJSONRPCMessage(_ messageBytes: Data) -> JSONRPCMessage? {
    let decoder = JSONDecoder()

    // Set message registry to use for model decoding.
    decoder.userInfo[.messageRegistryKey] = messageRegistry

    // Snapshot for the @Sendable decoder callback — safe because this method has no suspension
    // points, so the snapshot is current for the entire synchronous decode call.
    let localOutstandingRequests = outstandingRequests
    decoder.userInfo[.responseTypeCallbackKey] = { @Sendable (id: RequestID) -> ResponseType.Type? in
      guard let outstanding = localOutstandingRequests[id] else {
        logger.error("Unknown request for \(id, privacy: .public)")
        return nil
      }
      return outstanding.responseType
    }

    do {
      return try decoder.decode(
        JSONRPCMessage.self,
        from: messageBytes
      )
    } catch let error as MessageDecodingError {
      logger.fault("Failed to decode message: \(error.forLogging)")
      logger.fault("Malformed message: \(String(bytes: messageBytes, encoding: .utf8) ?? "<invalid UTF-8>")")

      // We failed to decode the message. Under those circumstances try to behave as LSP-conforming as possible.
      // Always log at the fault level so that we know something is going wrong from the logs.
      //
      // The pattern below is to handle the message in the best possible way and then `return nil` to acknowledge the
      // handling. That way the compiler enforces that we handle all code paths.
      switch error.messageKind {
      case .request:
        if let id = error.id {
          // If we know it was a request and we have the request ID, simply reply to the request and tell the client
          // that we couldn't parse it. That complies with LSP that all requests should eventually get a response.
          logger.fault(
            "Replying to request \(id, privacy: .public) with error response because we failed to decode the request"
          )
          sendEncoded(.errorResponse(ResponseError(error), id: id))
          return nil
        }
        // If we don't know the ID of the request, ignore it and show a notification to the user.
        // That way the user at least knows that something is going wrong even if the client never gets a response
        // for the request.
        logger.fault("Ignoring request because we failed to decode the request and don't have a request ID")
        sendMessageCodingErrorNotificationToClient(message: "sourcekit-lsp failed to decode a request")
        return nil
      case .response:
        if let id = error.id {
          if let outstanding = self.outstandingRequests.removeValue(forKey: id) {
            // If we received a response to a request we sent to the client, assume that the client responded with an
            // error. That complies with LSP that all requests should eventually get a response.
            logger.fault(
              "Assuming an error response to request \(id, privacy: .public) because response from client could not be decoded"
            )
            outstanding.replyHandler(.failure(ResponseError(error)))
            return nil
          }
          // If there's an error in the response but we don't even know about the request, we can ignore it.
          logger.fault(
            "Ignoring response to request \(id, privacy: .public) because it could not be decoded and given request ID is unknown"
          )
          return nil
        }
        // And if we can't even recover the ID the response is for, we drop it. This means that whichever code in
        // sourcekit-lsp sent the request will probably never get a reply but there's nothing we can do about that.
        // Ideally requests sent from sourcekit-lsp to the client would have some kind of timeout anyway.
        logger.fault("Ignoring response because its request ID could not be recovered")
        return nil
      case .notification:
        if error.code == .methodNotFound {
          // If we receive a notification we don't know about, this might be a client sending a new LSP notification
          // that we don't know about. It can't be very critical so we ignore it without bothering the user with an
          // error notification.
          logger.fault("Ignoring notification because we don't know about it's method")
          return nil
        }
        // Ignoring any other notification might result in corrupted behavior. For example, ignoring a
        // `textDocument/didChange` will result in an out-of-sync state between the editor and sourcekit-lsp.
        // Warn the user about the error.
        logger.fault("Ignoring notification that may cause corrupted behavior")
        sendMessageCodingErrorNotificationToClient(message: "sourcekit-lsp failed to decode a notification")
        return nil
      case .unknown:
        // We don't know what has gone wrong. This could be any level of badness. Inform the user about it.
        logger.fault("Ignoring unknown message")
        sendMessageCodingErrorNotificationToClient(message: "sourcekit-lsp failed to decode a message")
        return nil
      }
    } catch {
      // We don't know what has gone wrong. This could be any level of badness. Inform the user about it and ignore the
      // message.
      logger.fault("Ignoring unknown message")
      sendMessageCodingErrorNotificationToClient(message: "sourcekit-lsp failed to decode an unknown message")
      return nil
    }
  }

  /// Send outgoing message.
  private func sendEncoded(_ message: JSONRPCMessage) {
    guard readyToSend() else { return }

    let content: Data
    do {
      content = try JSONEncoder().encode(message)
    } catch {
      logger.fault("Failed to encode message: \(error.forLogging)")
      logger.fault("Malformed message: \(String(describing: message))")
      switch message {
      case .notification(_):
        // We want to send a notification to the editor but failed to encode it. Since dropping the notification might
        // result in getting out-of-sync state-wise with the editor (eg. for work progress notifications), inform the
        // user about it.
        sendMessageCodingErrorNotificationToClient(
          message: "sourcekit-lsp failed to encode a notification to the editor"
        )
        return
      case .request(_, _):
        // We want to send a request to the editor but failed to encode it. We don't know the `reply` handle for
        // the request at this point so we can't synthesize an errorResponse for the request. This means that the
        // request will never receive a reply. Inform the user about it.
        sendMessageCodingErrorNotificationToClient(
          message: "sourcekit-lsp failed to encode a request to the editor"
        )
        return
      case .response(_, _):
        // The editor sent a request to sourcekit-lsp, which failed but we can't serialize the result back to the
        // client. This means that the request will never receive a reply. Inform the user about it and accept that
        // we'll never send a reply.
        sendMessageCodingErrorNotificationToClient(
          message: "sourcekit-lsp failed to encode a response to the editor"
        )
        return
      case .errorResponse(_, _):
        // Same as `.response`. Has an optional `id`, so can't share the case.
        sendMessageCodingErrorNotificationToClient(
          message: "sourcekit-lsp failed to encode an error response to the editor"
        )
        return
      }
    }

    let header = "Content-Length: \(content.count)\r\n\r\n"
    sendContinuation.yield(Data(header.utf8))
    sendContinuation.yield(content)
  }
}
