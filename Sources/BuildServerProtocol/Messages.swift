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

public import LanguageServerProtocol

public protocol BSPRequest: RequestType {}
public protocol BSPNotification: NotificationType {}

private let requestTypes: [_RequestType.Type] = [
  BuildShutdownRequest.self,
  BuildTargetPrepareRequest.self,
  BuildTargetSourcesRequest.self,
  CreateWorkDoneProgressRequest.self,
  InitializeBuildRequest.self,
  RegisterForChanges.self,
  TextDocumentSourceKitOptionsRequest.self,
  WorkspaceBuildTargetsRequest.self,
  WorkspaceWaitForBuildSystemUpdatesRequest.self,
]

private let notificationTypes: [NotificationType.Type] = [
  CancelRequestNotification.self,
  FileOptionsChangedNotification.self,
  OnBuildExitNotification.self,
  OnBuildInitializedNotification.self,
  OnBuildLogMessageNotification.self,
  OnBuildTargetDidChangeNotification.self,
  OnWatchedFilesDidChangeNotification.self,
  TaskFinishNotification.self,
  TaskProgressNotification.self,
  TaskStartNotification.self,
]

extension MessageRegistry {
  public static let bspProtocol: MessageRegistry =
    MessageRegistry(requests: requestTypes, notifications: notificationTypes, legacyNames: bspLegacyNames)

  /// Maps current `sourcekit/`-prefixed BSP method names to the legacy names used before the
  /// prefix migration. Consumed by `MessageRegistry` (incoming routing) and
  /// `LegacyNameFallbackConnection` (outgoing retries).
  ///
  /// This table is frozen. Do not add new entries for newly introduced methods.
  public static let bspLegacyNames: [String: String] = [
    BuildTargetPrepareRequest.method: "buildTarget/prepare",
    FileOptionsChangedNotification.method: "build/sourceKitOptionsChanged",
    TextDocumentSourceKitOptionsRequest.method: "textDocument/sourceKitOptions",
    WorkspaceWaitForBuildSystemUpdatesRequest.method: "workspace/waitForBuildSystemUpdates",
  ]
  #if compiler(>=6.6)
  #warning("Remove the legacy method names")
  #endif
}

@available(*, deprecated, message: "use MessageRegistry.bspProtocol instead")
public var bspRegistry: MessageRegistry { MessageRegistry.bspProtocol }
