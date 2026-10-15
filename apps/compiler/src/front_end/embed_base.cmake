# Writes OUTPUT, a C++ source holding every .hsc file under BASE_DIR, so the compiler supplies base
# itself instead of reading it from disk while compiling.
#
# cmake -DBASE_DIR=<path to base> -DOUTPUT=<file to write> -P embed_base.cmake
#
# Each file is a list of parts of at most 4 KiB, joined when it's loaded, so no string literal comes
# near the 64 KiB that compilers are required to support.

file(GLOB_RECURSE files RELATIVE "${BASE_DIR}" "${BASE_DIR}/*.hsc")
list(SORT files)

set(parts_out "")
set(files_out "")
set(index 0)

foreach(file ${files})
  get_filename_component(folder "${file}" DIRECTORY)
  get_filename_component(name "${file}" NAME)
  file(READ "${BASE_DIR}/${file}" hex HEX)
  string(LENGTH "${hex}" hex_length)

  string(APPEND parts_out "\t// ${file}\n\tstatic constexpr std::string_view FILE_${index}_PARTS[] = {\n")
  set(part_start 0)
  while(part_start LESS hex_length)
    # One part: 4 KiB, written 64 bytes to a line, every byte escaped
    string(SUBSTRING "${hex}" ${part_start} 8192 part)
    string(LENGTH "${part}" part_hex_length)
    math(EXPR part_length "${part_hex_length} / 2")
    string(APPEND parts_out "\t\tstd::string_view(")
    set(line_start 0)
    while(line_start LESS part_hex_length)
      string(SUBSTRING "${part}" ${line_start} 128 line)
      string(REGEX REPLACE "([0-9a-f][0-9a-f])" "\\\\x\\1" line "${line}")
      string(APPEND parts_out "\n\t\t\t\"${line}\"")
      math(EXPR line_start "${line_start} + 128")
    endwhile()
    string(APPEND parts_out ", ${part_length}),\n")
    math(EXPR part_start "${part_start} + 8192")
  endwhile()
  if(hex_length EQUAL 0)
    string(APPEND parts_out "\t\tstd::string_view(),\n")
  endif()
  string(APPEND parts_out "\t};\n\n")

  string(APPEND files_out "\t\t{ \"${folder}\", \"${name}\", FILE_${index}_PARTS },\n")
  math(EXPR index "${index} + 1")
endforeach()

set(out "// Generated from base/ by src/front_end/embed_base.cmake. Don't edit.\n")
string(APPEND out "#include \"front_end/base_sources.h\"\n\nnamespace hemera {\n")
string(APPEND out "${parts_out}")
string(APPEND out "\tstatic constexpr EmbeddedFile EMBEDDED_BASE_FILES[] = {\n${files_out}\t};\n\n")
string(APPEND out "\tstd::span<const EmbeddedFile> embedded_base_files() {\n")
string(APPEND out "\t\treturn EMBEDDED_BASE_FILES;\n\t}\n}\n")

# Only rewrite when it changes, so the compiler isn't rebuilt for nothing
set(previous "")
if(EXISTS "${OUTPUT}")
  file(READ "${OUTPUT}" previous)
endif()
if(NOT previous STREQUAL out)
  file(WRITE "${OUTPUT}" "${out}")
endif()
