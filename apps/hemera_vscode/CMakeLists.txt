# The VS Code extension (docs/editor.md), packaged as hemera.vsix beside hemera-lsp, to install by hand. Built only by
# name, cmake --build <folder> --target HemeraVscode, as npm ci fetches its packages, and only where npm is found. It's
# packaged in a copy in the build folder, so node_modules and the package never land in the source tree.
FIND_PROGRAM(HEMERA_NPM NAMES npm.cmd npm)
IF(NOT HEMERA_NPM)
  MESSAGE(STATUS "npm not found: no HemeraVscode target for the VS Code extension")
  RETURN()
ENDIF()

SET(HEMERA_VSCODE_FILES
  extension.js
  language-configuration.json
  package.json
  package-lock.json
  .vscodeignore
  README.md
  syntaxes/hemera.tmLanguage.json
)
SET(HEMERA_VSCODE_COPY ${CMAKE_CURRENT_BINARY_DIR}/extension)
# Made now, as the build step starts in it
FILE(MAKE_DIRECTORY ${HEMERA_VSCODE_COPY}/syntaxes)
# npm is a batch file on Windows, which ends the build step's own unless it's run through cmd
IF(WIN32)
  SET(HEMERA_NPM_COMMAND cmd /c ${HEMERA_NPM})
ELSE()
  SET(HEMERA_NPM_COMMAND ${HEMERA_NPM})
ENDIF()
SET(HEMERA_VSCODE_SOURCES)
SET(HEMERA_VSCODE_COPIES)
FOREACH(FILE ${HEMERA_VSCODE_FILES})
  LIST(APPEND HEMERA_VSCODE_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/${FILE})
  LIST(APPEND HEMERA_VSCODE_COPIES COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_SOURCE_DIR}/${FILE}
    ${HEMERA_VSCODE_COPY}/${FILE})
ENDFOREACH()

ADD_CUSTOM_TARGET(HemeraVscode
  ${HEMERA_VSCODE_COPIES}
  COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_SOURCE_DIR}/LICENSE ${HEMERA_VSCODE_COPY}/LICENSE
  COMMAND ${HEMERA_NPM_COMMAND} ci --no-audit --no-fund
  COMMAND ${HEMERA_NPM_COMMAND} exec --no -- vsce package --allow-missing-repository
    --out $<TARGET_FILE_DIR:HemeraLsp>/hemera.vsix
  WORKING_DIRECTORY ${HEMERA_VSCODE_COPY}
  SOURCES ${HEMERA_VSCODE_SOURCES}
  COMMENT "Packaging the VS Code extension as hemera.vsix"
  VERBATIM
)
ADD_DEPENDENCIES(HemeraVscode HemeraLsp)
