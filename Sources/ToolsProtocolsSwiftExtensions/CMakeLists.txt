set(sources
  AsyncQueue.swift
  AsyncUtils.swift
  Atomics.swift
  Collection+Only.swift
  Duration+Seconds.swift
  FileManagerExtensions.swift
  NSLock+WithLock.swift
  PipeAsStringHandler.swift
  Task+WithPriorityChangedHandler.swift
  ThreadSafeBox.swift
  URLExtensions.swift
)

add_library(ToolsProtocolsSwiftExtensions ${sources})
set_target_properties(ToolsProtocolsSwiftExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(ToolsProtocolsSwiftExtensions PUBLIC
  ToolsProtocolsCAtomics)
target_link_libraries(ToolsProtocolsSwiftExtensions PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

add_library(_ToolsProtocolsSwiftExtensionsForPlugin ${sources})
set_target_properties(_ToolsProtocolsSwiftExtensionsForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(_ToolsProtocolsSwiftExtensionsForPlugin PUBLIC
  ToolsProtocolsCAtomics)
target_link_libraries(_ToolsProtocolsSwiftExtensionsForPlugin PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

set_property(GLOBAL APPEND PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS ToolsProtocolsSwiftExtensions)
set_property(GLOBAL APPEND PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS _ToolsProtocolsSwiftExtensionsForPlugin)

install(TARGETS ToolsProtocolsSwiftExtensions
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(TARGETS _ToolsProtocolsSwiftExtensionsForPlugin
  ARCHIVE DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${${PROJECT_NAME}_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
