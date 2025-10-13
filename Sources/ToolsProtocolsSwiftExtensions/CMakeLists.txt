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

add_library(ToolsProtocolsSwiftExtensions STATIC ${sources})
set_target_properties(ToolsProtocolsSwiftExtensions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(ToolsProtocolsSwiftExtensions PUBLIC
  ToolsProtocolsCAtomics)
target_link_libraries(ToolsProtocolsSwiftExtensions PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

add_library(ToolsProtocolsSwiftExtensionsForPlugin STATIC ${sources})
set_target_properties(ToolsProtocolsSwiftExtensionsForPlugin PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(ToolsProtocolsSwiftExtensionsForPlugin PUBLIC
  ToolsProtocolsCAtomics)
target_link_libraries(ToolsProtocolsSwiftExtensionsForPlugin PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

set_property(GLOBAL APPEND PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS ToolsProtocolsSwiftExtensions)
