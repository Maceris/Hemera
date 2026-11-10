# Applies the LLVM patches in this folder to the llvm-project submodule, in order, skipping those already applied, so a
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
# How many are applied already, as they're applied in order: up to the last that reverses cleanly. Each is checked from
# the last back, since an earlier patch that a later one changes the same lines as doesn't reverse on its own once the
# later one is applied
LIST(LENGTH HEMERA_LLVM_PATCHES HEMERA_PATCH_COUNT)
SET(HEMERA_PATCHES_APPLIED 0)
SET(HEMERA_PATCH_INDEX ${HEMERA_PATCH_COUNT})
WHILE(HEMERA_PATCH_INDEX GREATER 0)
  MATH(EXPR HEMERA_PATCH_INDEX "${HEMERA_PATCH_INDEX} - 1")
  LIST(GET HEMERA_LLVM_PATCHES ${HEMERA_PATCH_INDEX} HEMERA_PATCH)
  EXECUTE_PROCESS(COMMAND ${GIT_EXECUTABLE} apply --reverse --check ${HEMERA_PATCH}
    WORKING_DIRECTORY ${LLVM_SOURCE_DIR} RESULT_VARIABLE HEMERA_PATCH_APPLIED OUTPUT_QUIET ERROR_QUIET)
  IF(HEMERA_PATCH_APPLIED EQUAL 0)
    MATH(EXPR HEMERA_PATCHES_APPLIED "${HEMERA_PATCH_INDEX} + 1")
    BREAK()
  ENDIF()
ENDWHILE()
SET(HEMERA_PATCH_INDEX 0)
FOREACH(HEMERA_PATCH ${HEMERA_LLVM_PATCHES})
  GET_FILENAME_COMPONENT(HEMERA_PATCH_NAME ${HEMERA_PATCH} NAME)
  MATH(EXPR HEMERA_PATCH_INDEX "${HEMERA_PATCH_INDEX} + 1")
  IF(NOT HEMERA_PATCH_INDEX GREATER HEMERA_PATCHES_APPLIED)
    CONTINUE()
  ENDIF()
  EXECUTE_PROCESS(COMMAND ${GIT_EXECUTABLE} apply ${HEMERA_PATCH}
    WORKING_DIRECTORY ${LLVM_SOURCE_DIR} RESULT_VARIABLE HEMERA_PATCH_FAILED ERROR_VARIABLE HEMERA_PATCH_ERROR)
  IF(NOT HEMERA_PATCH_FAILED EQUAL 0)
    MESSAGE(FATAL_ERROR "The LLVM patch ${HEMERA_PATCH_NAME} doesn't apply to ${LLVM_SOURCE_DIR}:\n${HEMERA_PATCH_ERROR}")
  ENDIF()
  MESSAGE(STATUS "Applied the LLVM patch ${HEMERA_PATCH_NAME}")
ENDFOREACH()
