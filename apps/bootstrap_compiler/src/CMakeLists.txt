# Hemera compiler source

CMAKE_MINIMUM_REQUIRED(VERSION 3.13...3.31.4)

SET(HEADER_FILES
  ${INCLUDE_DIR}/job.h
  ${INCLUDE_DIR}/version.h
  ${INCLUDE_DIR}/cmd_line/arg_parsing.h
  ${INCLUDE_DIR}/error/reporting.h
  ${INCLUDE_DIR}/front_end/event.h
  ${INCLUDE_DIR}/front_end/front_end.h
  ${INCLUDE_DIR}/front_end/hlir.h
  ${INCLUDE_DIR}/front_end/info.h
  ${INCLUDE_DIR}/front_end/mlir.h
  ${INCLUDE_DIR}/front_end/type.h
  ${INCLUDE_DIR}/front_end/type_id.h
  ${INCLUDE_DIR}/front_end/work.h
  ${INCLUDE_DIR}/lexer/lexer.h
  ${INCLUDE_DIR}/lexer/token.h
  ${INCLUDE_DIR}/memory/allocator.h
  ${INCLUDE_DIR}/memory/thread_safe_queue.h
  ${INCLUDE_DIR}/parser/ast_types.h
  ${INCLUDE_DIR}/parser/parser.h
  ${INCLUDE_DIR}/types/primitives.h
  ${INCLUDE_DIR}/util/logger.h
  ${INCLUDE_DIR}/util/thread_pool.h
)

SET(SOURCE_FILES
  ${SOURCE_DIR}/cmd_line/arg_parsing.cpp
  ${SOURCE_DIR}/error/reporting.cpp
  ${SOURCE_DIR}/front_end/front_end.cpp
  ${SOURCE_DIR}/front_end/info.cpp
  ${SOURCE_DIR}/front_end/type.cpp
  ${SOURCE_DIR}/front_end/work.cpp
  ${SOURCE_DIR}/lexer/lexer.cpp 
  ${SOURCE_DIR}/lexer/token.cpp
  ${SOURCE_DIR}/memory/allocator.cpp
  ${SOURCE_DIR}/parser/ast_types.cpp
  ${SOURCE_DIR}/parser/parser.cpp
  ${SOURCE_DIR}/util/logger.cpp
  ${SOURCE_DIR}/util/thread_pool.cpp
)

SET(THIRD_PARTY_HEADER_FILES
  
)

SET(TEST_FILES
  ${TEST_DIR}/main.cpp
  ${TEST_DIR}/cmd_line/arg_parsing_test.cpp
  ${TEST_DIR}/lexer/lexer_test.cpp
  ${TEST_DIR}/parser/parser_test.cpp
)

ADD_LIBRARY(HemeraLib
  ${HEADER_FILES}
  ${THIRD_PARTY_HEADER_FILES}
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/errors.h
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/warnings.h
  
  ${SOURCE_FILES}
)

ADD_EXECUTABLE(Hemera
  ${HEADER_FILES}
  ${THIRD_PARTY_HEADER_FILES}

  ${SOURCE_DIR}/main.cpp
)

TARGET_INCLUDE_DIRECTORIES(HemeraLib PUBLIC
  ${INCLUDE_DIR}/
  $<BUILD_INTERFACE:${HEMERA_LIBRARY_OUTPUT_DIRECTORY}>
)

TARGET_INCLUDE_DIRECTORIES(Hemera PUBLIC
  ${INCLUDE_DIR}/
)

SOURCE_GROUP(TREE ${INCLUDE_DIR} PREFIX "include" FILES ${HEADER_FILES})
SOURCE_GROUP(TREE ${SOURCE_DIR} PREFIX "src" FILES ${SOURCE_FILES})
SOURCE_GROUP(TREE ${TEST_DIR} PREFIX "test" FILES ${TEST_FILES})

TARGET_USE_COMMON_OUTPUT_DIRECTORY(HemeraLib)
TARGET_USE_COMMON_OUTPUT_DIRECTORY(Hemera)

TARGET_LINK_LIBRARIES(Hemera HemeraLib)
SET_TARGET_PROPERTIES(Hemera PROPERTIES OUTPUT_NAME "hemera")
TARGET_COMPILE_DEFINITIONS(HemeraLib PRIVATE ${HEMERA_DEFINITIONS})
TARGET_COMPILE_DEFINITIONS(Hemera PRIVATE ${HEMERA_DEFINITIONS})
TARGET_COMPILE_OPTIONS(HemeraLib PRIVATE ${HEMERA_OPTIONS})
TARGET_COMPILE_OPTIONS(Hemera PRIVATE ${HEMERA_OPTIONS})

ADD_DEPENDENCIES(Hemera HemeraGenerated)

enable_testing()

ADD_EXECUTABLE(HemeraTest
  ${HEADER_FILES}
  ${THIRD_PARTY_HEADER_FILES}
  
  ${TEST_FILES}
)

TARGET_USE_COMMON_OUTPUT_DIRECTORY(HemeraTest)
TARGET_USE_COMMON_OUTPUT_DIRECTORY(gtest)
TARGET_USE_COMMON_OUTPUT_DIRECTORY(gtest_main)

TARGET_LINK_LIBRARIES(HemeraTest
  GTest::gtest_main
  GTest::gtest
  HemeraLib
)

gtest_discover_tests(HemeraTest)
