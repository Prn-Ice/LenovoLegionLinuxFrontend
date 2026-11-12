#pragma once

#include <string>
#include <vector>

namespace legion_control {
// Copies a regular ELF executable into a sealed memfd. The returned descriptor
// belongs to the caller. Errors return -1 and explain why approval must stop.
// Dynamic executables must use root-controlled host loader and search paths.
int CreateExecutableSnapshot(int source_fd, std::string *error);
int CreateExecutableSnapshot(const std::vector<unsigned char> &bytes,
                             std::string *error);
} // namespace legion_control
