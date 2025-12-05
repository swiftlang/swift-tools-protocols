add_library(LanguageServerProtocolTransport
  BuildServerMessageDependencyTracker.swift
  Connection+Send.swift
  DisableSigpipe.swift
  DocumentURI+CustomLogStringConvertible.swift
  JSONRPCConnection.swift
  LocalConnection.swift
  LoggableMessageTypes.swift
  MessageCoding.swift
  MessageSplitting.swift
  QueueBasedMessageHandler.swift
  RequestAndReply.swift
  ResponseError+Init.swift)
set_target_properties(LanguageServerProtocolTransport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(LanguageServerProtocolTransport PRIVATE
  LanguageServerProtocol
  BuildServerProtocol
  SKLogging)
target_link_libraries(LanguageServerProtocolTransport PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:swiftDispatch>
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

set_property(GLOBAL APPEND PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS LanguageServerProtocolTransport)

install(TARGETS LanguageServerProtocolTransport
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
