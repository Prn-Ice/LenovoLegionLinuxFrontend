#pragma once

#include <string>
#include <sys/types.h>

namespace legion_control {
namespace bundled_dart {

// Checks the systemd-owned directory, then creates a private root-owned bundle.
bool Stage(const std::string &unit, std::string *runtime, std::string *error);

#ifdef LEGION_BUNDLED_DART_TEST
bool StageForTest(const std::string &parent, const std::string &unit,
                  uid_t owner, std::string *runtime, std::string *error);
#endif

}  // namespace bundled_dart
}  // namespace legion_control
