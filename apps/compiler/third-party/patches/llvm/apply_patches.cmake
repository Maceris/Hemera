# Applies the LLVM patches in this folder to the llvm-project submodule, in order, skipping any already applied, so a
# fresh clone builds the patched compiler without a manual step. Included by the compiler's CMakeLists.txt before it
# adds LLVM, and runnable on its own:
#
#     cmake -DLLVM_SOURCE_DIR=<llvm-project> -P apply_patches.cmake
#
# A patch that's neither applied nor applies cleanly (after updating LLVM, say) stops configuring with the reason.

IF(NOT LLVM_SOURCE_DIR)
  MESSAGE(FATAL_ERROR "apply_patches.cmake needs LLVM_SOURCE_DIR, the llvm-project checkout")
ENDIF()
FIND_PACKAGE(Git QUIET)
IF(NOT GIT_FOUND)
  MESSAGE(FATAL_ERROR "Applying the LLVM patches needs git")
ENDIF()

FILE(GLOB HEMERA_LLVM_PATCHES ${CMAKE_CURRENT_LIST_DIR}/*.patch)
LIST(SORT HEMERA_LLVM_PATCHES)
FOREACH(HEMERA_PATCH ${HEMERA_LLVM_PATCHES})
  GET_FILENAME_COMPONENT(HEMERA_PATCH_NAME ${HEMERA_PATCH} NAME)
  # Applied already: it reverses cleanly
  EXECUTE_PROCESS(COMMAND ${GIT_EXECUTABLE} apply --reverse --check ${HEMERA_PATCH}
    WORKING_DIRECTORY ${LLVM_SOURCE_DIR} RESULT_VARIABLE HEMERA_PATCH_APPLIED OUTPUT_QUIET ERROR_QUIET)
  IF(HEMERA_PATCH_APPLIED EQUAL 0)
    CONTINUE()
  ENDIF()
  EXECUTE_PROCESS(COMMAND ${GIT_EXECUTABLE} apply ${HEMERA_PATCH}
    WORKING_DIRECTORY ${LLVM_SOURCE_DIR} RESULT_VARIABLE HEMERA_PATCH_FAILED ERROR_VARIABLE HEMERA_PATCH_ERROR)
  IF(NOT HEMERA_PATCH_FAILED EQUAL 0)
    MESSAGE(FATAL_ERROR "The LLVM patch ${HEMERA_PATCH_NAME} doesn't apply to ${LLVM_SOURCE_DIR}:\n${HEMERA_PATCH_ERROR}")
  ENDIF()
  MESSAGE(STATUS "Applied the LLVM patch ${HEMERA_PATCH_NAME}")
ENDFOREACH()
