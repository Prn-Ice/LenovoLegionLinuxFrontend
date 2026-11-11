#pragma once

#include <glib.h>
#include <string>

namespace legion_control {
inline bool ValidPortableUnit(const std::string &unit) {
  const char *prefixes[] = {"legion-portable-control-",
                            "legion-bootstrap-probe-"};
  for (const auto *prefix : prefixes) {
    const std::string name(prefix);
    if (unit.size() == name.size() + 36 + 8 &&
        unit.compare(0, name.size(), name) == 0 &&
        unit.compare(unit.size() - 8, 8, ".service") == 0 &&
        g_uuid_string_is_valid(unit.substr(name.size(), 36).c_str()))
      return true;
  }
  return false;
}
} // namespace legion_control
