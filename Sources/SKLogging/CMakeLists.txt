set(sources
  CustomLogStringConvertible.swift
  Error+ForLogging.swift
  Logging.swift
  LoggingScope.swift
  NonDarwinLogging.swift
  OrLog.swift
  SetGlobalLogFileHandler.swift
  SplitLogMessage.swift)

add_library(SKLogging STATIC ${sources})
set_target_properties(SKLogging PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SKLogging PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(SKLogging PUBLIC
  ToolsProtocolsSwiftExtensions)

add_library(_SKLoggingForPlugin STATIC ${sources})
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
