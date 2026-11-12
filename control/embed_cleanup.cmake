file(READ "${INPUT}" image HEX)
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," image "${image}")
file(WRITE "${OUTPUT}" "constexpr unsigned char legion_cleanup_image[] = {${image}};\n")
