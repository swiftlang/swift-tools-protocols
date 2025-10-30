add_library(BuildServerProtocol
  Messages.swift

  Messages/BuildShutdownRequest.swift
  Messages/BuildTargetPrepareRequest.swift
  Messages/BuildTargetSourcesRequest.swift
  Messages/InitializeBuildRequest.swift
  Messages/OnBuildExitNotification.swift
  Messages/OnBuildInitializedNotification.swift
  Messages/OnBuildLogMessageNotification.swift
  Messages/OnBuildTargetDidChangeNotification.swift
  Messages/OnWatchedFilesDidChangeNotification.swift
  Messages/RegisterForChangeNotifications.swift
  Messages/TaskFinishNotification.swift
  Messages/TaskProgressNotification.swift
  Messages/TaskStartNotification.swift
  Messages/TextDocumentSourceKitOptionsRequest.swift
  Messages/WorkspaceBuildTargetsRequest.swift
  Messages/WorkspaceWaitForBuildSystemUpdates.swift

  SupportTypes/BuildTarget.swift
  SupportTypes/MessageType.swift
  SupportTypes/MillisecondsSince1970Date.swift
  SupportTypes/StatusCode.swift
  SupportTypes/TaskId.swift
  SupportTypes/TextDocumentIdentifier.swift)
set_target_properties(BuildServerProtocol PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildServerProtocol PRIVATE
  LanguageServerProtocol)

set_property(GLOBAL APPEND PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS BuildServerProtocol)

install(TARGETS BuildServerProtocol
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
