
cmake_minimum_required(VERSION 3.16.1)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake/modules)

project(swift-tools-protocols
  LANGUAGES C Swift)

set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

add_compile_options(
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature InternalImportsByDefault>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature MemberImportVisibility>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature InferIsolatedConformances>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-upcoming-feature NonisolatedNonsendingByDefault>"
)

find_package(dispatch QUIET)
find_package(Foundation QUIET)

include(SwiftSupport)

add_subdirectory(Sources)
add_subdirectory(cmake/modules)
