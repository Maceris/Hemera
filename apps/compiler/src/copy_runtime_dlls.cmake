# Copy the DLLs some programs load, and the DLLs those load, into a folder, leaving out the system's own, so the
# programs run from there with nothing on the PATH: the compiler and lld beside it, and the DLLs LLVM was built
# against, like vcpkg's zlib and libxml2, whose libxml2 loads iconv.
#
#     cmake -DEXECUTABLES=<a;b> -DDESTINATION=<folder> -DFOLDERS=<c;d> -P copy_runtime_dlls.cmake
#
# EXECUTABLES are the programs, DESTINATION where the DLLs go, and FOLDERS where they're looked for besides the PATH
# this runs with. A DLL found nowhere is left out, which the program then reports when it's run, as without this.

IF(NOT EXECUTABLES OR NOT DESTINATION)
  MESSAGE(FATAL_ERROR "copy_runtime_dlls.cmake needs EXECUTABLES and DESTINATION")
ENDIF()

SET(SEARCHED ${FOLDERS})
IF(WIN32)
  FILE(TO_CMAKE_PATH "$ENV{PATH}" PATH_FOLDERS)
  LIST(APPEND SEARCHED ${PATH_FOLDERS})
ENDIF()

FILE(GET_RUNTIME_DEPENDENCIES
  EXECUTABLES ${EXECUTABLES}
  RESOLVED_DEPENDENCIES_VAR RESOLVED
  UNRESOLVED_DEPENDENCIES_VAR UNRESOLVED
  DIRECTORIES ${SEARCHED}
  # The system's own: its API sets, and whatever's in the Windows folder
  PRE_EXCLUDE_REGEXES "^api-ms-" "^ext-ms-"
  POST_EXCLUDE_REGEXES ".*[/\\\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\\\].*")

FOREACH(DLL ${RESOLVED})
  FILE(COPY ${DLL} DESTINATION ${DESTINATION})
ENDFOREACH()
