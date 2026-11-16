# Hemera: the compiler and the tools built on it, sharing one build of LLVM. Configure with a preset from
# CMakePresets.json, which builds into build/<preset>.

CMAKE_MINIMUM_REQUIRED(VERSION 3.20.0...4.3.3)

PROJECT(Hemera LANGUAGES C CXX)

# Every project's programs in bin/<configuration> and libraries in lib/<configuration>, under the build folder
SET(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
SET(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
SET(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

ADD_SUBDIRECTORY(apps/compiler)

# The formatter, the language server and the VS Code extension, once they have a CMakeLists.txt of their own
FOREACH(HEMERA_TOOL hemera_format hemera_lsp hemera_vscode)
  IF(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/apps/${HEMERA_TOOL}/CMakeLists.txt)
    ADD_SUBDIRECTORY(apps/${HEMERA_TOOL})
  ENDIF()
ENDFOREACH()

SET_PROPERTY(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT Hemera)
