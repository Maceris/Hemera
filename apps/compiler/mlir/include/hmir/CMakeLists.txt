# HMIR include

INCLUDE_DIRECTORIES(SYSTEM
  ${LLVM_INCLUDE_DIRS}
  ${MLIR_INCLUDE_DIRS}
  ${THIRD_PARTY_DIR}/llvm-project/mlir/include
  ${THIRD_PARTY_DIR}/llvm-project/llvm/include
  $<BUILD_INTERFACE:${HEMERA_LIBRARY_OUTPUT_DIRECTORY}/third-party/llvm-project/llvm/include>
)

ADD_MLIR_DIALECT(hmir_ops hmir)
ADD_MLIR_DOC(hmir_dialect hmir_dialect dialects/ -gen-dialect-doc)
ADD_MLIR_DOC(hmir_ops hmir_ops dialects/ -gen-op-doc)
