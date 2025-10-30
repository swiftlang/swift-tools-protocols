set(sources
  CustomLogStringConvertible.swift
  Error+ForLogging.swift
  Logging.swift
  LoggingScope.swift
  NonDarwinLogging.swift
  OrLog.swift
  SetGlobalLogFileHandler.swift
  SplitLogMessage.swift)

add_library(SKLogging ${sources})
set_target_properties(SKLogging PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKLogging PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(SKLogging PUBLIC
  ToolsProtocolsSwiftExtensions)

add_library(_SKLoggingForPlugin ${sources})
set_target_properties(_SKLoggingForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_compile_options(_SKLoggingForPlugin PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:
    "SHELL:-module-alias ToolsProtocolsSwiftExtensions=_ToolsProtocolsSwiftExtensionsForPlugin"
  >)
target_link_libraries(_SKLoggingForPlugin PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(_SKLoggingForPlugin PUBLIC
  _ToolsProtocolsSwiftExtensionsForPlugin)

set_property(GLOBAL APPEND PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS SKLogging)
set_property(GLOBAL APPEND PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS _SKLoggingForPlugin)

install(TARGETS SKLogging
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(TARGETS _SKLoggingForPlugin
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
