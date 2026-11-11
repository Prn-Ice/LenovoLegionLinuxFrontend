#pragma once

#include <string>

namespace legion_control {
// Validate every selector, link target, directory, and executable against the
// host's root ownership. Returns the executable's canonical path.
bool TrustedExecutable(const std::string &input, std::string *resolved);

// Inspect fixed administrator-controlled installation locations, in order.
// A present but unsafe candidate stops discovery; the caller receives a reason.
std::string FindHostLegionCli(std::string *error);
} // namespace legion_control
