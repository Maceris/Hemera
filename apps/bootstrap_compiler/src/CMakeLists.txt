# Hemera compiler source

CMAKE_MINIMUM_REQUIRED(VERSION 3.13...3.31.4)

SET(HEADER_FILES
  ${INCLUDE_DIR}/job.h
  ${INCLUDE_DIR}/version.h
  ${INCLUDE_DIR}/cmd_line/arg_parsing.h
  ${INCLUDE_DIR}/memory/allocator.h
  ${INCLUDE_DIR}/memory/thread_safe_queue.h
  ${INCLUDE_DIR}/util/logger.h
  ${INCLUDE_DIR}/util/thread_pool.h
)

SET(SOURCE_FILES
  ${SOURCE_DIR}/main.cpp
  ${SOURCE_DIR}/cmd_line/arg_parsing.cpp
  ${SOURCE_DIR}/util/logger.cpp
  ${SOURCE_DIR}/util/thread_pool.cpp
)

SET(THIRD_PARTY_HEADER_FILES
  
)


ADD_EXECUTABLE(Hemera
  ${HEADER_FILES}
  ${THIRD_PARTY_HEADER_FILES}
  
  ${SOURCE_FILES}
)

TARGET_INCLUDE_DIRECTORIES(Hemera PUBLIC
  ${INCLUDE_DIR}/
)

SOURCE_GROUP(TREE ${INCLUDE_DIR} PREFIX "include" FILES ${HEADER_FILES})
SOURCE_GROUP(TREE ${SOURCE_DIR} PREFIX "src" FILES ${SOURCE_FILES})

TARGET_USE_COMMON_OUTPUT_DIRECTORY(Hemera)

TARGET_LINK_LIBRARIES(Hemera)
SET_TARGET_PROPERTIES(Hemera PROPERTIES OUTPUT_NAME "hemera")
