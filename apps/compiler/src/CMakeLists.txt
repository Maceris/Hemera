# Hemera compiler source

CMAKE_MINIMUM_REQUIRED(VERSION 3.20.0...4.3.3)

ADD_EXECUTABLE(generate_errors ${SOURCE_DIR}/error/generate_errors.cpp)

TARGET_COMPILE_DEFINITIONS(generate_errors PRIVATE ${HEMERA_DEFINITIONS})
TARGET_COMPILE_OPTIONS(generate_errors PRIVATE ${HEMERA_OPTIONS} ${HEMERA_WARNING_OPTIONS})

SET_TARGET_PROPERTIES(generate_errors PROPERTIES OUTPUT_NAME generate_errors)

ADD_CUSTOM_COMMAND(
  OUTPUT
    ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.h 
    ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.cpp
  COMMAND generate_errors hemera_errors hpp ${ROOT_DIR}/include/error/errors_template.h > ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.h
  COMMAND generate_errors hemera_errors cpp ${ROOT_DIR}/include/error/errors_template.h > ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.cpp
  DEPENDS generate_errors ${ROOT_DIR}/include/error/errors_template.h
)
SET(HEMERA_GENERATED
  ${HEMERA_GENERATED}
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.h
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.cpp
)

ADD_CUSTOM_COMMAND(
  OUTPUT
    ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.h
    ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.cpp
  COMMAND generate_errors hemera_warnings hpp ${ROOT_DIR}/include/error/warnings_template.h > ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.h
  COMMAND generate_errors hemera_warnings cpp ${ROOT_DIR}/include/error/warnings_template.h > ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.cpp
  DEPENDS generate_errors ${ROOT_DIR}/include/error/warnings_template.h
)

SET(HEMERA_GENERATED 
  ${HEMERA_GENERATED}
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.h
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.cpp
)

ADD_CUSTOM_TARGET(HemeraGenerated DEPENDS ${HEMERA_GENERATED})

SET(HEADER_FILES
  ${INCLUDE_DIR}/job.h
  ${INCLUDE_DIR}/version.h
  ${INCLUDE_DIR}/back_end/back_end.h
  ${INCLUDE_DIR}/cmd_line/arg_parsing.h
  ${INCLUDE_DIR}/cmd_line/cmd_line_utils.h
  ${INCLUDE_DIR}/cmd_line/options.h
  ${INCLUDE_DIR}/error/errors_template.h
  ${INCLUDE_DIR}/error/reporting.h
  ${INCLUDE_DIR}/error/warnings_template.h
  ${INCLUDE_DIR}/front_end/event.h
  ${INCLUDE_DIR}/front_end/front_end.h
  ${INCLUDE_DIR}/front_end/hlir.h
  ${INCLUDE_DIR}/front_end/hlir_generation.h
  ${INCLUDE_DIR}/front_end/info.h
  ${INCLUDE_DIR}/front_end/type.h
  ${INCLUDE_DIR}/front_end/type_checking.h
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
  ${SOURCE_DIR}/back_end/llvm.cpp
  ${SOURCE_DIR}/cmd_line/arg_parsing.cpp
  ${SOURCE_DIR}/cmd_line/cmd_line_utils.cpp
  ${SOURCE_DIR}/cmd_line/options.cpp
  ${SOURCE_DIR}/error/reporting.cpp
  ${SOURCE_DIR}/front_end/front_end.cpp
  ${SOURCE_DIR}/front_end/hlir.cpp
  ${SOURCE_DIR}/front_end/hlir_generation.cpp
  ${SOURCE_DIR}/front_end/info.cpp
  ${SOURCE_DIR}/front_end/type.cpp
  ${SOURCE_DIR}/front_end/type_checking.cpp
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
  ${TEST_DIR}/front_end/hlir_test.cpp
  ${TEST_DIR}/lexer/lexer_test.cpp
  ${TEST_DIR}/parser/parser_test.cpp
)

ADD_LIBRARY(HemeraLib
  ${HEADER_FILES}
  ${THIRD_PARTY_HEADER_FILES}
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.h
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.h
  
  ${SOURCE_FILES}
)

ADD_EXECUTABLE(Hemera
  ${HEADER_FILES}
  ${THIRD_PARTY_HEADER_FILES}
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.cpp
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.cpp

  ${SOURCE_DIR}/main.cpp
)

llvm_map_components_to_libnames(llvm_libs
  aarch64codegen
  aarch64desc
  aarch64info
  aarch64utils
  analysis
  armcodegen
  armdesc
  arminfo
  armutils
  codegen
  codegentypes
  core
  debuginfopdb
  ipo
  irreader
  linker
  native
  nativecodegen
  scalaropts
  support
  transformutils
  vectorize
  x86codegen
  x86desc
  x86info
  x86targetmca
)
SEPARATE_ARGUMENTS(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
TARGET_LINK_LIBRARIES(HemeraLib PUBLIC
  ${llvm_libs}
  HMIR
)

TARGET_INCLUDE_DIRECTORIES(HemeraLib PUBLIC
  ${INCLUDE_DIR}/
  $<BUILD_INTERFACE:${HEMERA_LIBRARY_OUTPUT_DIRECTORY}>
)

IF(MSVC)
  # Intellisense doesn't play well with the clang-cl SYSTEM PRIVATE includes
  LIST(APPEND CMAKE_VS_SDK_INCLUDE_DIRECTORIES ${THIRD_PARTY_DIR}/googletest/googletest/include)
ENDIF()

TARGET_INCLUDE_DIRECTORIES(Hemera PUBLIC
  ${INCLUDE_DIR}/
)

SOURCE_GROUP(TREE ${INCLUDE_DIR} PREFIX "include" FILES ${HEADER_FILES})
SOURCE_GROUP(TREE ${SOURCE_DIR} PREFIX "src" FILES ${SOURCE_FILES})
SOURCE_GROUP(TREE ${TEST_DIR} PREFIX "test" FILES ${TEST_FILES})

TARGET_LINK_LIBRARIES(Hemera HemeraLib)
SET_TARGET_PROPERTIES(Hemera PROPERTIES OUTPUT_NAME "hemera")
TARGET_COMPILE_DEFINITIONS(HemeraLib PRIVATE ${HEMERA_DEFINITIONS} ${LLVM_DEFINITIONS_LIST})
TARGET_COMPILE_DEFINITIONS(Hemera PRIVATE ${HEMERA_DEFINITIONS})
TARGET_COMPILE_OPTIONS(HemeraLib PRIVATE ${HEMERA_OPTIONS} ${HEMERA_WARNING_OPTIONS})
TARGET_COMPILE_OPTIONS(Hemera PRIVATE ${HEMERA_OPTIONS} ${HEMERA_WARNING_OPTIONS})

ADD_DEPENDENCIES(Hemera HemeraGenerated)

enable_testing()

ADD_EXECUTABLE(HemeraTest
  ${HEADER_FILES}
  ${THIRD_PARTY_HEADER_FILES}
  
  ${TEST_FILES}
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_errors.cpp
  ${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/hemera_warnings.cpp
)

TARGET_COMPILE_OPTIONS(HemeraTest PRIVATE ${HEMERA_OPTIONS})
TARGET_COMPILE_DEFINITIONS(HemeraTest PRIVATE ${HEMERA_DEFINITIONS})
TARGET_INCLUDE_DIRECTORIES(HemeraTest SYSTEM PRIVATE
  ${THIRD_PARTY_DIR}/googletest/googletest/include
)

TARGET_LINK_LIBRARIES(HemeraTest
  GTest::gtest_main
  GTest::gtest
  HemeraLib
  ${llvm_libs}
)

gtest_discover_tests(HemeraTest)
