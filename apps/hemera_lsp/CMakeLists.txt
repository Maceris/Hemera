# hemera-lsp: the Hemera language server, which an editor starts and speaks the Language Server Protocol to over
# standard input and output (docs/editor.md). hemera-lsp-debug for Debug, so both builds can be on PATH and be run by
# name. What it does is in HemeraLspLib, so the tests drive it without a client.
ADD_LIBRARY(HemeraLspLib STATIC
  src/checker.cpp
  src/checker.h
  src/documents.cpp
  src/documents.h
  src/features.cpp
  src/features.h
  src/index.cpp
  src/index.h
  src/parsing.cpp
  src/parsing.h
  src/protocol.cpp
  src/protocol.h
  src/serve_client.cpp
  src/serve_client.h
  src/server.cpp
  src/server.h
  src/uri.cpp
  src/uri.h
)
TARGET_INCLUDE_DIRECTORIES(HemeraLspLib PUBLIC src)
TARGET_INCLUDE_DIRECTORIES(HemeraLspLib SYSTEM PUBLIC ${HEMERA_TOOL_LLVM_INCLUDES})
TARGET_LINK_LIBRARIES(HemeraLspLib PUBLIC HemeraLib)
TARGET_COMPILE_DEFINITIONS(HemeraLspLib PRIVATE ${HEMERA_TOOL_DEFINITIONS})
TARGET_COMPILE_OPTIONS(HemeraLspLib PRIVATE ${HEMERA_TOOL_OPTIONS})
ADD_DEPENDENCIES(HemeraLspLib HemeraGenerated)
SET_TARGET_PROPERTIES(HemeraLspLib PROPERTIES MSVC_RUNTIME_LIBRARY "${HEMERA_TOOL_RUNTIME_LIBRARY}")

ADD_EXECUTABLE(HemeraLsp src/main.cpp ${HEMERA_TOOL_MANIFEST})
TARGET_LINK_LIBRARIES(HemeraLsp HemeraLspLib)
TARGET_COMPILE_DEFINITIONS(HemeraLsp PRIVATE ${HEMERA_TOOL_DEFINITIONS})
TARGET_COMPILE_OPTIONS(HemeraLsp PRIVATE ${HEMERA_TOOL_OPTIONS})
SET_TARGET_PROPERTIES(HemeraLsp PROPERTIES OUTPUT_NAME "hemera-lsp" OUTPUT_NAME_DEBUG "hemera-lsp-debug"
  MSVC_RUNTIME_LIBRARY "${HEMERA_TOOL_RUNTIME_LIBRARY}")
IF(MSVC)
  # A PDB for Release too, so a crash has names
  TARGET_LINK_OPTIONS(HemeraLsp PRIVATE $<$<CONFIG:Release>:/DEBUG /OPT:REF /OPT:ICF>)
ENDIF()

ADD_EXECUTABLE(HemeraLspTest
  test/checker_test.cpp
  test/documents_test.cpp
  test/features_test.cpp
  test/index_test.cpp
  test/parsing_test.cpp
  test/protocol_test.cpp
  test/server_test.cpp
  test/uri_test.cpp
)
TARGET_LINK_LIBRARIES(HemeraLspTest HemeraLspLib GTest::gtest_main GTest::gtest)
TARGET_COMPILE_DEFINITIONS(HemeraLspTest PRIVATE ${HEMERA_TOOL_DEFINITIONS})
TARGET_COMPILE_OPTIONS(HemeraLspTest PRIVATE ${HEMERA_TOOL_TEST_OPTIONS})
SET_TARGET_PROPERTIES(HemeraLspTest PROPERTIES MSVC_RUNTIME_LIBRARY "${HEMERA_TOOL_RUNTIME_LIBRARY}")
gtest_discover_tests(HemeraLspTest)
