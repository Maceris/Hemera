# hemera-format: lays Hemera files out to the style rules, with the compiler's own lexer, parser and printer
# (HemeraLib). hemera-format-debug for Debug, so both builds can be on PATH and be run by name.
ADD_EXECUTABLE(HemeraFormat src/main.cpp ${HEMERA_TOOL_MANIFEST})
TARGET_LINK_LIBRARIES(HemeraFormat HemeraLib)
TARGET_COMPILE_DEFINITIONS(HemeraFormat PRIVATE ${HEMERA_TOOL_DEFINITIONS})
TARGET_COMPILE_OPTIONS(HemeraFormat PRIVATE ${HEMERA_TOOL_OPTIONS})
ADD_DEPENDENCIES(HemeraFormat HemeraGenerated)
SET_TARGET_PROPERTIES(HemeraFormat PROPERTIES OUTPUT_NAME "hemera-format" OUTPUT_NAME_DEBUG "hemera-format-debug"
  MSVC_RUNTIME_LIBRARY "${HEMERA_TOOL_RUNTIME_LIBRARY}")
IF(MSVC)
  # A PDB for Release too, so a crash has names
  TARGET_LINK_OPTIONS(HemeraFormat PRIVATE $<$<CONFIG:Release>:/DEBUG /OPT:REF /OPT:ICF>)
ENDIF()
