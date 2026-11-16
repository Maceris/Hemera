# Hemera compiler source

CMAKE_MINIMUM_REQUIRED(VERSION 3.20.0...4.3.3)

ADD_EXECUTABLE(generate_errors ${SOURCE_DIR}/error/generate_errors.cpp)

TARGET_COMPILE_DEFINITIONS(generate_errors PRIVATE ${HEMERA_DEFINITIONS})
TARGET_COMPILE_OPTIONS(generate_errors PRIVATE ${HEMERA_OPTIONS} ${HEMERA_WARNING_OPTIONS})

SET_TARGET_PROPERTIES(generate_errors PROPERTIES OUTPUT_NAME generate_errors)

# The commands below write into it with the shell's redirection, which doesn't make folders
FILE(MAKE_DIRECTORY ${HEMERA_GENERATED_DIR})

ADD_CUSTOM_COMMAND(
  OUTPUT
    ${HEMERA_GENERATED_DIR}/hemera_errors.h 
    ${HEMERA_GENERATED_DIR}/hemera_errors.cpp
  COMMAND generate_errors hemera_errors hpp ${ROOT_DIR}/include/error/errors_template.h > ${HEMERA_GENERATED_DIR}/hemera_errors.h
  COMMAND generate_errors hemera_errors cpp ${ROOT_DIR}/include/error/errors_template.h > ${HEMERA_GENERATED_DIR}/hemera_errors.cpp
  DEPENDS generate_errors ${ROOT_DIR}/include/error/errors_template.h
)
SET(HEMERA_GENERATED
  ${HEMERA_GENERATED}
  ${HEMERA_GENERATED_DIR}/hemera_errors.h
  ${HEMERA_GENERATED_DIR}/hemera_errors.cpp
)

ADD_CUSTOM_COMMAND(
  OUTPUT
    ${HEMERA_GENERATED_DIR}/hemera_warnings.h
    ${HEMERA_GENERATED_DIR}/hemera_warnings.cpp
  COMMAND generate_errors hemera_warnings hpp ${ROOT_DIR}/include/error/warnings_template.h > ${HEMERA_GENERATED_DIR}/hemera_warnings.h
  COMMAND generate_errors hemera_warnings cpp ${ROOT_DIR}/include/error/warnings_template.h > ${HEMERA_GENERATED_DIR}/hemera_warnings.cpp
  DEPENDS generate_errors ${ROOT_DIR}/include/error/warnings_template.h
)

SET(HEMERA_GENERATED 
  ${HEMERA_GENERATED}
  ${HEMERA_GENERATED_DIR}/hemera_warnings.h
  ${HEMERA_GENERATED_DIR}/hemera_warnings.cpp
)

# base is built into the compiler, which supplies it rather than reading it while compiling
FILE(GLOB_RECURSE HEMERA_BASE_SOURCES CONFIGURE_DEPENDS ${ROOT_DIR}/../../base/*.hsc)
ADD_CUSTOM_COMMAND(
  OUTPUT ${HEMERA_GENERATED_DIR}/hemera_base.cpp
  COMMAND ${CMAKE_COMMAND} -DBASE_DIR=${ROOT_DIR}/../../base -DOUTPUT=${HEMERA_GENERATED_DIR}/hemera_base.cpp -P ${SOURCE_DIR}/front_end/embed_base.cmake
  DEPENDS ${SOURCE_DIR}/front_end/embed_base.cmake ${HEMERA_BASE_SOURCES}
)
SET(HEMERA_GENERATED
  ${HEMERA_GENERATED}
  ${HEMERA_GENERATED_DIR}/hemera_base.cpp
)

ADD_CUSTOM_TARGET(HemeraGenerated DEPENDS ${HEMERA_GENERATED})

SET(HEADER_FILES
  ${INCLUDE_DIR}/job.h
  ${INCLUDE_DIR}/version.h
  ${INCLUDE_DIR}/back_end/back_end.h
  ${INCLUDE_DIR}/back_end/symbolize.h
  ${INCLUDE_DIR}/back_end/check_interface.h
  ${INCLUDE_DIR}/cmd_line/arg_parsing.h
  ${INCLUDE_DIR}/cmd_line/cmd_line_utils.h
  ${INCLUDE_DIR}/cmd_line/options.h
  ${INCLUDE_DIR}/error/errors_template.h
  ${INCLUDE_DIR}/error/reporting.h
  ${INCLUDE_DIR}/error/warnings_template.h
  ${INCLUDE_DIR}/front_end/base_sources.h
  ${INCLUDE_DIR}/front_end/bounds.h
  ${INCLUDE_DIR}/front_end/checking.h
  ${INCLUDE_DIR}/front_end/documentation.h
  ${INCLUDE_DIR}/front_end/stack_pointers.h
  ${INCLUDE_DIR}/front_end/event.h
  ${INCLUDE_DIR}/front_end/front_end.h
  ${INCLUDE_DIR}/front_end/name_index.h
  ${INCLUDE_DIR}/front_end/names.h
  ${INCLUDE_DIR}/front_end/info.h
  ${INCLUDE_DIR}/front_end/type.h
  ${INCLUDE_DIR}/front_end/type_id.h
  ${INCLUDE_DIR}/front_end/walk.h
  ${INCLUDE_DIR}/front_end/work.h
  ${INCLUDE_DIR}/lexer/identifier_security.h
  ${INCLUDE_DIR}/lexer/identifiers.h
  ${INCLUDE_DIR}/lexer/lexer.h
  ${INCLUDE_DIR}/lexer/token.h
  ${INCLUDE_DIR}/memory/allocator.h
  ${INCLUDE_DIR}/memory/thread_safe_queue.h
  ${INCLUDE_DIR}/middle_end/generate.h
  ${INCLUDE_DIR}/middle_end/jit.h
  ${INCLUDE_DIR}/middle_end/reflection.h
  ${INCLUDE_DIR}/middle_end/serve.h
  ${INCLUDE_DIR}/middle_end/schema_writer.h
  ${INCLUDE_DIR}/middle_end/build.h
  ${INCLUDE_DIR}/middle_end/code_values.h
  ${INCLUDE_DIR}/parser/ast_types.h
  ${INCLUDE_DIR}/parser/formatting.h
  ${INCLUDE_DIR}/parser/layout.h
  ${INCLUDE_DIR}/parser/parser.h
  ${INCLUDE_DIR}/parser/printing.h
  ${INCLUDE_DIR}/types/primitives.h
  ${INCLUDE_DIR}/util/console.h
  ${INCLUDE_DIR}/util/crash_dump.h
  ${INCLUDE_DIR}/util/logger.h
  ${INCLUDE_DIR}/util/thread_pool.h
  ${INCLUDE_DIR}/util/utf8.h
)

SET(SOURCE_FILES
  ${SOURCE_DIR}/back_end/llvm.cpp
  ${SOURCE_DIR}/back_end/symbolize.cpp
  ${SOURCE_DIR}/back_end/check_interface.cpp
  ${SOURCE_DIR}/cmd_line/arg_parsing.cpp
  ${SOURCE_DIR}/cmd_line/cmd_line_utils.cpp
  ${SOURCE_DIR}/cmd_line/options.cpp
  ${SOURCE_DIR}/error/reporting.cpp
  ${SOURCE_DIR}/front_end/bounds.cpp
  ${SOURCE_DIR}/front_end/constraints.cpp
  ${SOURCE_DIR}/front_end/early.cpp
  ${SOURCE_DIR}/front_end/format_spec.cpp
  ${SOURCE_DIR}/front_end/ownership.cpp
  ${SOURCE_DIR}/front_end/checking.cpp
  ${SOURCE_DIR}/front_end/declarations.cpp
  ${SOURCE_DIR}/front_end/documentation.cpp
  ${SOURCE_DIR}/front_end/front_end.cpp
  ${SOURCE_DIR}/front_end/name_index.cpp
  ${SOURCE_DIR}/front_end/names.cpp
  ${SOURCE_DIR}/front_end/stack_pointers.cpp
  ${SOURCE_DIR}/front_end/info.cpp
  ${SOURCE_DIR}/front_end/type.cpp
  ${SOURCE_DIR}/front_end/work.cpp
  ${SOURCE_DIR}/lexer/identifier_security.cpp
  ${SOURCE_DIR}/lexer/identifier_security_tables.h
  ${SOURCE_DIR}/lexer/identifiers.cpp
  ${SOURCE_DIR}/lexer/identifier_tables.h
  ${SOURCE_DIR}/lexer/lexer.cpp
  ${SOURCE_DIR}/lexer/token.cpp
  ${SOURCE_DIR}/memory/allocator.cpp
  ${SOURCE_DIR}/middle_end/generate.cpp
  ${SOURCE_DIR}/middle_end/jit.cpp
  ${SOURCE_DIR}/middle_end/reflection.cpp
  ${SOURCE_DIR}/middle_end/serve.cpp
  ${SOURCE_DIR}/middle_end/schema_writer.cpp
  ${SOURCE_DIR}/middle_end/build.cpp
  ${SOURCE_DIR}/middle_end/code_values.cpp
  ${SOURCE_DIR}/parser/ast_types.cpp
  ${SOURCE_DIR}/parser/formatting.cpp
  ${SOURCE_DIR}/parser/layout.cpp
  ${SOURCE_DIR}/parser/parser.cpp
  ${SOURCE_DIR}/parser/printing.cpp
  ${SOURCE_DIR}/util/console.cpp
  ${SOURCE_DIR}/util/crash_dump.cpp
  ${SOURCE_DIR}/util/logger.cpp
  ${SOURCE_DIR}/util/thread_pool.cpp
)

SET(TEST_FILES
  ${TEST_DIR}/main.cpp
  ${TEST_DIR}/string_cache_guard.h
  ${TEST_DIR}/back_end/freestanding_test.cpp
  ${TEST_DIR}/back_end/hosted_test.cpp
  ${TEST_DIR}/cmd_line/arg_parsing_test.cpp
  ${TEST_DIR}/error/reporting_test.cpp
  ${TEST_DIR}/front_end/front_end_test.cpp
  ${TEST_DIR}/lexer/lexer_test.cpp
  ${TEST_DIR}/parser/layout_test.cpp
  ${TEST_DIR}/parser/parser_test.cpp
)

llvm_map_components_to_libnames(llvm_libs
  aarch64asmparser
  aarch64codegen
  aarch64desc
  aarch64info
  aarch64utils
  analysis
  bitreader
  bitwriter
  armasmparser
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
  object
  orcjit
  scalaropts
  support
  symbolize
  transformutils
  vectorize
  x86asmparser
  x86codegen
  x86desc
  x86info
  x86targetmca
)
SEPARATE_ARGUMENTS(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})

# On Windows, every program linking the compiler's library has this manifest, which makes UTF-8 the process's code
# page, so paths and the command line are UTF-8 there as everywhere else in the compiler
IF(WIN32)
  SET(HEMERA_MANIFEST ${SOURCE_DIR}/utf8.manifest)
ENDIF()

# A compiler: the library LIBRARY, of everything but main and the generated sources too, for the compiler's tests and
# the tools built on it; and the program PROGRAM, which is main linked with it
FUNCTION(HEMERA_ADD_COMPILER LIBRARY PROGRAM)
  ADD_LIBRARY(${LIBRARY} ${HEADER_FILES} ${HEMERA_GENERATED} ${SOURCE_FILES})
  TARGET_LINK_LIBRARIES(${LIBRARY} PUBLIC
    ${llvm_libs}
    HMIR
    MLIRPass
    MLIRBuiltinToLLVMIRTranslation
    MLIRLLVMToLLVMIRTranslation
    MLIRTargetLLVMIRExport
  )
  TARGET_INCLUDE_DIRECTORIES(${LIBRARY} PUBLIC ${INCLUDE_DIR}/ $<BUILD_INTERFACE:${HEMERA_GENERATED_DIR}>)
  TARGET_COMPILE_DEFINITIONS(${LIBRARY} PRIVATE ${HEMERA_DEFINITIONS} ${LLVM_DEFINITIONS_LIST})
  TARGET_COMPILE_OPTIONS(${LIBRARY} PRIVATE ${HEMERA_OPTIONS} ${HEMERA_WARNING_OPTIONS})

  ADD_EXECUTABLE(${PROGRAM} ${HEADER_FILES} ${SOURCE_DIR}/main.cpp ${HEMERA_MANIFEST})
  TARGET_LINK_LIBRARIES(${PROGRAM} ${LIBRARY})
  TARGET_COMPILE_DEFINITIONS(${PROGRAM} PRIVATE ${HEMERA_DEFINITIONS})
  TARGET_COMPILE_OPTIONS(${PROGRAM} PRIVATE ${HEMERA_OPTIONS} ${HEMERA_WARNING_OPTIONS})
  ADD_DEPENDENCIES(${PROGRAM} HemeraGenerated)
ENDFUNCTION()

HEMERA_ADD_COMPILER(HemeraLib Hemera)
# hemera-debug for Debug, so both builds can be on PATH and be run by name
SET_TARGET_PROPERTIES(Hemera PROPERTIES OUTPUT_NAME "hemera" OUTPUT_NAME_DEBUG "hemera-debug")
IF(MSVC)
  # The Release compiler's PDB, from what /Zi compiled, without giving up unreferenced code being dropped
  TARGET_LINK_OPTIONS(Hemera PRIVATE $<$<CONFIG:Release>:/DEBUG /OPT:REF /OPT:ICF>)
ENDIF()

IF(MSVC)
  # Intellisense doesn't play well with the clang-cl SYSTEM PRIVATE includes
  LIST(APPEND CMAKE_VS_SDK_INCLUDE_DIRECTORIES ${THIRD_PARTY_DIR}/googletest/googletest/include)
ENDIF()

SOURCE_GROUP(TREE ${INCLUDE_DIR} PREFIX "include" FILES ${HEADER_FILES})
SOURCE_GROUP(TREE ${SOURCE_DIR} PREFIX "src" FILES ${SOURCE_FILES})
SOURCE_GROUP(TREE ${TEST_DIR} PREFIX "test" FILES ${TEST_FILES})

# The compiler with AddressSanitizer, for memory errors that only show now and then: hemera-asan.exe, with
# -DHEMERA_ASAN=ON. Only Hemera's own code is instrumented; LLVM and MLIR are the libraries the compiler links, so
# they aren't rebuilt for it. The ASan runtime's DLL has to be on the PATH, or next to it, to run.
OPTION(HEMERA_ASAN "Also build hemera-asan, the compiler with AddressSanitizer" OFF)
IF(HEMERA_ASAN)
  HEMERA_ADD_COMPILER(HemeraLibAsan HemeraAsan)
  SET_TARGET_PROPERTIES(HemeraAsan PROPERTIES OUTPUT_NAME "hemera-asan")
  # The standard library's container annotations off, as in the uninstrumented LLVM libraries, which the linker checks
  SET(HEMERA_ASAN_DEFINITIONS _DISABLE_STRING_ANNOTATION _DISABLE_VECTOR_ANNOTATION)
  TARGET_COMPILE_DEFINITIONS(HemeraLibAsan PRIVATE ${HEMERA_ASAN_DEFINITIONS})
  TARGET_COMPILE_DEFINITIONS(HemeraAsan PRIVATE ${HEMERA_ASAN_DEFINITIONS})
  TARGET_COMPILE_OPTIONS(HemeraLibAsan PRIVATE -fsanitize=address)
  TARGET_COMPILE_OPTIONS(HemeraAsan PRIVATE -fsanitize=address)
  IF(MSVC)
    # clang-cl's ASan runtime, from its own lib/clang/<version>/lib/windows: the dynamic one, as the CRT is; and a PDB
    GET_FILENAME_COMPONENT(HEMERA_CLANG_BIN ${CMAKE_CXX_COMPILER} DIRECTORY)
    FILE(GLOB HEMERA_ASAN_LIBRARY_DIRS ${HEMERA_CLANG_BIN}/../lib/clang/*/lib/windows)
    LIST(GET HEMERA_ASAN_LIBRARY_DIRS 0 HEMERA_ASAN_LIBRARY_DIR)
    TARGET_LINK_OPTIONS(HemeraAsan PRIVATE
      ${HEMERA_ASAN_LIBRARY_DIR}/clang_rt.asan_dynamic-x86_64.lib
      /wholearchive:${HEMERA_ASAN_LIBRARY_DIR}/clang_rt.asan_dynamic_runtime_thunk-x86_64.lib
      # Without folding identical data, which can put a string literal in another global's redzone
      $<$<CONFIG:Release>:/DEBUG /OPT:NOICF>
      # ASan's frames are several times larger: every thread's stack, reserved, is 64 MiB
      /STACK:67108864)
    # Its DLL next to the compiler, so it runs from there
    ADD_CUSTOM_COMMAND(TARGET HemeraAsan POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different ${HEMERA_ASAN_LIBRARY_DIR}/clang_rt.asan_dynamic-x86_64.dll $<TARGET_FILE_DIR:HemeraAsan>)
  ENDIF()
ENDIF()

enable_testing()

ADD_EXECUTABLE(HemeraTest ${HEADER_FILES} ${TEST_FILES} ${HEMERA_MANIFEST})

TARGET_COMPILE_OPTIONS(HemeraTest PRIVATE ${HEMERA_OPTIONS})
# Where tests write what they build, like the hosted test's program
TARGET_COMPILE_DEFINITIONS(HemeraTest PRIVATE ${HEMERA_DEFINITIONS} HEMERA_TEST_OUTPUT_DIR="${CMAKE_CURRENT_BINARY_DIR}/test_output"
  HEMERA_COMPILER="$<TARGET_FILE:Hemera>")
# The compiler itself, for the tests that run it as a program
ADD_DEPENDENCIES(HemeraTest Hemera)
TARGET_INCLUDE_DIRECTORIES(HemeraTest SYSTEM PRIVATE
  ${THIRD_PARTY_DIR}/googletest/googletest/include
)

TARGET_LINK_LIBRARIES(HemeraTest
  GTest::gtest_main
  GTest::gtest
  HemeraLib
)
IF(MSVC)
  # A PDB for the Release tests too, so a crash or a profile of them has names
  TARGET_LINK_OPTIONS(HemeraTest PRIVATE $<$<CONFIG:Release>:/DEBUG /OPT:REF /OPT:ICF>)
ENDIF()

gtest_discover_tests(HemeraTest)

# What a program built on the compiler's library compiles with, for apps/hemera_format and apps/hemera_lsp, which are
# directories of their own
SET(HEMERA_TOOL_DEFINITIONS ${HEMERA_DEFINITIONS} CACHE INTERNAL "")
SET(HEMERA_TOOL_OPTIONS ${HEMERA_OPTIONS} ${HEMERA_WARNING_OPTIONS} CACHE INTERNAL "")
# A tool's tests, which build as HemeraTest does, without the warnings gtest's macros set off
SET(HEMERA_TOOL_TEST_OPTIONS ${HEMERA_OPTIONS} CACHE INTERNAL "")
SET(HEMERA_TOOL_MANIFEST ${HEMERA_MANIFEST} CACHE INTERNAL "")
SET(HEMERA_TOOL_RUNTIME_LIBRARY ${CMAKE_MSVC_RUNTIME_LIBRARY} CACHE INTERNAL "")
# LLVM's headers, its own and those its build writes, for a tool that uses LLVM's support library, like JSON
SET(HEMERA_TOOL_LLVM_INCLUDES ${THIRD_PARTY_DIR}/llvm-project/llvm/include ${HEMERA_LLVM_BINARY_DIR}/include CACHE INTERNAL "")
