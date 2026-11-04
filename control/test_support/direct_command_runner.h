#pragma once
#include "managed_command.h"

namespace legion_control {
// Ordinary-user fixtures only. This runner supplies no process-tree
// containment.
std::shared_ptr<ManagedCommandRunner> CreateDirectCommandRunner();
} // namespace legion_control
