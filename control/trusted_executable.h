#pragma once

#include <string>

namespace legion_control {
// Validate every selector, link target, directory, and executable against the
// host's root ownership. Returns the executable's canonical path.
bool TrustedExecutable(const std::string &input, std::string *resolved);

// Applies the same ownership and traversal checks to host library directories.
bool TrustedDirectory(const std::string &input, std::string *resolved);

enum class CliAccess { privileged, readOnly };

// Select a canonical CLI from fixed host locations. Privileged use requires
// root-controlled paths. Read-only discovery establishes no root trust; the
// helper independently validates the same selected path before any writes.
std::string FindHostLegionCli(std::string *error,
                              CliAccess access = CliAccess::privileged);
} // namespace legion_control
