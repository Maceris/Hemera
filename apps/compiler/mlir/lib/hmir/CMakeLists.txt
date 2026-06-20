# HMIR lib

add_mlir_dialect_library(HMIR
  ${HEMERA_MLIR_DIR}/lib/hmir/hmir_dialect.cpp
  ${HEMERA_MLIR_DIR}/lib/hmir/ir/hmir_ops.cpp

  DEPENDS
  MLIRhmir_opsIncGen

  LINK_COMPONENTS
  Core
)

TARGET_INCLUDE_DIRECTORIES(HMIR PUBLIC
  $<BUILD_INTERFACE:${INCLUDE_DIR}/>
  $<BUILD_INTERFACE:${HEMERA_MLIR_DIR}/include>
)

TARGET_LINK_LIBRARIES(HMIR PUBLIC MLIRIR)
