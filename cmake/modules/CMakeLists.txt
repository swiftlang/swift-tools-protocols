##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set(SWIFTTOOLSPROTOCOLS_EXPORTS_FILE ${CMAKE_CURRENT_BINARY_DIR}/SwiftToolsProtocolsExports.cmake)

configure_file(SwiftToolsProtocolsConfig.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/SwiftToolsProtocolsConfig.cmake)

get_property(SWIFTTOOLSPROTOCOLS_EXPORTS GLOBAL PROPERTY SWIFTTOOLSPROTOCOLS_EXPORTS)
export(TARGETS ${SWIFTTOOLSPROTOCOLS_EXPORTS}
  NAMESPACE SwiftToolsProtocols::
  FILE ${SWIFTTOOLSPROTOCOLS_EXPORTS_FILE})
